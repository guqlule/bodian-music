import 'dart:convert';
import '../../core/utils/logger.dart';
import 'package:http/http.dart' as http;
import '../../models/music_model.dart';
import '../lyric/krc_decoder.dart';

const _uaDesktop = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

/// 通用 GET + JSON，返回 null 表示任何失败（超时/非 200/解析异常）
Future<Map<String, dynamic>?> _httpGetJson(Uri url, {String tag = '', Map<String, String>? headers}) async {
  try {
    final response = await http.get(url, headers: {'User-Agent': _uaDesktop, ...?headers})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      logDebug('[LyricApi] $tag: HTTP ${response.statusCode}');
      return null;
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  } catch (e) {
    logDebug('[LyricApi] $tag: 失败 - $e');
    return null;
  }
}

/// 内置歌词获取服务
class LyricApiService {
  static final LyricApiService _instance = LyricApiService._internal();
  factory LyricApiService() => _instance;
  LyricApiService._internal();

  /// 获取歌词 - 根据来源选择对应API，失败后跨源兜底
  Future<Map<String, String?>?> getLyric(MusicInfo music) async {
    logDebug('[LyricApi] 获取歌词: source=${music.source}, id=${music.songId}');
    
    Map<String, String?>? result;
    switch (music.source) {
      case 'kw':
        result = await _getKwLyric(music);
        break;
      case 'wy':
        result = await _getWyLyric(music);
        break;
      case 'tx':
        result = await _getTxLyric(music);
        break;
      case 'kg':
        result = await _getKgLyric(music);
        break;
      default:
        result = await _getKwLyric(music);
        if (result == null) result = await _getWyLyric(music);
    }

    if (result != null && result['lyric'] != null && result['lyric']!.isNotEmpty) {
      return result;
    }

    // 跨源兜底 1：本源歌词为空时，用网易云歌词接口按歌名+歌手搜索
    logDebug('[LyricApi] 本源歌词为空，尝试网易云跨源兜底');
    try {
      final fallback = await _searchWyLyricByKeyword(music);
      if (fallback != null && fallback['lyric'] != null && fallback['lyric']!.isNotEmpty) {
        logDebug('[LyricApi] 网易云跨源兜底成功');
        return fallback;
      }
    } catch (e) {
      logDebug('[LyricApi] 网易云跨源兜底失败: $e');
    }

    // 跨源兜底 2：酷狗 KRC（唯一稳定提供逐字歌词的公开接口）。
    // 网易云/QQ 接口只返回行级歌词，所以任何源都能从这里拿到逐字版本。
    logDebug('[LyricApi] 尝试酷狗 KRC 跨源逐字兜底');
    try {
      final kg = await _searchKgLyricByKeyword(music);
      if (kg != null && kg['lyric'] != null && kg['lyric']!.isNotEmpty) {
        logDebug('[LyricApi] 酷狗 KRC 跨源兜底成功（逐字）');
        return kg;
      }
    } catch (e) {
      logDebug('[LyricApi] 酷狗 KRC 兜底失败: $e');
    }

    return result;
  }

  /// 按歌名+歌手搜索歌词（用于本地歌曲无 .lrc 时在线兜底）
  ///
  /// 优先用酷狗 KRC（逐字），失败再退网易云（行级）。
  Future<Map<String, String?>?> searchLyricByKeyword(
      String name, String singer) async {
    final music = MusicInfo(
      id: 'temp',
      name: name,
      singer: singer,
      album: '',
      duration: 0,
      source: 'wy',
    );
    try {
      final kg = await _searchKgLyricByKeyword(music);
      if (kg != null && (kg['lyric'] ?? '').isNotEmpty) return kg;
    } catch (_) {}
    return _searchWyLyricByKeyword(music);
  }

