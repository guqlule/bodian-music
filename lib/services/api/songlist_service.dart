import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import '../../core/utils/logger.dart';
import 'package:http/http.dart' as http;
import '../../models/music_model.dart';

/// 在线歌单信息
class SonglistInfo {
  final String id;
  final String name;
  final String author;
  final String imgUrl;
  final int playCount;
  final int songCount;
  final String desc;
  final String source;

  SonglistInfo({
    required this.id,
    required this.name,
    required this.author,
    required this.imgUrl,
    required this.playCount,
    required this.songCount,
    required this.desc,
    required this.source,
  });
}

/// 歌单信息服务：获取推荐歌单、歌单详情（酷我等）
class SonglistService {
  static final SonglistService _instance = SonglistService._internal();
  factory SonglistService() => _instance;
  SonglistService._internal();

  static const String _kwDetailUrl =
      'https://nplserver.kuwo.cn/pl.svc?op=getlistinfo&pid={id}&pn={page}&rn=1000&encode=utf8&keyset=pl2012&identity=kuwo&pcmp4=1&vipver=MUSIC_9.0.5.0_W1&newver=1';

  /// 获取推荐歌单列表
  Future<List<SonglistInfo>> getRecommendSonglists({int page = 1, int pageSize = 30}) async {
    try {
      final url = Uri.parse(
        'https://wapi.kuwo.cn/api/pc/classify/playlist/getRcmPlayList?loginUid=0&loginSid=0&appUid=76039576&pn=$page&rn=$pageSize&order=hot',
      );
      final response = await http.get(url, headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      if (data['code'] != 200) return [];

      final list = data['data']?['data'] as List? ?? [];
      return list.map((item) {
        final img = item['img']?.toString() ?? '';
        return SonglistInfo(
          id: item['id']?.toString() ?? '',
          name: item['name']?.toString() ?? '',
          author: item['uname']?.toString() ?? '',
          imgUrl: _normalizeKwImg(img),
          playCount: _formatPlayCount(item['listencnt']),
          songCount: int.tryParse(item['total']?.toString() ?? '0') ?? 0,
          desc: item['desc']?.toString() ?? '',
          source: 'kw',
        );
      }).toList();
    } catch (e) {
      logDebug('获取推荐歌单失败: $e');
      return [];
    }
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

  /// 搜索 QQ 音乐歌单（复用搜索歌曲的 zzc 签名机制）
  Future<List<SonglistInfo>> searchQQSonglists(String keyword, {int page = 1, int pageSize = 20}) async {
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
            'search_type': 3, // 歌单
            'searchid': DateTime.now().millisecondsSinceEpoch.toString(),
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

      // 原始流请求（QQ 响应头含非法字符，绕过 http 包头解析）
      final client = http.Client();
      final request = http.Request('POST', url)
        ..headers['Content-Type'] = 'application/json'
        ..headers['User-Agent'] = 'QQMusic 14090508(android 12)'
        ..body = jsonEncode(data);
      final streamed = await client.send(request).timeout(const Duration(seconds: 15));
      final bodyBytes = await streamed.stream.toBytes();
      client.close();

      if (streamed.statusCode != 200) return [];

      final responseData =
          jsonDecode(utf8.decode(bodyBytes, allowMalformed: true));
      final reqData = responseData['req']?['data'];
      final body = reqData?['body'];
      final songList = body?['item_songlist'] as List? ?? [];

      return songList.map((item) {
        return SonglistInfo(
          id: item['dissid']?.toString() ?? '',
          name: (item['dissname']?.toString() ?? '')
              .replaceAll(RegExp(r'</?em>'), ''), // 去高亮标签
          author: item['nickname']?.toString() ?? '',
          imgUrl: item['logo']?.toString() ?? '',
          playCount: item['listennum'] ?? 0,
          songCount: 0,
          desc: item['description']?.toString() ?? '',
          source: 'tx',
        );
      }).toList();
    } catch (e) {
      logDebug('[SonglistSearch] QQ歌单搜索失败: $e');
      return [];
    }
  }

  static const String _eapiKey = 'e82ckenh8dichen8';

  /// 网易云 eapi 参数加密（与 music_search_service 的 WySearchSource 一致）
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

  /// 搜索酷我歌单（对齐原版 kw/songList.js search）
  Future<List<SonglistInfo>> searchKwSonglists(String keyword, {int page = 1, int pageSize = 20}) async {
    try {
      final url = Uri.parse(
          'http://search.kuwo.cn/r.s?all=${Uri.encodeComponent(keyword)}&pn=${page - 1}&rn=$pageSize&rformat=json&encoding=utf8&ver=mbox&vipver=MUSIC_8.7.7.0_BCS37&plat=pc&devid=28156413&ft=playlist&pay=0&needliveshow=0');
      final response = await http.get(url).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return [];
      final body = jsonDecode(response.body);
      final absList = body['abslist'] as List? ?? [];
      return absList.map((item) {
        return SonglistInfo(
          id: item['playlistid']?.toString() ?? '',
          name: _decode(item['name']?.toString() ?? ''),
          author: _decode(item['nickname']?.toString() ?? ''),
          imgUrl: item['pic']?.toString() ?? '',
          playCount: int.tryParse(item['playcnt']?.toString() ?? '0') ?? 0,
          songCount: int.tryParse(item['songnum']?.toString() ?? '0') ?? 0,
          desc: _decode(item['intro']?.toString() ?? ''),
          source: 'kw',
        );
      }).toList();
    } catch (e) {
      logDebug('[SonglistSearch] 酷我歌单搜索失败: $e');
      return [];
    }
  }

  /// 搜索网易云歌单（对齐原版 wy/songList.js search，eapi cloudsearch type=1000）
  Future<List<SonglistInfo>> searchWySonglists(String keyword, {int page = 1, int pageSize = 20}) async {
    try {
      final requestData = {
        's': keyword,
        'type': 1000, // 1000 = 歌单
        'limit': pageSize,
        'total': page == 1,
        'offset': pageSize * (page - 1),
      };
      final params = _eapi('/api/cloudsearch/pc', jsonEncode(requestData));
      final response = await http.post(
        Uri.parse('http://interface.music.163.com/eapi/batch'),
        headers: const {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36',
          'origin': 'https://music.163.com',
        },
        body: {'params': params},
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return [];
      final body = jsonDecode(response.body);
      if (body['code'] != 200) return [];
      final playlists = body['result']?['playlists'] as List? ?? [];
      return playlists.map((item) {
        final creator = item['creator'] as Map? ?? {};
        return SonglistInfo(
          id: item['id']?.toString() ?? '',
          name: item['name']?.toString() ?? '',
          author: creator['nickname']?.toString() ?? '',
          imgUrl: item['coverImgUrl']?.toString() ?? '',
          playCount: item['playCount'] ?? 0,
          songCount: item['trackCount'] ?? 0,
          desc: item['description']?.toString() ?? '',
          source: 'wy',
        );
      }).toList();
    } catch (e) {
      logDebug('[SonglistSearch] 网易歌单搜索失败: $e');
      return [];
    }
  }

  /// 统一歌单搜索入口：按源分发；'all' 并行聚合（去重）
  Future<List<SonglistInfo>> searchSonglists(String keyword, {required String source, int page = 1, int pageSize = 20}) async {
    switch (source) {
      case 'tx':
        return searchQQSonglists(keyword, page: page, pageSize: pageSize);
      case 'kw':
        return searchKwSonglists(keyword, page: page, pageSize: pageSize);
      case 'wy':
        return searchWySonglists(keyword, page: page, pageSize: pageSize);
      case 'all':
        final results = await Future.wait([
          searchQQSonglists(keyword, page: page, pageSize: pageSize),
          searchKwSonglists(keyword, page: page, pageSize: pageSize),
          searchWySonglists(keyword, page: page, pageSize: pageSize),
        ]);
        // 交错合并：各源首页结果轮流取样，去重（按 name+author）
        final merged = <SonglistInfo>[];
        final seen = <String>{};
        final maxLen = results.map((r) => r.length).fold(0, (a, b) => a > b ? a : b);
        for (var i = 0; i < maxLen; i++) {
          for (final r in results) {
            if (i >= r.length) continue;
            final s = r[i];
            final key = '${s.name}_${s.author}';
            if (seen.contains(key)) continue;
            seen.add(key);
            merged.add(s);
          }
        }
        return merged;
      default:
        return searchQQSonglists(keyword, page: page, pageSize: pageSize);
    }
  }

  /// 获取 QQ 音乐推荐歌单（随机分类，用于我的歌单页推荐区）
  Future<List<SonglistInfo>> getQQRecommendSonglists({
    int page = 0,
    int pageSize = 30,
    int categoryId = 10000000, // 热门
    int sortId = 5, // 5 = 最热
  }) async {
    try {
      final rnd = DateTime.now().millisecondsSinceEpoch % 100000;
      final url = Uri.parse(
        'https://c.y.qq.com/splcloud/fcgi-bin/fcg_get_diss_by_tag.fcg'
        '?picmid=1&rnd=$rnd&g_tk=5381&loginUin=0&hostUin=0&format=json'
        '&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json'
        '&needNewCode=0&categoryId=$categoryId&sortId=$sortId'
        '&sin=${page * pageSize}&ein=${page * pageSize + pageSize - 1}',
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://c.y.qq.com/',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      if (data['code'] != 0) return [];

      final list = data['data']?['list'] as List? ?? [];
      return list.map((item) {
        return SonglistInfo(
          id: item['dissid']?.toString() ?? '',
          name: item['dissname']?.toString() ?? '',
          author: item['creator']?['name']?.toString() ?? '',
          imgUrl: item['imgurl']?.toString() ?? '',
          playCount: item['listennum'] ?? 0,
          songCount: 0,
          desc: item['introduction']?.toString() ?? '',
          source: 'tx',
        );
      }).toList();
    } catch (e) {
      logDebug('[ShareLink] QQ推荐歌单获取失败: $e');
      return [];
    }
  }

  /// 获取歌单内歌曲列表
  /// [source] 为 'tx' 时走 QQ 歌单详情接口（含推荐歌单/导入歌单）。
  /// 注意：酷我和 QQ 的歌单 ID 都是纯数字，无法靠 ID 格式区分，
  /// 调用方应显式传入 source；未传时按来源依次尝试。
  Future<({String name, String imgUrl, List<MusicInfo> songs})?> getSonglistDetail({
    required String songlistId,
    int page = 0,
    String source = 'kw',
  }) async {
    switch (source) {
      case 'tx':
        return getQQPlaylistDetail(songlistId);
      case 'wy':
        final wyDetail = await getWYPlaylistDetail(songlistId);
        if (wyDetail != null && wyDetail.songs.isNotEmpty) return wyDetail;
        // wy 失败不回退 tx（ID 体系不同，必然失败）
        return wyDetail;
    }
    // kw：先试酷我，失败（酷我 ID 与 QQ ID 格式重叠）再试 QQ
    final kwDetail = await _getKwSonglistDetail(songlistId, page);
    if (kwDetail != null && kwDetail.songs.isNotEmpty) return kwDetail;
    return getQQPlaylistDetail(songlistId);
  }

  Future<({String name, String imgUrl, List<MusicInfo> songs})?> _getKwSonglistDetail(
      String songlistId, int page) async {
    try {
      final url = Uri.parse(_kwDetailUrl
          .replaceAll('{id}', songlistId)
          .replaceAll('{page}', page.toString()));
      final response = await http.get(url, headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      if (data['result'] != 'ok') return null;

      final musicList = data['musiclist'] as List? ?? [];
      final songs = musicList.map((item) => _parseKwSong(item)).toList();

      return (
        name: data['title']?.toString() ?? '',
        imgUrl: data['pic']?.toString() ?? '',
        songs: songs,
      );
    } catch (e) {
      logDebug('获取歌单详情失败: $e');
      return null;
    }
  }

  MusicInfo _parseKwSong(Map<String, dynamic> item) {
    final songId = item['id']?.toString() ?? '';
    final pic = item['pic']?.toString() ?? item['pic120']?.toString() ?? '';
    return MusicInfo(
      id: 'kw_$songId',
      name: _decode(item['name']?.toString() ?? ''),
      singer: _decode(item['artist']?.toString() ?? ''),
      album: _decode(item['album']?.toString() ?? ''),
      duration: 0,
      source: 'kw',
      songId: songId,
      songmid: songId,
      imgUrl: pic.isNotEmpty ? _normalizeKwImg(pic) : null,
    );
  }

  String _decode(String str) {
    return str
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }

  String _formatQQSize(dynamic size) {
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

  /// 将酷我小图转为大图
  String _normalizeKwImg(String img) {
    if (img.contains('_500.jpg')) return img;
    // 截断文件名尾部的尺寸标记
    final match = RegExp(r'^(.*?)_\d+\.(jpg|png)$').firstMatch(img);
    if (match != null) {
      return '${match.group(1)}_500.${match.group(2)}';
    }
    return img;
  }

  int _formatPlayCount(dynamic count) {
    final num = int.tryParse(count?.toString() ?? '0') ?? 0;
    return num;
  }

  /// 解析歌单分享链接，返回 (source, songlistId)
  /// 支持: QQ音乐分享短链 c6.y.qq.com/base/fcgi-bin/u?__=xxx
  ///       QQ音乐歌单页 i2.y.qq.com/.../playlist.html?id=xxx / taoge.html?id=xxx
  ///       网易云分享 music.163.com/playlist?id=xxx 或短链 163cn.tv
  static ({String source, String id})? parseShareLink(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;

    // 提取文本中的 URL（分享文本可能是 "歌名 xxx 链接" 格式）
    final urlMatch = RegExp(r'https?://[^\s，,。]+').firstMatch(text);
    if (urlMatch == null) return null;
    final url = urlMatch.group(0)!;

    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    // 直接带 id 参数的
    final host = uri.host;
    final idParam = uri.queryParameters['id'] ?? uri.queryParameters['disstid'];
    if (idParam != null && RegExp(r'^\d+$').hasMatch(idParam)) {
      final host = uri.host;
      if (host.contains('163.com') || host.contains('163cn.tv')) return (source: 'wy', id: idParam);
      if (host.contains('qq.com')) return (source: 'tx', id: idParam);
      return (source: 'tx', id: idParam); // 默认按 QQ 处理
    }

    // QQ/网易短链：需要跟随重定向提取 id
    if (host.contains('qq.com') || host.contains('163cn.tv') || host.contains('163.com')) {
      return (source: 'redirect', id: url); // 标记需要重定向解析
    }
    return null;
  }

  /// 跟随短链重定向，提取歌单 ID
  static Future<String?> resolveRedirectId(String url) async {
    try {
      final client = http.Client();
      var currentUrl = url;
      // 最多跟 5 次 302
      for (var i = 0; i < 5; i++) {
        final request = http.Request('GET', Uri.parse(currentUrl))
          ..followRedirects = false
          ..headers['User-Agent'] =
              'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15';
        final response = await client.send(request).timeout(const Duration(seconds: 10));
        final status = response.statusCode;
        // 读完丢弃 body
        await response.stream.drain();

        if (status == 301 || status == 302) {
          final location = response.headers['location'];
          if (location == null) break;
          currentUrl = location.startsWith('http') ? location : '${Uri.parse(currentUrl).origin}$location';
          // 已能从 URL 提取 id
          final uri = Uri.tryParse(currentUrl);
          final idParam = uri?.queryParameters['id'] ?? uri?.queryParameters['disstid'];
          if (idParam != null && RegExp(r'^\d+$').hasMatch(idParam)) {
            client.close();
            return idParam;
          }
          continue;
        }
        break;
      }
      client.close();
      // 最后再从 URL 提取一次
      final uri = Uri.tryParse(currentUrl);
      return uri?.queryParameters['id'] ?? uri?.queryParameters['disstid'];
    } catch (e) {
      logDebug('[ShareLink] 重定向解析失败: $e');
      return null;
    }
  }

  /// 导入 QQ 音乐歌单（通过分享链接的 disstid）
  Future<({String name, String imgUrl, List<MusicInfo> songs})?> getQQPlaylistDetail(
      String disstid) async {
    try {
      final data = {
        'comm': {'uin': 0, 'format': 'json', 'ct': 24, 'cv': 0},
        'req': {
          'module': 'music.srfDissInfo.DissInfo',
          'method': 'CgiGetDiss',
          'param': {
            'disstid': int.tryParse(disstid) ?? 0,
            'onlysong': 0,
            'song_begin': 0,
            'song_num': 500,
          },
        },
      };

      // 注意：不能用 http.post 便捷方法——QQ 返回的 Content-Type 头含非法字符
      //（GBK 中文注释），http_parser 严格解析会直接抛异常导致"歌单加载失败"。
      // 用 client.send() 原始流 + 手动读 body 绕过头解析。
      final client = http.Client();
      final request = http.Request(
        'POST',
        Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg?format=json'),
      );
      request.headers.addAll({
        'Content-Type': 'application/json',
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15',
        'Referer': 'https://y.qq.com/n3/other/pages/details/playlist.html',
        'Origin': 'https://y.qq.com',
      });
      request.body = jsonEncode(data);

      final streamed = await client.send(request).timeout(const Duration(seconds: 15));
      final bodyBytes = await streamed.stream.toBytes();
      client.close();

      if (streamed.statusCode != 200) {
        logDebug('[ShareLink] QQ歌单: HTTP ${streamed.statusCode}');
        return null;
      }

      final resp =
          jsonDecode(utf8.decode(bodyBytes, allowMalformed: true));
      final reqData = resp['req']?['data'];
      if (reqData == null) {
        logDebug('[ShareLink] QQ歌单: req.data 为空, code=${resp['req']?['code']}');
        return null;
      }

      // 接口返回小写键（dirinfo/songlist），兼容驼峰
      final dirInfo = (reqData['dirinfo'] ?? reqData['dirInfo']) as Map? ?? {};
      final songList = (reqData['songlist'] ?? reqData['songList']) as List? ?? [];
      logDebug('[ShareLink] QQ歌单: title=${dirInfo['title']}, 原始歌曲数=${songList.length}, 接口msg=${reqData['msg']}');

      final songs = <MusicInfo>[];
      for (final item in songList) {
        // 每项直接是歌曲对象（部分接口变体可能有 songInfo 包裹）
        final si = (item['songInfo'] ?? item) as Map?;
        if (si == null) continue;
        final songmid = si['mid']?.toString() ?? '';
        if (songmid.isEmpty) continue;
        final singers = si['singer'] as List? ?? [];
        final artist = singers.map((s) => s['name']?.toString() ?? '').join('、');
        final album = si['album'] as Map? ?? {};
        final albumMid = album['mid']?.toString() ?? '';

        // 解析音质列表（file.size_* 与搜索接口一致，供音质预选）
        final file = si['file'] as Map? ?? {};
        final types = <QualityType>[];
        if (((file['size_128mp3'] ?? 0) != 0)) {
          types.add(QualityType(type: '128k', size: _formatQQSize(file['size_128mp3'])));
        }
        if (((file['size_320mp3'] ?? 0) != 0)) {
          types.add(QualityType(type: '320k', size: _formatQQSize(file['size_320mp3'])));
        }
        if (((file['size_flac'] ?? 0) != 0)) {
          types.add(QualityType(type: 'flac', size: _formatQQSize(file['size_flac'])));
        }
        if (((file['size_hires'] ?? 0) != 0)) {
          types.add(QualityType(type: 'flac24bit', size: _formatQQSize(file['size_hires'])));
        }

        songs.add(MusicInfo(
          id: 'tx_$songmid',
          name: (si['title'] ?? si['name'])?.toString() ?? '',
          singer: artist,
          album: album['name']?.toString() ?? '',
          duration: si['interval'] ?? 0,
          source: 'tx',
          songId: si['id']?.toString() ?? '',
          songmid: songmid,
          strMediaMid: file['media_mid']?.toString() ?? songmid,
          imgUrl: albumMid.isNotEmpty
              ? 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$albumMid.jpg'
              : null,
          types: types.isNotEmpty ? types : null,
        ));
      }

      return (
        name: dirInfo['title']?.toString() ?? '',
        imgUrl: dirInfo['picurl']?.toString() ?? dirInfo['pic']?.toString() ?? '',
        songs: songs,
      );
    } catch (e) {
      logDebug('[ShareLink] QQ歌单获取失败: $e');
      return null;
    }
  }

  /// 导入网易云歌单（playlist id）
    /// 获取网易云歌单详情（eapi v3 接口，返回完整曲目——旧 api/playlist/detail 只返回前 10 首）
  Future<({String name, String imgUrl, List<MusicInfo> songs})?> getWYPlaylistDetail(
      String playlistId) async {
    try {
      final params = _eapi('/api/v3/playlist/detail', jsonEncode({
        'id': playlistId,
        'n': 1000,
        's': 8,
      }));
      final response = await http.post(
        Uri.parse('http://interface.music.163.com/eapi/batch'),
        headers: const {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36',
          'origin': 'https://music.163.com',
        },
        body: {'params': params},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data['code'] != 200) return null;

      final playlist = data['playlist'] as Map? ?? {};
      final name = playlist['name']?.toString() ?? '';
      final imgUrl = playlist['coverImgUrl']?.toString() ?? '';
      final tracks = playlist['tracks'] as List? ?? [];
      final trackIds = playlist['trackIds'] as List? ?? [];
      final privileges = playlist['privileges'] as List? ?? [];

      // tracks 通常随 n=1000 全量返回；个别情况只有 trackIds（则截断到 tracks 可用部分）
      final songs = <MusicInfo>[];
      final privilegeById = <String, Map>{};
      for (final p in privileges) {
        final pid = p['id']?.toString();
        if (pid != null) privilegeById[pid] = p;
      }

      for (final t in tracks) {
        final songId = t['id']?.toString() ?? '';
        if (songId.isEmpty) continue;
        final artists = t['ar'] as List? ?? (t['artists'] as List? ?? []);
        final artist = artists.map((a) => a['name']?.toString() ?? '').where((n) => n.isNotEmpty).join('、');
        final album = t['al'] as Map? ?? (t['album'] as Map? ?? {});

        // 音质列表（按 privilege.maxBrLevel / maxbr，与搜索一致）
        final privilege = privilegeById[songId] as Map? ?? {};
        final maxbr = privilege['maxbr'] ?? 0;
        final maxBrLevel = privilege['maxBrLevel']?.toString() ?? '';
        final types = <QualityType>[];
        if (maxBrLevel == 'hires') {
          types.add(QualityType(type: 'flac24bit', size: _formatQQSize(t['hr']?['size'] ?? 0)));
        }
        if (maxbr >= 999000) {
          types.add(QualityType(type: 'flac', size: _formatQQSize(t['sq']?['size'] ?? 0)));
        }
        if (maxbr >= 320000) {
          types.add(QualityType(type: '320k', size: _formatQQSize(t['h']?['size'] ?? 0)));
        }
        if (maxbr >= 128000) {
          types.add(QualityType(type: '128k', size: _formatQQSize(t['l']?['size'] ?? 0)));
        }

        songs.add(MusicInfo(
          id: 'wy_$songId',
          name: t['name']?.toString() ?? '',
          singer: artist,
          album: album['name']?.toString() ?? '',
          duration: (t['dt'] ?? 0) ~/ 1000,
          source: 'wy',
          songId: songId,
          songmid: songId,
          imgUrl: album['picUrl']?.toString(),
          types: types.isNotEmpty ? types : null,
        ));
      }
      // tracks 常被服务端截断为 10 首（n 参数对部分歌单无效），但 trackIds 恒完整。
      // 截断时按原版逻辑批量补拉：/api/v3/song/detail 每批 500 个 ID
      if (tracks.length < trackIds.length) {
        final privById = <String, Map>{};
        for (final p in privileges) {
          final pid = p['id']?.toString();
          if (pid != null) privById[pid] = p;
        }
        final allIds = trackIds.map((t) => t['id']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
        final fetchedSongs = <Map>[];
        final fetchedPrivs = <Map>[];
        for (var i = 0; i < allIds.length; i += 500) {
          final batch = allIds.skip(i).take(500).toList();
          final detailData = await _eapiRequest('/api/v3/song/detail', {
            'c': '[${batch.map((id) => '{"id":$id}').join(',')}]',
            'ids': '[${batch.join(',')}]',
          });
          if (detailData == null) continue;
          fetchedSongs.addAll((detailData['songs'] as List? ?? []).cast<Map>());
          fetchedPrivs.addAll((detailData['privileges'] as List? ?? []).cast<Map>());
        }
        logDebug('[WYPlaylist] tracks 截断(${tracks.length}/${trackIds.length})，已补拉 ${fetchedSongs.length} 首');
        return (
          name: name,
          imgUrl: imgUrl,
          songs: _buildWYSongs(fetchedSongs, fetchedPrivs, name, imgUrl),
        );
      }

      return (
        name: name,
        imgUrl: imgUrl,
        songs: _buildWYSongs(tracks.cast<Map>(), privileges.cast<Map>(), name, imgUrl),
      );
    } catch (e) {
      logDebug('[WYPlaylist] 获取失败: $e');
      return null;
    }
  }

  /// eapi POST 请求（返回解码后的 JSON Map，失败返回 null）
  Future<Map?> _eapiRequest(String url, Map data) async {
    try {
      final params = _eapi(url, jsonEncode(data));
      final response = await http.post(
        Uri.parse('http://interface.music.163.com/eapi/batch'),
        headers: const {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36',
          'origin': 'https://music.163.com',
        },
        body: {'params': params},
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      return decoded is Map ? decoded : null;
    } catch (e) {
      logDebug('[WYPlaylist] eapi 请求失败: $e');
      return null;
    }
  }

  /// 从 tracks+privileges 构建 MusicInfo 列表（详情/批量补拉共用）
  List<MusicInfo> _buildWYSongs(List<Map> tracks, List<Map> privileges, String name, String imgUrl) {
    final songs = <MusicInfo>[];
    final privilegeById = <String, Map>{};
    for (final p in privileges) {
      final pid = p['id']?.toString();
      if (pid != null) privilegeById[pid] = p;
    }
    for (final t in tracks) {
      final songId = t['id']?.toString() ?? '';
      if (songId.isEmpty) continue;
      final artists = t['ar'] as List? ?? (t['artists'] as List? ?? []);
      final artist = artists.map((a) => a['name']?.toString() ?? '').where((n) => n.isNotEmpty).join('、');
      final album = t['al'] as Map? ?? (t['album'] as Map? ?? {});

      final privilege = privilegeById[songId] as Map? ?? {};
      final maxbr = privilege['maxbr'] ?? 0;
      final maxBrLevel = privilege['maxBrLevel']?.toString() ?? '';
      final types = <QualityType>[];
      if (maxBrLevel == 'hires') {
        types.add(QualityType(type: 'flac24bit', size: _formatQQSize(t['hr']?['size'] ?? 0)));
      }
      if (maxbr >= 999000) {
        types.add(QualityType(type: 'flac', size: _formatQQSize(t['sq']?['size'] ?? 0)));
      }
      if (maxbr >= 320000) {
        types.add(QualityType(type: '320k', size: _formatQQSize(t['h']?['size'] ?? 0)));
      }
      if (maxbr >= 128000) {
        types.add(QualityType(type: '128k', size: _formatQQSize(t['l']?['size'] ?? 0)));
      }

      songs.add(MusicInfo(
        id: 'wy_$songId',
        name: t['name']?.toString() ?? '',
        singer: artist,
        album: album['name']?.toString() ?? '',
        duration: (t['dt'] ?? 0) ~/ 1000,
        source: 'wy',
        songId: songId,
        songmid: songId,
        imgUrl: album['picUrl']?.toString(),
        types: types.isNotEmpty ? types : null,
      ));
    }
    logDebug('[WYPlaylist] 构建歌单 $name: ${songs.length} 首');
    return songs;
  }

  /// 获取每日推荐歌曲（从热门歌单中随机抽取）
  Future<List<MusicInfo>> getRecommendSongs({int count = 20}) async {
    try {
      // 先获取推荐歌单
      final songlists = await getRecommendSonglists(page: 1, pageSize: 5);
      if (songlists.isEmpty) return [];

      // 随机选择一个歌单
      final random = DateTime.now().millisecondsSinceEpoch % songlists.length;
      final songlist = songlists[random];

      // 获取歌单详情
      final detail = await getSonglistDetail(songlistId: songlist.id);
      if (detail == null || detail.songs.isEmpty) return [];

      // 随机打乱并取指定数量
      final songs = List<MusicInfo>.from(detail.songs)..shuffle();
      return songs.take(count).toList();
    } catch (e) {
      logDebug('获取推荐歌曲失败: $e');
      return [];
    }
  }
}
