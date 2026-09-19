import 'dart:convert';
import '../../core/utils/logger.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:http/http.dart' as http;
import '../../models/music_model.dart';

class MusicSearchService {
  static final MusicSearchService _instance = MusicSearchService._internal();
  factory MusicSearchService() => _instance;
  MusicSearchService._internal();

  final Map<String, MusicSearchSource> _sources = {
    'kw': KwSearchSource(),
    'kg': KgSearchSource(),
    'tx': TxSearchSource(),
    'wy': WySearchSource(),
  };

  /// 搜索源列表 —— 对齐原版 musicSdk/index.js：四源 + 全部
  /// 注：mg（咪咕）suggest/搜索接口已 301 跳转网页版失效，故下线
  static const List<String> availableSources = ['kw', 'kg', 'tx', 'wy', 'all'];

  /// 音源显示名 —— 对齐原版
  static const Map<String, String> sourceNames = {
    'kw': '源一',
    'kg': '源二',
    'tx': '源三',
    'wy': '源四',
    'all': '全部',
  };

  Future<SearchResult> search({
    required String keyword,
    required String source,
    int page = 1,
    int pageSize = 30,
  }) async {
    if (source == 'all') {
      return _searchAll(keyword: keyword, page: page, pageSize: pageSize);
    }
    final searchSource = _sources[source];
    if (searchSource == null) {
      throw Exception('不支持的音源: $source');
    }
    return searchSource.search(keyword: keyword, page: page, pageSize: pageSize);
  }

  /// 全部源并行搜索（匹配洛雪 "all" 行为）
  Future<SearchResult> _searchAll({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async {
    final results = await Future.wait(
      _sources.entries.map((entry) async {
        try {
          return await entry.value.search(
            keyword: keyword,
            page: page,
            pageSize: pageSize,
          );
        } catch (e) {
          logDebug('源 ${entry.key} 搜索失败: $e');
          return SearchResult(list: [], total: 0, page: page, pageSize: pageSize, source: entry.key);
        }
      }),
    );

    final allList = <MusicInfo>[];
    var total = 0;
    for (final r in results) {
      allList.addAll(r.list);
      total += r.total;
    }

    return SearchResult(
      list: allList,
      total: total,
      page: page,
      pageSize: pageSize,
      source: 'all',
    );
  }
}

abstract class MusicSearchSource {
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  });
}

// 酷我音乐搜索
class KwSearchSource extends MusicSearchSource {
  @override
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async {
    // 对齐原版：SHOW=0 且 TOTAL!=0 时重试（最多2次）
    for (var retry = 0; retry < 3; retry++) {
      try {
        final result = await _searchOnce(keyword: keyword, page: page, pageSize: pageSize);
        final show = result['SHOW']?.toString();
        final total = result['TOTAL']?.toString() ?? '0';
        if (total != '0' && show == '0' && retry < 2) continue;
        return result['result'] as SearchResult;
      } catch (e) {
        if (retry >= 2) rethrow;
      }
    }
    throw Exception('酷我搜索失败');
  }

  Future<Map<String, dynamic>> _searchOnce({
    required String keyword,
    required int page,
    required int pageSize,
  }) async {
    final url = Uri.parse(
      'http://search.kuwo.cn/r.s?client=kt&all=${Uri.encodeComponent(keyword)}&pn=${page - 1}&rn=$pageSize&uid=794762570&ver=kwplayer_ar_9.2.2.1&vipver=1&show_copyright_off=1&newver=1&ft=music&cluster=0&strategy=2012&encoding=utf8&rformat=json&vermerge=1&mobi=1&issubtitle=1',
    );

    final response = await http.get(url).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('搜索请求失败');
    }
    final data = jsonDecode(response.body);
    final absList = data['abslist'] as List? ?? [];
    final total = int.tryParse(data['TOTAL']?.toString() ?? '0') ?? 0;

    final results = absList.map((item) => _parseItem(item)).toList();