  // ==================== 酷我 (KW) ====================
  /// 从酷我获取歌词 - 使用简单API
  Future<Map<String, String?>?> _getKwLyric(MusicInfo music) async {
    final musicId = music.songId ?? music.id;
    if (musicId.isEmpty) {
      logDebug('[LyricApi] KW: musicId为空');
      return null;
    }
    logDebug('[LyricApi] KW: 请求 musicId=$musicId');

    final data = await _httpGetJson(
      Uri.parse('https://m.kuwo.cn/newh5/singles/songinfoandlrc?musicId=$musicId'),
      tag: 'KW',
      headers: {
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15',
        'Referer': 'https://m.kuwo.cn/',
      },
    );
    if (data == null || data['status'] != 200) return null;

    final lrcList = data['data']?['lrclist'] as List?;
    if (lrcList == null || lrcList.isEmpty) {
      logDebug('[LyricApi] KW: lrclist为空');
      return null;
    }
    logDebug('[LyricApi] KW: 获取到 ${lrcList.length} 行歌词');

    final StringBuffer lrcBuffer = StringBuffer();
    for (final item in lrcList) {
      final time = item['time']?.toString() ?? '0';
      final text = item['lineLyric']?.toString() ?? '';
      if (text.isEmpty) continue;

      final seconds = double.tryParse(time) ?? 0;
      final minutes = (seconds / 60).floor();
      final secs = (seconds % 60).toStringAsFixed(2);
      lrcBuffer.writeln('[${minutes.toString().padLeft(2, '0')}:$secs]$text');
    }

    final lrc = lrcBuffer.toString();
    if (lrc.isEmpty) {
      logDebug('[LyricApi] KW: 构建LRC为空');
      return null;
    }
    logDebug('[LyricApi] KW: 成功，歌词长度=${lrc.length}');
    return {'lyric': lrc, 'tlyric': null};
  }

  // ==================== 网易云 (WY) ====================
  /// 从网易云获取歌词
  Future<Map<String, String?>?> _getWyLyric(MusicInfo music) async {
    final musicId = music.songId ?? music.id;
    if (musicId.isEmpty) return null;
    logDebug('[LyricApi] WY: 请求 musicId=$musicId');

    final data = await _httpGetJson(
      Uri.parse('https://music.163.com/api/song/lyric?id=$musicId&lv=1&tv=1'),
      tag: 'WY',
      headers: {'Referer': 'https://music.163.com/'},
    );
    if (data == null || data['code'] != 200) return null;

    final lrc = data['lrc']?['lyric'] as String?;
    final tlyric = data['tlyric']?['lyric'] as String?;
    if (lrc == null || lrc.isEmpty) {
      logDebug('[LyricApi] WY: lrc为空');
      return null;
    }
    logDebug('[LyricApi] WY: 成功，歌词长度=${lrc.length}');
    return {'lyric': lrc, 'tlyric': tlyric};
  }

  // ==================== QQ音乐 (TX) ====================
  /// 从QQ音乐获取歌词
  Future<Map<String, String?>?> _getTxLyric(MusicInfo music) async {
    final musicId = music.songmid ?? music.songId ?? music.id;
    if (musicId.isEmpty) return null;
    logDebug('[LyricApi] TX: 请求 musicId=$musicId');

    final data = await _httpGetJson(
      Uri.parse(
        'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg'
        '?songmid=$musicId&g_tk=5381&loginUin=0&hostUin=0'
        '&format=json&inCharset=utf8&outCharset=utf-8&platform=yqq',
      ),
      tag: 'TX',
      headers: {'Referer': 'https://y.qq.com/portal/player.html'},
    );
    if (data == null || data['code'] != 0) return null;

    final lyric = data['lyric'] as String?;
    final trans = data['trans'] as String?;
    if (lyric == null || lyric.isEmpty) {
      logDebug('[LyricApi] TX: lyric为空');
      return null;
    }

    // Base64 解码
    final decodedLyric = utf8.decode(base64Decode(lyric));
    final decodedTrans = trans != null && trans.isNotEmpty
        ? utf8.decode(base64Decode(trans))
        : null;
    logDebug('[LyricApi] TX: 成功，歌词长度=${decodedLyric.length}');
    return {'lyric': decodedLyric, 'tlyric': decodedTrans};
  }

