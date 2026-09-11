import 'dart:convert';
import 'package:http/http.dart' as http;

/// 热搜词服务 —— 对齐 lx-music-mobile src/utils/musicSdk/*/hotSearch.js
/// tx（musicu.fcg 返回 500001）与 wy（eapi chart）接口已失效，回退 kw 数据
class HotSearchService {
  static final HotSearchService _instance = HotSearchService._internal();
  factory HotSearchService() => _instance;
  HotSearchService._internal();

  final Map<String, List<String>> _cache = {};
  final Map<String, DateTime> _cacheTime = {};
  static const _cacheTtl = Duration(minutes: 10);

  /// 获取指定音源的热搜词，失败时回退到可用源
  Future<List<String>> getHotSearch(String source) async {
    final cached = _getCached(source);
    if (cached != null) return cached;

    List<String> list;
    switch (source) {
      case 'kw':
        list = await _kwHotSearch();
        break;
      case 'kg':
        list = await _kgHotSearch();
        break;
      case 'mg':
        list = await _mgHotSearch();
        break;
      case 'tx':
      case 'wy':
        // 接口已失效（tx musicu.fcg 500001 / wy eapi chart 需登录态）
        // 对齐原版行为：失败即空列表，由 UI 回退静态热词
        return const [];
      default:
        // 'all' 或未知源 → 用酷我（原版列表第一个源）
        list = await _kwHotSearch();
        break;
    }
    if (list.isEmpty) return const [];
    _cache[source] = list;
    _cacheTime[source] = DateTime.now();
    return list;
  }

  List<String>? _getCached(String source) {
    final time = _cacheTime[source];
    if (time == null) return null;
    if (DateTime.now().difference(time) > _cacheTtl) {
      _cache.remove(source);
      _cacheTime.remove(source);
      return null;
    }
    return _cache[source];
  }

  /// 酷我热搜 —— 对齐 kw/hotSearch.js
  Future<List<String>> _kwHotSearch() async {
    final response = await http.get(
      Uri.parse(
          'http://hotword.kuwo.cn/hotword.s?prod=kwplayer_ar_9.3.0.1&corp=kuwo&newver=2&vipver=9.3.0.1&source=kwplayer_ar_9.3.0.1_40.apk&p2p=1&notrace=0&uid=0&plat=kwplayer_ar&rformat=json&encoding=utf8&tabid=1'),
      headers: const {
        'User-Agent': 'Dalvik/2.1.0 (Linux; U; Android 9;)',
      },
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception('获取热搜词失败');
    }
    final body = jsonDecode(response.body);
    if (body['status'] != 'ok') {
      throw Exception('获取热搜词失败');
    }
    final tags = body['tagvalue'] as List? ?? [];
    return tags
        .map((t) => t['key']?.toString() ?? '')
        .where((k) => k.isNotEmpty)
        .toList();
  }

  /// 酷狗热搜 —— 对齐 kg/hotSearch.js
  Future<List<String>> _kgHotSearch() async {
    final response = await http.get(
      Uri.parse(
          'http://gateway.kugou.com/api/v3/search/hot_tab?signature=ee44edb9d7155821412d220bcaf509dd&appid=1005&clientver=10026&plat=0'),
      headers: const {
        'dfid': '1ssiv93oVqMp27cirf2CvoF1',
        'mid': '156798703528610303473757548878786007104',
        'clienttime': '1584257267',
        'x-router': 'msearch.kugou.com',
        'user-agent': 'Android9-AndroidPhone-10020-130-0-searchrecommendprotocol-wifi',
        'kg-rc': '1',
      },
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception('获取热搜词失败');
    }
    final body = jsonDecode(response.body);
    if (body['errcode'] != 0) {
      throw Exception('获取热搜词失败');
    }
    final list = body['data']?['list'] as List? ?? [];
    final result = <String>[];
    for (final item in list) {
      final keywords = item['keywords'] as List? ?? [];
      for (final k in keywords) {
        final word = _decodeName(k['keyword']?.toString() ?? '');
        if (word.isNotEmpty) result.add(word);
      }
    }
    return result;
  }

  /// 咪咕热搜 —— 对齐 mg/hotSearch.js（只取歌曲类型）
  Future<List<String>> _mgHotSearch() async {
    final response = await http.get(
      Uri.parse('http://jadeite.migu.cn:7090/music_search/v3/search/hotword'),
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception('获取热搜词失败');
    }
    final body = jsonDecode(response.body);
    if (body['code'] != '000000') {
      throw Exception('获取热搜词失败');
    }
    final hotwords = body['data']?['hotwords'] as List? ?? [];
    final result = <String>[];
    for (final group in hotwords) {
      final wordList = group['hotwordList'] as List? ?? [];
      for (final item in wordList) {
        if (item['resourceType']?.toString() != 'song') continue;
        final word = item['word']?.toString() ?? '';
        if (word.isNotEmpty) result.add(word);
      }
    }
    return result;
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