    return {
      'SHOW': data['SHOW']?.toString(),
      'TOTAL': data['TOTAL']?.toString(),
      'result': SearchResult(
        list: results,
        total: total,
        page: page,
        pageSize: pageSize,
        source: 'kw',
      ),
    };
  }

  MusicInfo _parseItem(Map<String, dynamic> item) {
    final songId = (item['MUSICRID']?.toString() ?? '').replaceFirst('MUSIC_', '');
    final name = _decodeHtml(item['SONGNAME']?.toString() ?? '');
    final artist = _decodeHtml(item['ARTIST']?.toString() ?? '');
    final album = _decodeHtml(item['ALBUM']?.toString() ?? '');
    final duration = int.tryParse(item['DURATION']?.toString() ?? '0') ?? 0;
    final imgUrl = item['WEB_ALBUM_PIC']?.toString();

    final types = _parseKwTypes(item['N_MINFO']?.toString() ?? '');

    return MusicInfo(
      id: 'kw_$songId',
      name: name,
      singer: artist,
      album: album,
      source: 'kw',
      songId: songId,
      songmid: songId,
      duration: duration,
      imgUrl: imgUrl,
      types: types.isNotEmpty ? types : null,
    );
  }

  List<QualityType> _parseKwTypes(String minfo) {
    final types = <QualityType>[];
    final regExp = RegExp(r'level:(\w+),bitrate:(\d+),format:(\w+),size:([\w.]+)');

    for (final match in regExp.allMatches(minfo)) {
      final bitrate = match.group(2);
      final size = match.group(4);

      String type;
      switch (bitrate) {
        case '4000':
          type = 'flac24bit';
          break;
        case '2000':
          type = 'flac';
          break;
        case '320':
          type = '320k';
          break;
        case '128':
          type = '128k';
          break;
        default:
          continue;
      }
      types.add(QualityType(type: type, size: size ?? ''));
    }

    return types;
  }

  String _decodeHtml(String str) {
    return str
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }
}

// 酷狗音乐搜索
class KgSearchSource extends MusicSearchSource {
  @override
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async {
    try {
      final url = Uri.parse(
        'https://songsearch.kugou.com/song_search_v2?keyword=${Uri.encodeComponent(keyword)}&page=$page&pagesize=$pageSize&userid=0&clientver=&platform=WebFilter&filter=2&iscorrection=1&privilege_filter=0&area_code=1',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['error_code'] != 0) {
          throw Exception('搜索错误: ${data['error_code']}');
        }

        final lists = data['data']['lists'] as List? ?? [];
        final total = data['data']['total'] ?? 0;

        final results = <MusicInfo>[];
        final ids = <String>{};

        for (final item in lists) {
          final music = _parseItem(item);
          final key = '${music.songId}_${music.name}';
          if (!ids.contains(key)) {
            ids.add(key);
            results.add(music);
          }
        }

        return SearchResult(
          list: results,
          total: total,
          page: page,
          pageSize: pageSize,
          source: 'kg',
        );
      }
      throw Exception('搜索请求失败');
    } catch (e) {
      throw Exception('酷狗搜索失败: $e');
    }
  }

  MusicInfo _parseItem(Map<String, dynamic> item) {
    final songId = item['Audioid']?.toString() ?? '';
    final name = _decodeHtml(item['SongName']?.toString() ?? '');
    final singers = item['Singers'] as List? ?? [];
    final artist = singers.map((s) => s['name']?.toString() ?? '').join('、');
    final album = _decodeHtml(item['AlbumName']?.toString() ?? '');
    final duration = item['Duration'] ?? 0;

    final types = <QualityType>[];
    if ((item['FileSize'] ?? 0) != 0) {
      types.add(QualityType(type: '128k', size: _formatSize(item['FileSize'])));
    }
    if ((item['HQFileSize'] ?? 0) != 0) {
      types.add(QualityType(type: '320k', size: _formatSize(item['HQFileSize'])));
    }
    if ((item['SQFileSize'] ?? 0) != 0) {
      types.add(QualityType(type: 'flac', size: _formatSize(item['SQFileSize'])));
    }
    if ((item['ResFileSize'] ?? 0) != 0) {
      types.add(QualityType(type: 'flac24bit', size: _formatSize(item['ResFileSize'])));
    }

    return MusicInfo(
      id: 'kg_$songId',
      name: name,
      singer: artist,
      album: album,
      source: 'kg',
      songId: songId,
      hash: songId,
      duration: duration,
      types: types.isNotEmpty ? types : null,
    );
  }

  String _formatSize(dynamic size) {
    final bytes = size is int ? size : int.tryParse(size?.toString() ?? '0') ?? 0;
    if (bytes == 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    int i = 0;
    double sizeValue = bytes.toDouble();
    while (sizeValue >= 1024 && i < units.length - 1) {
      sizeValue /= 1024;
      i++;
    }
    return '${sizeValue.toStringAsFixed(2)} ${units[i]}';
  }

  String _decodeHtml(String str) {
    return str
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }
}

