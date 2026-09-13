import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../../models/music_model.dart';

/// 榜单条目
class BoardInfo {
  final String id;
  final String name;
  final String? cover;
  const BoardInfo({required this.id, required this.name, this.cover});
}

/// 音乐排行榜数据服务（真实API）
class BoardService {
  static final BoardService _instance = BoardService._internal();
  factory BoardService() => _instance;
  BoardService._internal();

  // ==================== 榜单定义 ====================

  static const Map<String, List<BoardInfo>> boardsBySource = {
    'kw': [
      BoardInfo(id: '2', name: '热歌榜'),
      BoardInfo(id: '296', name: '飙升榜'),
      BoardInfo(id: '17', name: '新歌榜'),
      BoardInfo(id: '105', name: '抖音热榜'),
    ],
    'wy': [
      BoardInfo(id: '3779629', name: '飙升榜'),
      BoardInfo(id: '3778678', name: '热歌榜'),
      BoardInfo(id: '19723756', name: '飙升榜(电音)'),
      BoardInfo(id: '27135204', name: '抖音热歌'),
    ],
    'tx': [
      BoardInfo(id: '26', name: '热歌榜'),
      BoardInfo(id: '27', name: '新歌榜'),
      BoardInfo(id: '62', name: '飙升榜'),
      BoardInfo(id: '58', name: '抖音热榜'),
    ],
  };

  List<BoardInfo> boards(String source) => boardsBySource[source] ?? boardsBySource['kw']!;

  // ==================== 获取榜单歌曲 ====================

  Future<List<MusicInfo>> getBoardSongs(String source, String boardId) async {
    switch (source) {
      case 'kw':
        return _getKwBoard(boardId);
      case 'wy':
        return _getWyBoard(boardId);
      case 'tx':
        return _getTxBoard(boardId);
      default:
        return _getKwBoard(boardId);
    }
  }

  // ==================== 酷我榜单 ====================
  Future<List<MusicInfo>> _getKwBoard(String boardId) async {
    final client = http.Client();
    try {
      final url = Uri.parse(
        'https://mobiles.kuwo.cn/mobi.s?f=kuwo&q='
        '${Uri.encodeQueryComponent('{"reqId":0,"reqType":2,"p":1,"cnt":50,'
        '"listid":$boardId,"entityType":"song"}')}',
      );
      final response = await client.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 12) Mobile Safari/537.36',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('酷我服务器错误: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final list = data['data']?['list'] as List? ?? [];

