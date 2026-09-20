import 'dart:convert';
import 'package:http/http.dart' as http;

/// 搜索联想（输入提示）—— 对齐 lx-music-mobile src/utils/musicSdk/*/tipSearch.js
/// mg（301 到网页版）已失效；wy 用明文 suggest 接口（原版 weapi 需 RSA 加密，明文接口等效）
class SearchSuggestService {
  static final SearchSuggestService _instance = SearchSuggestService._internal();
  factory SearchSuggestService() => _instance;
  SearchSuggestService._internal();

  static const Set<String> _supportedSources = {'kw', 'kg', 'tx', 'wy'};

  bool supports(String source) => _supportedSources.contains(source);

  /// 返回联想词列表（"歌名 - 歌手" 或关联词），失败返回空列表
  Future<List<String>> getSuggestions(String source, String keyword) async {
    if (keyword.trim().isEmpty) return const [];
    try {
      switch (source) {
        case 'all':
          return await _allSuggest(keyword);
        case 'kw':
          return await _kwSuggest(keyword);
        case 'kg':
          return await _kgSuggest(keyword);
        case 'tx':
          return await _txSuggest(keyword);
        case 'wy':
          return await _wySuggest(keyword);
        default:
          return const [];
      }
    } catch (_) {
      return const [];
    }
  }

  /// 全部源 —— 四源并行联想并去重合并
  Future<List<String>> _allSuggest(String keyword) async {
    final results = await Future.wait([
      _kwSuggest(keyword).catchError((_) => const <String>[]),
      _kgSuggest(keyword).catchError((_) => const <String>[]),
      _txSuggest(keyword).catchError((_) => const <String>[]),
      _wySuggest(keyword).catchError((_) => const <String>[]),
    ]);
    final seen = <String>{};
    final merged = <String>[];
    for (final list in results) {
      for (final w in list) {
        if (w.isNotEmpty && seen.add(w)) merged.add(w);
      }
    }
    return merged.take(15).toList();
  }

  /// 酷我 —— 对齐 kw/tipSearch.js
  Future<List<String>> _kwSuggest(String keyword) async {
    final response = await http.get(
      Uri.parse(
          'https://tips.kuwo.cn/t.s?corp=kuwo&newver=3&p2p=1&notrace=0&c=mbox&w=${Uri.encodeComponent(keyword)}&encoding=utf8&rformat=json'),
      headers: const {'Referer': 'http://www.kuwo.cn/'},
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) return const [];
    final body = jsonDecode(response.body);
    final wordItems = body['WORDITEMS'] as List? ?? [];
    return wordItems
        .map((item) => item['RELWORD']?.toString() ?? '')
        .where((w) => w.isNotEmpty)
        .toList();
  }

  /// 酷狗 —— 对齐 kg/tipSearch.js
  Future<List<String>> _kgSuggest(String keyword) async {
    final response = await http.get(
      Uri.parse(
          'https://searchtip.kugou.com/getSearchTip?MusicTipCount=10&keyword=${Uri.encodeComponent(keyword)}'),
      headers: const {'Referer': 'https://www.kugou.com/'},
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) return const [];
    final body = jsonDecode(response.body);
    if (body['status'] != 1 && body['error_code'] != 0) return const [];
    final data = body['data'] as List? ?? [];
    final result = <String>[];
    for (final d in data) {
      final records = d['RecordDatas'] as List? ?? [];
      for (final record in records) {
        final hint = _decodeName(record['HintInfo']?.toString() ?? '');
        if (hint.isNotEmpty) result.add(hint);
      }
    }
    return result;
  }

  /// QQ 音乐 —— 对齐 tx/tipSearch.js（smartbox）
  Future<List<String>> _txSuggest(String keyword) async {
    final response = await http.get(
      Uri.parse(
          'https://c.y.qq.com/splcloud/fcgi-bin/smartbox_new.fcg?is_xml=0&format=json&key=${Uri.encodeComponent(keyword)}&loginUin=0&hostUin=0&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq&needNewCode=0'),
      headers: const {'Referer': 'https://y.qq.com/portal/player.html'},
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) return const [];
    final body = jsonDecode(response.body);
    if (body['code'] != 0) return const [];
    final song = body['data']?['song'] as Map? ?? {};
    final itemlist = song['itemlist'] as List? ?? [];
    return itemlist
        .map((info) {
          final name = info['name']?.toString() ?? '';
          final singer = info['singer']?.toString() ?? '';
          return singer.isNotEmpty ? '$name - $singer' : name;
        })
        .where((w) => w.isNotEmpty)
        .toList();
  }

  /// 网易云 —— 明文 suggest 接口（等效原版 weapi search/suggest/web）
  Future<List<String>> _wySuggest(String keyword) async {
    final response = await http.get(
      Uri.parse(
          'https://music.163.com/api/search/suggest/web?s=${Uri.encodeComponent(keyword)}'),
      headers: const {
        'Referer': 'https://music.163.com/',
        'Cookie': 'appver=8.7.01',
      },
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) return const [];
    final body = jsonDecode(response.body);
    final songs = body['result']?['songs'] as List? ?? [];
    return songs
        .map((info) {
          final name = info['name']?.toString() ?? '';
          final singers = (info['artists'] as List? ?? [])
              .map((a) => a['name']?.toString() ?? '')
              .where((n) => n.isNotEmpty)
              .join('、');
          return singers.isNotEmpty ? '$name - $singers' : name;
        })
        .where((w) => w.isNotEmpty)
        .toList();
  }

  String _decodeName(String str) {
    return str
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }
}