// QQ音乐搜索
class TxSearchSource extends MusicSearchSource {
  @override
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async {
    try {
      final data = {
        'comm': {
          'ct': '11',
          'cv': '14090508',
          'v': '14090508',
          'tmeAppID': 'qqmusic',
          'phonetype': 'EBG-AN10',
          'deviceScore': '553.47',
          'devicelevel': '50',
          'newdevicelevel': '20',
          'rom': 'HuaWei/EMOTION/EmotionUI_14.2.0',
          'os_ver': '12',
          'OpenUDID': '0',
          'OpenUDID2': '0',
          'QIMEI36': '0',
          'udid': '0',
          'chid': '0',
          'aid': '0',
          'oaid': '0',
          'taid': '0',
          'tid': '0',
          'wid': '0',
          'uid': '0',
          'sid': '0',
          'modeSwitch': '6',
          'teenMode': '0',
          'ui_mode': '2',
          'nettype': '1020',
          'v4ip': '',
        },
        'req': {
          'module': 'music.search.SearchCgiService',
          'method': 'DoSearchForQQMusicMobile',
          'param': {
            'search_type': 0,
            'searchid': _generateSearchId(),
            'query': keyword,
            'page_num': page,
            'num_per_page': pageSize,
            'highlight': 0,
            'nqc_flag': 0,
            'multi_zhida': 0,
            'cat': 2,
            'grp': 1,
            'sin': 0,
            'sem': 0,
          },
        },
      };

      final sign = _zzcSign(jsonEncode(data));
      final url = Uri.parse('https://u.y.qq.com/cgi-bin/musics.fcg?sign=$sign');

      // 使用原始请求避免 Content-Type 解析错误
      final client = http.Client();
      final request = http.Request('POST', url)
        ..headers['Content-Type'] = 'application/json'
        ..headers['User-Agent'] = 'QQMusic 14090508(android 12)'
        ..body = jsonEncode(data);
      final streamedResponse = await client.send(request).timeout(const Duration(seconds: 15));
      final responseBody = await streamedResponse.stream.bytesToString();
      client.close();

      if (streamedResponse.statusCode == 200) {
        final responseData = jsonDecode(responseBody);
        if (responseData['code'] != 0) {
          throw Exception('搜索错误');
        }

        final body = responseData['req']['data']['body'];
        final songList = body?['item_song'] as List? ?? [];
        final total = responseData['req']['data']['meta']?['estimate_sum'] ?? 0;

        final results = songList.map((item) => _parseItem(item)).toList();

        return SearchResult(
          list: results,
          total: total,
          page: page,
          pageSize: pageSize,
          source: 'tx',
        );
      }
      throw Exception('搜索请求失败');
    } catch (e) {
      throw Exception('QQ音乐搜索失败: $e');
    }
  }

