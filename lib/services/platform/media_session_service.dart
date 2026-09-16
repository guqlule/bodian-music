import 'package:flutter/services.dart';

/// 直接更新原生 MediaSession metadata。
///
/// 绕过 audio_service 的 mediaItem.add()，避免频繁更新导致的
/// 通知重建、ANR、车机蓝牙歌词不刷新等问题（对齐 lx-music-mobile 方案）。
class MediaSessionService {
  static final MediaSessionService _instance = MediaSessionService._internal();
  factory MediaSessionService() => _instance;
  MediaSessionService._internal();

  static const _channel = MethodChannel('com.lxmusic/media_session');

  /// 直接更新 MediaSession 的 title/artist/album + 歌词 extras。
  /// 车机蓝牙从这些字段读取歌词显示。
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