      final results = <MusicInfo>[];
      for (final item in list) {
        final songInfo = item['musicinfo'] as Map?;
        if (songInfo == null) continue;
        final songId = songInfo['id']?.toString() ?? '';
        if (songId.isEmpty) continue;

        results.add(MusicInfo(
          id: 'kw_$songId',
          name: songInfo['songName']?.toString() ?? '',
          singer: songInfo['artist']?.toString() ?? '',
          album: songInfo['album']?.toString() ?? '',
          duration: (int.tryParse(songInfo['duration']?.toString() ?? '0') ?? 0) * 1000,
          source: 'kw',
          songId: songId,
          songmid: songId,
          imgUrl: songInfo['pic']?.toString(),
        ));
      }
      if (results.isEmpty) throw Exception('酷我榜单数据为空');
      return results;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('网络连接失败') || msg.contains('超时') || msg.contains('服务器错误') || msg.contains('数据为空')) {
        rethrow;
      }
      throw Exception('酷我榜单请求失败: $e');
    } finally {
      client.close();
    }
  }

  // ==================== 网易云榜单 ====================
  Future<List<MusicInfo>> _getWyBoard(String boardId) async {
    final client = http.Client();
    try {
      final response = await client.get(
        Uri.parse('https://music.163.com/api/playlist/detail?id=$boardId'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://music.163.com/',
          'Cookie': 'appver=2.9.7; os=android; osver=12',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('网易云服务器错误: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final tracks = data['result']?['tracks'] as List? ?? [];

      final results = <MusicInfo>[];
      for (final t in tracks) {
        final songId = t['id']?.toString() ?? '';
        if (songId.isEmpty) continue;
        final artists = t['artists'] as List? ?? [];
        final artist = artists.map((a) => a['name']?.toString() ?? '').join('、');
        final album = t['album'] as Map? ?? {};

        results.add(MusicInfo(
          id: 'wy_$songId',
          name: t['name']?.toString() ?? '',
          singer: artist,
          album: album['name']?.toString() ?? '',
          duration: (t['duration'] ?? 0) ~/ 1000,
          source: 'wy',
          songId: songId,
          imgUrl: album['picUrl']?.toString(),
        ));
      }
      if (results.isEmpty) throw Exception('网易云榜单数据为空');
      return results;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('网络连接失败') || msg.contains('超时') || msg.contains('服务器错误') || msg.contains('数据为空')) {
        rethrow;
      }
      throw Exception('网易云榜单请求失败: $e');
    } finally {
      client.close();
    }
  }

  // ==================== QQ音乐榜单 ====================
  Future<List<MusicInfo>> _getTxBoard(String boardId) async {
    final client = http.Client();
    try {
      final data = {
        'comm': {
          'uin': 0, 'format': 'json', 'ct': 24, 'cv': 0,
        },
        'req': {
          'module': 'musicToplist.ToplistInfoServer',
          'method': 'GetDetail',
          'param': {
            'topId': int.tryParse(boardId) ?? 26,
            'offset': 0,
            'num': 50,
            'period': '-1',
          },
        },
      };

      final sign = _zzcSign(jsonEncode(data));

      final request = http.Request(
        'POST',
        Uri.parse('https://u.y.qq.com/cgi-bin/musics.fcg?sign=$sign'),
      );
      request.headers.addAll({
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://y.qq.com/',
      });
      request.body = jsonEncode(data);
      final streamed = await client.send(request).timeout(const Duration(seconds: 15));
      final bodyBytes = await streamed.stream.toBytes();

      if (streamed.statusCode != 200) {
        throw Exception('QQ音乐服务器错误: ${streamed.statusCode}');
      }

      final resp = jsonDecode(utf8.decode(bodyBytes, allowMalformed: true));
      final songDataList = resp['req']?['data']?['songInfoList'] as List? ?? [];

      final results = <MusicInfo>[];
      for (final item in songDataList) {
        final songmid = item['mid']?.toString() ?? '';
        if (songmid.isEmpty) continue;
        final songId = item['id']?.toString() ?? '';
        final singers = item['singer'] as List? ?? [];
        final artist = singers.map((s) => s['name']?.toString() ?? '').join('、');
        final album = item['album'] as Map? ?? {};
        final albumMid = album['mid']?.toString() ?? '';

        results.add(MusicInfo(
          id: 'tx_$songmid',
          name: item['title']?.toString() ?? '',
          singer: artist,
          album: album['name']?.toString() ?? '',
          duration: item['interval'] ?? 0,
          source: 'tx',
          songId: songId,
          songmid: songmid,
          imgUrl: albumMid.isNotEmpty
              ? 'https://y.gtimg.cn/music/photo_new/T002R500x500M000$albumMid.jpg'
              : null,
        ));
      }
      if (results.isEmpty) throw Exception('QQ音乐榜单数据为空');
      return results;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('网络连接失败') || msg.contains('超时') || msg.contains('服务器错误') || msg.contains('数据为空')) {
        rethrow;
      }
      throw Exception('QQ音乐榜单请求失败: $e');
    } finally {
      client.close();
    }
  }

  // ==================== QQ签名 ====================
  String _zzcSign(String text) {
    final bytes = utf8.encode(text);
    final digest = sha1.convert(bytes);
    final hash = digest.toString();

    const part1Indexes = [23, 14, 6, 36, 16, 40, 7, 19];
    const part2Indexes = [16, 1, 32, 12, 19, 27, 8, 5];
    const scrambleValues = [89, 39, 179, 150, 218, 82, 58, 252, 177, 52,
        186, 123, 120, 64, 242, 133, 143, 161, 121, 179];

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
}