  MusicInfo _parseItem(Map<String, dynamic> item) {
    final songId = item['id']?.toString() ?? '';
    final songmid = item['mid']?.toString() ?? '';
    final name = item['title']?.toString() ?? '';
    final singers = item['singer'] as List? ?? [];
    final artist = singers.map((s) => s['name']?.toString() ?? '').join('、');
    final album = item['album']?['name']?.toString() ?? '';
    final albumMid = item['album']?['mid']?.toString() ?? '';
    final duration = item['interval'] ?? 0;
    final file = item['file'] as Map? ?? {};
    final strMediaMid = file['media_mid']?.toString() ?? '';

    final types = <QualityType>[];
    if ((file['size_128mp3'] ?? 0) != 0) {
      types.add(QualityType(type: '128k', size: _formatSize(file['size_128mp3'])));
    }
    if ((file['size_320mp3'] ?? 0) != 0) {
      types.add(QualityType(type: '320k', size: _formatSize(file['size_320mp3'])));
    }
    if ((file['size_flac'] ?? 0) != 0) {
      types.add(QualityType(type: 'flac', size: _formatSize(file['size_flac'])));
    }
    if ((file['size_hires'] ?? 0) != 0) {
      types.add(QualityType(type: 'flac24bit', size: _formatSize(file['size_hires'])));
    }

    final img = albumMid.isNotEmpty
        ? 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$albumMid.jpg'
        : null;

    return MusicInfo(
      id: 'tx_$songmid',
      name: name,
      singer: artist,
      album: album,
      source: 'tx',
      songId: songId,
      songmid: songmid,
      strMediaMid: strMediaMid,
      duration: duration,
      imgUrl: img,
      types: types.isNotEmpty ? types : null,
    );
  }

  String _zzcSign(String text) {
    final bytes = utf8.encode(text);
    final digest = sha1.convert(bytes);
    final hash = digest.toString();

    const part1Indexes = [23, 14, 6, 36, 16, 40, 7, 19];
    const part2Indexes = [16, 1, 32, 12, 19, 27, 8, 5];
    const scrambleValues = [89, 39, 179, 150, 218, 82, 58, 252, 177, 52,
        186, 123, 120, 64, 242, 133, 143, 161, 121, 179];

    // JS: hash[i] returns undefined when out of bounds; join turns it into ''
    String pickHash(int idx) => idx < hash.length ? hash[idx] : '';

    final part1 = part1Indexes.map(pickHash).join();
    final part2 = part2Indexes.map(pickHash).join();

    final part3 = List<int>.generate(20, (i) {
      final hashByte = int.parse(hash.substring(i * 2, i * 2 + 2), radix: 16);
      return scrambleValues[i] ^ hashByte;
    });

    final b64Part = base64.encode(part3).replaceAll(RegExp(r'[\\/+=]'), '');

    return 'zzc${part1}${b64Part}${part2}'.toLowerCase();
  }

  String _generateSearchId() {
    final random = DateTime.now().millisecondsSinceEpoch;
    return random.toString();
  }

  String _formatSize(dynamic size) {
    final bytes = size is int ? size : int.tryParse(size?.toString() ?? '0') ?? 0;
    if (bytes == 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    int i = 0;
    double sizeValue = bytes.toDouble();
    while (sizeValue >= 1024 && i < units.length - 1) {
      sizeValue /= 1024;
      i++;
    }
    return '${sizeValue.toStringAsFixed(2)} ${units[i]}';
  }
}

// 网易云音乐搜索
class WySearchSource extends MusicSearchSource {
  static const String _eapiKey = 'e82ckenh8dichen8';

