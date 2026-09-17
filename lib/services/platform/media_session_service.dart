import 'package:flutter/services.dart';

/// 直接更新原生 MediaSession metadata。
/// 走 MethodChannel `com.lxmusic/media_session` → 原生 MediaSessionHelper
class MediaSessionService {
  static final MediaSessionService _instance = MediaSessionService._internal();
  factory MediaSessionService() => _instance;
  MediaSessionService._internal();

  static const _channel = MethodChannel('com.lxmusic/media_session');

  /// 直接更新 MediaSession 的 title/artist/album + 歌词 extras。
  /// 原生端一次性反射拿到 audio_service 内部的 MediaSession，缓存后用公开 API setMetadata 推送。
  Future<bool> updateLyric({
    required String title,
    required String artist,
    required String album,
    String lyric = '',
    String? artPath,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('updateLyric', {
        'title': title,
        'artist': artist,
        'album': album,
        'lyric': lyric,
        if (artPath != null) 'artPath': artPath,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}