  // ==================== 酷狗 (KG) ====================
  /// 从酷狗获取歌词
  Future<Map<String, String?>?> _getKgLyric(MusicInfo music) async {
    final musicId = music.songId ?? music.hash ?? music.id;
    if (musicId.isEmpty) return null;
    logDebug('[LyricApi] KG: 请求 musicId=$musicId');

    // 搜索歌词
    final searchData = await _httpGetJson(
      Uri.parse(
        'https://krcs.kugou.com/search?ver=1&man=yes&client=pc'
        '&keyword=${Uri.encodeComponent(music.name + ' ' + music.singer)}'
        '&hash=$musicId&timelength=0&lrctxt=1',
      ),
      tag: 'KG',
    );
    if (searchData == null) return null;

    final candidates = searchData['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      logDebug('[LyricApi] KG: 无候选歌词');
      return null;
    }
    final first = candidates[0];
    final lrcId = first['id'];
    final accessKey = first['accesskey'];
    logDebug('[LyricApi] KG: 找到歌词 id=$lrcId');

    // 优先请求 KRC（逐字歌词），失败降级 LRC（行级）
    // KRC = base64 → skip 4B → XOR 固定 16B 密钥 → zlib 解压
    final krc = await _downloadKg('krc', lrcId, accessKey);
    if (krc != null && krc.trim().isNotEmpty) {
      logDebug('[LyricApi] KG: KRC 逐字歌词成功，长度=${krc.length}');
      return {'lyric': krc, 'tlyric': null, 'krc': '1'};
    }

    final lrc = await _downloadKg('lrc', lrcId, accessKey);
    if (lrc == null || lrc.trim().isEmpty) {
      logDebug('[LyricApi] KG: 歌词获取失败');
      return null;
    }
    logDebug('[LyricApi] KG: LRC 行级歌词成功，长度=${lrc.length}');
    return {'lyric': lrc, 'tlyric': null};
  }

  /// 下载酷狗歌词并解密。
  /// fmt=krc 时走 KRC 解密流程；fmt=lrc 时仅 base64 解码。
  Future<String?> _downloadKg(
    String fmt,
    Object lrcId,
    Object accessKey,
  ) async {
    try {
      final data = await _httpGetJson(
        Uri.parse(
          'https://lyrics.kugou.com/download?ver=1&client=pc'
          '&id=$lrcId&accesskey=$accessKey&fmt=$fmt&charset=utf8',
        ),
        tag: 'KG',
      );
      if (data == null) return null;

      final content = data['content'] as String?;
      if (content == null || content.isEmpty) return null;

      if (fmt == 'krc') {
        return KrcDecoder.decode(content);
      }
      // lrc：仅 base64
      return utf8.decode(base64Decode(_padBase64(content)));
    } catch (e) {
      logDebug('[LyricApi] KG: $fmt 下载失败: $e');
      return null;
    }
  }

  static String _padBase64(String s) {
    final t = s.trim();
    final pad = (4 - t.length % 4) % 4;
    return pad == 0 ? t : t + ('=' * pad);
  }

  // ==================== 跨源兜底：网易云歌词搜索 ====================
  /// 通过歌名+歌手在网易云搜索歌词（兜底用，限前3条候选）
  Future<Map<String, String?>?> _searchWyLyricByKeyword(MusicInfo music) async {
    final keyword = '${music.name} ${music.singer}';
    final searchUrl = Uri.parse(
      'https://music.163.com/api/search/get?s=${Uri.encodeComponent(keyword)}'
      '&type=1&limit=3&offset=0',
    );

    final searchResp = await http.get(searchUrl, headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      'Referer': 'https://music.163.com/',
    }).timeout(const Duration(seconds: 8));

    if (searchResp.statusCode != 200) return null;

    final searchData = jsonDecode(searchResp.body);
    final songs = searchData['result']?['songs'] as List?;
    if (songs == null || songs.isEmpty) return null;