  @override
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async {
    try {
      final requestData = {
        'keyword': keyword,
        'needCorrect': '1',
        'channel': 'typing',
        'offset': pageSize * (page - 1),
        'scene': 'normal',
        'total': page == 1,
        'limit': pageSize,
      };

      final params = _eapi('/api/search/song/list/page', jsonEncode(requestData));

      final response = await http.post(
        Uri.parse('http://interface.music.163.com/eapi/batch'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36',
          'origin': 'https://music.163.com',
        },
        body: {'params': params},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] != 200) {
          throw Exception('搜索错误');
        }

        final resources = data['data']['resources'] as List? ?? [];
        final totalCount = data['data']['totalCount'] ?? 0;

        final results = resources.map((item) => _parseItem(item)).toList();

        return SearchResult(
          list: results,
          total: totalCount,
          page: page,
          pageSize: pageSize,
          source: 'wy',
        );
      }
      throw Exception('搜索请求失败');
    } catch (e) {
      throw Exception('网易云搜索失败: $e');
    }
  }

  MusicInfo _parseItem(Map<String, dynamic> item) {
    final baseInfo = item['baseInfo'] as Map? ?? {};
    final songData = baseInfo['simpleSongData'] as Map? ?? {};
    final songId = songData['id']?.toString() ?? '';
    final name = songData['name']?.toString() ?? '';
    final singers = songData['ar'] as List? ?? [];
    final artist = singers.map((s) => s['name']?.toString() ?? '').join('、');
    final albumData = songData['al'] as Map? ?? {};
    final album = albumData['name']?.toString() ?? '';
    final duration = (songData['dt'] ?? 0) ~/ 1000;
    final img = albumData['picUrl']?.toString();

    final privilege = songData['privilege'] as Map? ?? {};
    final maxbr = privilege['maxbr'] ?? 0;
    final maxBrLevel = privilege['maxBrLevel']?.toString() ?? '';

    final types = <QualityType>[];
    if (maxBrLevel == 'hires') {
      final hrSize = songData['hr']?['size'] ?? 0;
      types.add(QualityType(type: 'flac24bit', size: _formatSize(hrSize)));
    }
    if (maxbr >= 999000) {
      final sqSize = songData['sq']?['size'] ?? 0;
      types.add(QualityType(type: 'flac', size: _formatSize(sqSize)));
    }
    if (maxbr >= 320000) {
      final hSize = songData['h']?['size'] ?? 0;
      types.add(QualityType(type: '320k', size: _formatSize(hSize)));
    }
    if (maxbr >= 128000) {
      final lSize = songData['l']?['size'] ?? 0;
      types.add(QualityType(type: '128k', size: _formatSize(lSize)));
    }

    return MusicInfo(
      id: 'wy_$songId',
      name: name,
      singer: artist,
      album: album,
      source: 'wy',
      songId: songId,
      songmid: songId,
      duration: duration,
      imgUrl: img,
      types: types.isNotEmpty ? types : null,
    );
  }

  String _eapi(String url, String text) {
    final message = 'nobody${url}use${text}md5forencrypt';
    final digest = md5.convert(utf8.encode(message)).toString();
    final data = '$url-36cd479b6b5-$text-36cd479b6b5-$digest';

    final keyBytes = utf8.encode(_eapiKey);
    final key = Key(keyBytes);
    final encrypter = Encrypter(AES(key, mode: AESMode.ecb, padding: 'PKCS7'));
    final encrypted = encrypter.encryptBytes(utf8.encode(data));

    return encrypted.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  }

  String _formatSize(dynamic size) {
    final bytes = size is int ? size : int.tryParse(size?.toString() ?? '0') ?? 0;
    if (bytes == 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    int i = 0;
    double sizeValue = bytes.toDouble();
    while (sizeValue >= 1024 && i < units.length - 1) {
      sizeValue /= 1024;
      i++;
    }
    return '${sizeValue.toStringAsFixed(2)} ${units[i]}';
  }
}

// 咪咕音乐搜索
class MgSearchSource extends MusicSearchSource {
  static const String _deviceId = '963B7AA0D21511ED807EE5846EC87D20';
  static const String _signatureMd5 = '6cdc72a439cef99a3418d2a78aa28c73';

  @override
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final sign = _createSignature(timestamp, keyword);

