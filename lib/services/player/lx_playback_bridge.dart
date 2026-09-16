import 'dart:async';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/music_model.dart';

/// 替换 audio_service 的 BaseAudioHandler。
/// 直接通过 MethodChannel `com.lxmedia/playback_methods` 推送元数据，
/// 通过 EventChannel `com.lxmedia/playback_events` 接收蓝牙/车机控制命令。
///
/// 实际音频播放仍由 just_audio 完成（与原生 LxPlaybackService 配合）。
class LxPlaybackBridge {
  LxPlaybackBridge({
    required AudioPlayer player,
    required this.onPlayNext,
    required this.onPlayPrevious,
  }) : _player = player {
    _bindPlayerState();
    _bindIncomingEvents();
  }

  final AudioPlayer _player;
  final Future<void> Function() onPlayNext;
  final Future<void> Function() onPlayPrevious;
  Future<void> Function(int index)? onPlayIndex;

  static const _methods = MethodChannel('com.lxmedia/playback_methods');
  static const _events = EventChannel('com.lxmedia/playback_events');

  StreamSubscription? _playbackSub;
  StreamSubscription? _eventsSub;
  Timer? _posRefreshTimer;

  String _baseMediaId = '';
  String _currentTitle = '';
  String _currentArtist = '';
  String _currentAlbum = '';
  String? _currentArtUri;
  Duration _currentDuration = Duration.zero;
  int _currentQueueIndex = 0;

  bool _btLyricCached = true;

  Future<bool> _readBluetoothLyricEnabled() async {
    try {
      // 委托给 MediaSessionService（已存在 SharedPreferences 读取逻辑）
      final svc = await _ensureService();
      return svc.isBluetoothLyricEnabled();
    } catch (_) {
      return true;
    }
  }

  // 避免循环依赖：LxMediaSessionService 是单例
  Future<dynamic> _ensureService() async {
    return _PlatformService.instance;
  }

  void _bindPlayerState() {
    _playbackSub = _player.playbackEventStream.listen((_) {
      _broadcastState();
      _updatePosRefreshTimer();
    });
  }

  void _bindIncomingEvents() {
    _eventsSub = _events.receiveBroadcastStream().listen((data) {
      if (data is! Map) return;
      final event = data['event'] as String?;
      switch (event) {
        case 'play':
          _player.play();
          break;
        case 'pause':
          _player.pause();
          break;
        case 'stop':
          _player.stop();
          break;
        case 'skipToNext':
          onPlayNext();
          break;
        case 'skipToPrevious':
          onPlayPrevious();
          break;
        case 'seekTo':
          final pos = (data['data'] as Map?)?['position'] as int? ?? 0;
          _player.seek(Duration(milliseconds: pos));
          break;
        case 'skipToQueueItem':
          final id = (data['data'] as Map?)?['id'] as int?;
          if (id != null) onPlayIndex?.call(id.toInt());
          break;
        case 'becomingNoisy':
          _player.pause();
          break;
        case 'playFromMediaId':
          final id = (data['data'] as Map?)?['mediaId'] as String?;
          if (id != null) _playByMediaId(id);
          break;
      }
    }, onError: (Object _) {});
  }

  void _playByMediaId(String mediaId) {
    // 由 PlayerService 通过 onPlayIndex 接管（mediaId 实际是 baseMediaId）
    onPlayIndex?.call(_findIndexById(mediaId));
  }

  int _findIndexById(String id) {
    // 由外部在 syncQueueToSystem 时填充
    for (int i = 0; i < _cachedQueue.length; i++) {
      if (_cachedQueue[i].id == id) return i;
    }
    return 0;
  }

  final List<MusicInfo> _cachedQueue = [];

