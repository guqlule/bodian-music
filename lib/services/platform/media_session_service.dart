import 'package:flutter/services.dart';

/// 直接更新原生 MediaSession metadata。
/// 走 MethodChannel `com.lxmusic/media_session` → 原生 MediaSessionHelper
class MediaSessionService {
  static final MediaSessionService _instance = MediaSessionService._internal();
  factory MediaSessionService() => _instance;
  MediaSessionService._internal();

  static const _channel = MethodChannel('com.lxmusic/media_session');

  /// 直接更新 MediaSession 的 title/artist/album + 歌词。
  /// 原生端一次性反射拿到 audio_service 内部的 MediaSession，缓存后用公开 API setMetadata 推送。
  Future<bool> updateLyric({
    required String title,
    required String artist,
    required String album,
    String lyric = '',
    String? fullLyric,
    int? durationMs,
    int? positionMs,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('updateLyric', {
        'title': title,
        'artist': artist,
        'album': album,
        'lyric': lyric,
        if (fullLyric != null) 'fullLyric': fullLyric,
        if (durationMs != null) 'durationMs': durationMs,
        if (positionMs != null) 'positionMs': positionMs,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 切歌时清空歌词 extras，避免旧歌歌词残留
  Future<bool> clearLyric() async {
    try {
      final result = await _channel.invokeMethod<bool>('clearLyric');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 将歌词写入 PlaybackState extras（Jovi InCar 可能从这里读）
  Future<bool> setPlaybackStateLyric(String lyric) async {
    try {
      final result = await _channel.invokeMethod<bool>('setPlaybackStateLyric', {
        'lyric': lyric,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 是否接入车机（Jovi InCar / HiCar / Android Auto 等）。
  /// 车机模式下 title 必须保持歌名（否则首页卡片标题会跳歌词），
  /// 歌词只写 LYRICS / displayDescription 字段。
  Future<bool> isCarMode() async {
    try {
      final result = await _channel.invokeMethod<bool>('isCarMode');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}