    for (final song in songs) {
      final id = song['id'];
      if (id == null) continue;

      try {
        final lyricUrl = Uri.parse(
          'https://music.163.com/api/song/lyric?id=$id&lv=1&tv=1',
        );
        final lyricResp = await http.get(lyricUrl, headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://music.163.com/',
        }).timeout(const Duration(seconds: 8));

        if (lyricResp.statusCode != 200) continue;

        final lyricData = jsonDecode(lyricResp.body);
        if (lyricData['code'] != 200) continue;

        final lrc = lyricData['lrc']?['lyric'] as String?;
        final tlyric = lyricData['tlyric']?['lyric'] as String?;

        if (lrc != null && lrc.isNotEmpty) {
          return {'lyric': lrc, 'tlyric': tlyric};
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  // ==================== 跨源：酷狗 KRC 逐字兜底 ====================
  /// 用「歌名+歌手」到酷狗搜索 KRC（逐字歌词）。
  ///
  /// 酷狗是唯一稳定提供逐字歌词的公开接口（网易云/QQ 只给行级），
  /// 所以任何音源的歌曲都可以从这里拿到逐字版本。
  ///
  /// 注意：搜索接口对「歌名 歌手」联合词的召回不稳定（实测「孤勇者 陈奕迅」
  /// 返回 0 条，而单用歌名能命中），因此先试联合词，再退回纯歌名。
  /// 纯歌名召回更宽，因此**必须校验候选的歌手是否匹配**，避免拿到同名歌的词。
  Future<Map<String, String?>?> _searchKgLyricByKeyword(MusicInfo music) async {
    final title = music.name.trim();
    if (title.isEmpty) return null;

    final keywords = <String>[
      if (music.singer.trim().isNotEmpty) '$title ${music.singer.trim()}',
      title,
    ];

    for (final kw in keywords) {
      final candidates = await _kgLyricSearch(kw);
      for (final c in candidates) {
        // 歌手必须匹配（纯歌名搜索时尤其重要）
        if (!_singerMatches(c['singer'] as String?, music.singer)) continue;
        final lrcId = c['id'];
        final accessKey = c['accesskey'];
        if (lrcId == null || accessKey == null) continue;

        final krc = await _downloadKg('krc', lrcId, accessKey);
        if (krc != null && krc.trim().isNotEmpty) {
          return {'lyric': krc, 'tlyric': null, 'krc': '1'};
        }
        // 该候选没有逐字，退回行级
        final lrc = await _downloadKg('lrc', lrcId, accessKey);
        if (lrc != null && lrc.trim().isNotEmpty) {
          return {'lyric': lrc, 'tlyric': null};
        }
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _kgLyricSearch(String keyword) async {
    try {
      final url = Uri.parse(
        'https://krcs.kugou.com/search?ver=1&man=yes&client=pc'
        '&keyword=${Uri.encodeComponent(keyword)}'
        '&hash=&timelength=0&lrctxt=1',
      );
      final resp = await http.get(url, headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      }).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return const [];

      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      final list = data['candidates'] as List?;
      if (list == null || list.isEmpty) return const [];
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      logDebug('[LyricApi] KG 搜索失败: $e');
      return const [];
    }
  }

  /// 歌手匹配：候选歌手与目标歌手有交集即认为匹配。
  /// 酷狗歌手字段常为「A、B」多歌手形式，只要有一人命中即可。
  static bool _singerMatches(String? candidate, String target) {
    if (target.trim().isEmpty) return true;
    if (candidate == null || candidate.trim().isEmpty) return false;
    final t = target.trim();
    final c = candidate.trim();
    if (c == t) return true;
    final cParts = c.split(RegExp(r'[,/、&]')).map((e) => e.trim()).where((e) => e.isNotEmpty);
    // 目标歌手也可能是多歌手，取交集
    final tParts = t.split(RegExp(r'[,/、&]')).map((e) => e.trim()).where((e) => e.isNotEmpty);
    for (final tp in tParts) {
      for (final cp in cParts) {
        if (cp == tp) return true;
        // 单名互相包含（如「周杰伦」vs「周杰倫feat.」）
        if (cp.length >= 2 && tp.length >= 2 &&
            (cp.contains(tp) || tp.contains(cp))) {
          return true;
        }
      }
    }
    return false;
  }
}