      final url = Uri.parse(
        'https://jadeite.migu.cn/music_search/v3/search/searchAll?isCorrect=0&isCopyright=1&searchSwitch=%7B%22song%22%3A1%2C%22album%22%3A0%2C%22singer%22%3A0%2C%22tagSong%22%3A1%2C%22mvSong%22%3A0%2C%22bestShow%22%3A1%2C%22songlist%22%3A0%2C%22lyricSong%22%3A0%7D&pageSize=$pageSize&text=${Uri.encodeComponent(keyword)}&pageNo=$page&sort=0&sid=USS',
      );

      final response = await http.get(url, headers: {
        'uiVersion': 'A_music_3.6.1',
        'deviceId': _deviceId,
        'timestamp': timestamp,
        'sign': sign,
        'channel': '0146921',
        'User-Agent': 'Mozilla/5.0 (Linux; U; Android 11.0.0; zh-cn; MI 11)',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] != '000000') {
          throw Exception('搜索错误');
        }

        final songResult = data['songResultData'] as Map? ?? {};
        final resultList = songResult['resultList'] as List? ?? [];
        final totalCount = songResult['totalCount'] ?? 0;

        final results = <MusicInfo>[];
        final ids = <String>{};

        for (final group in resultList) {
          if (group is List) {
            for (final item in group) {
              final music = _parseItem(item);
              final songId = music.songId ?? '';
              if (songId.isNotEmpty && !ids.contains(songId)) {
                ids.add(songId);
                results.add(music);
              }
            }
          }
        }

        return SearchResult(
          list: results,
          total: totalCount,
          page: page,
          pageSize: pageSize,
          source: 'mg',
        );
      }
      throw Exception('搜索请求失败');
    } catch (e) {
      throw Exception('咪咕搜索失败: $e');
    }
  }

  MusicInfo _parseItem(Map<String, dynamic> item) {
    final songId = item['songId']?.toString() ?? '';
    final copyrightId = item['copyrightId']?.toString() ?? '';
    final name = item['name']?.toString() ?? '';
    final singerList = item['singerList'] as List? ?? [];
    final artist = singerList.map((s) => s['name']?.toString() ?? '').join('、');
    final album = item['album']?.toString() ?? '';
    final duration = item['duration'] ?? 0;

    final img = item['img3']?.toString() ??
        item['img2']?.toString() ??
        item['img1']?.toString();

    final types = <QualityType>[];
    final audioFormats = item['audioFormats'] as List? ?? [];
    for (final format in audioFormats) {
      final formatType = format['formatType']?.toString();
      final asize = format['asize'] ?? format['isize'];
      switch (formatType) {
        case 'PQ':
          types.add(QualityType(type: '128k', size: asize?.toString() ?? ''));
          break;
        case 'HQ':
          types.add(QualityType(type: '320k', size: asize?.toString() ?? ''));
          break;
        case 'SQ':
          types.add(QualityType(type: 'flac', size: asize?.toString() ?? ''));
          break;
        case 'ZQ24':
          types.add(QualityType(type: 'flac24bit', size: asize?.toString() ?? ''));
          break;
      }
    }

    return MusicInfo(
      id: 'mg_$copyrightId',
      name: name,
      singer: artist,
      album: album,
      source: 'mg',
      songId: songId,
      copyrightId: copyrightId,
      duration: duration,
      imgUrl: img,
      types: types.isNotEmpty ? types : null,
    );
  }

  String _createSignature(String time, String keyword) {
    final signStr = '${keyword}${_signatureMd5}yyapp2d16148780a1dcc7408e06336b98cfd50${_deviceId}${time}';
    return md5.convert(utf8.encode(signStr)).toString();
  }
}

// 搜索结果模型
class SearchResult {
  final List<MusicInfo> list;
  final int total;
  final int page;
  final int pageSize;
  final String source;

  SearchResult({
    required this.list,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.source,
  });

  bool get hasMore => list.length < total;
}
