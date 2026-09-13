import 'package:dio/dio.dart';
import '../../models/music_model.dart';

class MusicApi {
  final Dio _dio = Dio();
  
  static const String _baseUrl = 'https://lxmusicapi.example.com';
  
  MusicApi() {
    _dio.options.baseUrl = _baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.headers = {
      'User-Agent': 'LX Music Flutter/1.0.0',
    };
  }

  Future<List<MusicInfo>> search({
    required String keyword,
    required String source,
    int page = 1,
    int pageSize = 30,
  }) async {
    try {
      final response = await _dio.get(
        '/search',
        queryParameters: {
          'keyword': keyword,
          'source': source,
          'page': page,
          'pageSize': pageSize,
        },
      );
      
      if (response.statusCode == 200 && response.data['code'] == 200) {
        final List<dynamic> list = response.data['data']['list'] ?? [];
        return list.map((item) => MusicInfo.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      throw Exception('搜索失败: $e');
    }
  }

  Future<String?> getMusicUrl({
    required String musicId,
    required String source,
    String quality = '320',
  }) async {
    try {
      final response = await _dio.get(
        '/song/url',
        queryParameters: {
          'id': musicId,
          'source': source,
          'quality': quality,
        },
      );
      
      if (response.statusCode == 200 && response.data['code'] == 200) {
        return response.data['data']['url'];
      }
      return null;
    } catch (e) {
      throw Exception('获取播放地址失败: $e');
    }
  }

  Future<Map<String, String?>> getLyric({
    required String musicId,
    required String source,
  }) async {
    try {
      final response = await _dio.get(
        '/song/lyric',
        queryParameters: {
          'id': musicId,
          'source': source,
        },
      );
      
      if (response.statusCode == 200 && response.data['code'] == 200) {
        return {
          'lyric': response.data['data']['lyric'],
          'tlyric': response.data['data']['tlyric'],
          'rlyric': response.data['data']['rlyric'],
        };
      }
      return {};
    } catch (e) {
      throw Exception('获取歌词失败: $e');
    }
  }

  Future<String?> getCoverUrl({
    required String musicId,
    required String source,
  }) async {
    try {
      final response = await _dio.get(
        '/song/cover',
        queryParameters: {
          'id': musicId,
          'source': source,
        },
      );
      
      if (response.statusCode == 200 && response.data['code'] == 200) {
        return response.data['data']['coverUrl'];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getLeaderboard({
    required String source,
    String? boardId,
  }) async {
    try {
      final response = await _dio.get(
        '/leaderboard',
        queryParameters: {
          'source': source,
          if (boardId != null) 'boardId': boardId,
        },
      );
      
      if (response.statusCode == 200 && response.data['code'] == 200) {
        return List<Map<String, dynamic>>.from(response.data['data'] ?? []);
      }
      return [];
    } catch (e) {
      throw Exception('获取排行榜失败: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getSonglist({
    required String source,
    String? tag,
    int page = 1,
    int pageSize = 30,
  }) async {
    try {
      final response = await _dio.get(
        '/songlist',
        queryParameters: {
          'source': source,
          if (tag != null) 'tag': tag,
          'page': page,
          'pageSize': pageSize,
        },
      );
      
      if (response.statusCode == 200 && response.data['code'] == 200) {
        return List<Map<String, dynamic>>.from(response.data['data'] ?? []);
      }
      return [];
    } catch (e) {
      throw Exception('获取歌单失败: $e');
    }
  }

  Future<List<String>> getHotSearch({
    required String source,
  }) async {
    try {
      final response = await _dio.get(
        '/hotSearch',
        queryParameters: {
          'source': source,
        },
      );
      
      if (response.statusCode == 200 && response.data['code'] == 200) {
        return List<String>.from(response.data['data'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}