  void _updatePosRefreshTimer() {
    if (_player.playing && _btLyricCached) {
      _posRefreshTimer ??= Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _broadcastState(),
      );
    } else {
      _posRefreshTimer?.cancel();
      _posRefreshTimer = null;
    }
  }

  void _broadcastState() {
    final playing = _player.playing;
    final position = _player.position;
    unawaited(_methods.invokeMethod('setPlaybackState', {
      'playing': playing,
      'position': position.inMilliseconds,
      'bufferedPosition': _player.bufferedPosition.inMilliseconds,
      'speed': _player.speed,
      'queueIndex': _currentQueueIndex,
    }));
  }

  // ============== 公共 API（供 PlayerService 调用）==============

  /// 更新当前播放的歌曲（切歌时调）
  void updateNowPlaying(MusicInfo? music) {
    if (music == null) {
      _currentTitle = '';
      _currentArtist = '';
      _currentAlbum = '';
      _currentArtUri = null;
      _currentDuration = Duration.zero;
      _baseMediaId = '';
      return;
    }
    _baseMediaId = music.id;
    _currentTitle = music.name;
    _currentArtist = music.singer;
    _currentAlbum = music.album;
    _currentArtUri = _buildArtUri(music);
    _currentDuration = music.duration > 0
        ? Duration(milliseconds: music.duration)
        : Duration.zero;
    _pushMetadata();
  }

  /// 更新真实时长（首次缓冲完成时调）
  void updateDuration(Duration duration) {
    if (_currentDuration == duration) return;
    _currentDuration = duration;
    _pushMetadata();
  }

  /// 更新歌词行（轻量，绕过 notification rebuild）
  Future<void> updateLyricLine(String? line) async {
    final enabled = await _readBluetoothLyricEnabled();
    _btLyricCached = enabled;
    if (!enabled) return;

    final hasLine = line != null && line.isNotEmpty;
    final title = hasLine ? line : _currentTitle;
    final displayDesc = hasLine ? line : _currentAlbum;

    unawaited(_methods.invokeMethod('setMetadata', {
      'mediaId': _baseMediaId,
      'title': title,
      'artist': _currentArtist,
      'album': _currentAlbum,
      'duration': _currentDuration.inMilliseconds,
      'artUri': _currentArtUri,
      'lyric': line ?? '',
      'displayDescription': displayDesc,
    }));
  }

  /// 同步队列到系统
  Future<void> syncQueueToSystem(List<MusicInfo> playlist, int currentIndex) async {
    _cachedQueue
      ..clear()
      ..addAll(playlist);
    _currentQueueIndex = currentIndex;

    final rawItems = playlist.map((m) => {
      'id': m.id,
      'title': m.name,
      'artist': m.singer,
      'album': m.album,
      'duration': m.duration > 0 ? m.duration : 0,
    }).toList();
    unawaited(_methods.invokeMethod('setQueue', {
      'items': rawItems,
      'currentIndex': currentIndex,
    }));
  }

  /// 同步播放状态（车机 AVRCP 依赖）
  void syncPlaybackState() => _broadcastState();

  /// 直接播放/暂停/停止/快进快退（供 PlayerService 调用）
  Future<void> play() async {
    await _player.play();
    _btLyricCached = await _readBluetoothLyricEnabled();
    _updatePosRefreshTimer();
  }

  Future<void> pause() async {
    await _player.pause();
    _updatePosRefreshTimer();
  }

  Future<void> stop() async {
    _posRefreshTimer?.cancel();
    _posRefreshTimer = null;
    await _player.stop();
    unawaited(_methods.invokeMethod('setActive', {'active': false}));
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> skipToNext() async {
    await onPlayNext();
  }

  Future<void> skipToPrevious() async {
    await onPlayPrevious();
  }

  Future<void> skipToQueueItem(int index) async {
    await onPlayIndex?.call(index);
  }

  Future<void> dispose() async {
    _posRefreshTimer?.cancel();
    await _playbackSub?.cancel();
    await _eventsSub?.cancel();
  }

  // ============== 内部 ==============

  void _pushMetadata() {
    unawaited(_methods.invokeMethod('setMetadata', {
      'mediaId': _baseMediaId,
      'title': _currentTitle,
      'artist': _currentArtist,
      'album': _currentAlbum,
      'duration': _currentDuration.inMilliseconds,
      'artUri': _currentArtUri,
      'lyric': '',
      'displayDescription': _currentAlbum,
    }));
  }

  String? _buildArtUri(MusicInfo m) {
    if (m.imgUrl == null || m.imgUrl!.isEmpty) return null;
    if (m.source == 'local') return 'file://${m.imgUrl}';
    return m.imgUrl;
  }
}

/// 单例代理，用于跨文件访问，避免循环 import
class _PlatformService {
  static final _PlatformService instance = _PlatformService._();
  _PlatformService._();

  /// 检查蓝牙歌词开关
  Future<bool> isBluetoothLyricEnabled() async {
    // 由 MediaSessionService 的 updateLyric 同款逻辑处理
    try {
      final result = await _checkChannel.invokeMethod<bool>('isBluetoothLyricEnabled');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  static const _checkChannel = MethodChannel('com.lxmusic/bluetooth_lyric_check');
}