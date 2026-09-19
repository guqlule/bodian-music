import 'dart:async';
import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/music_model.dart';
import '../platform/media_session_service.dart';

/// 音频后台服务 handler
/// 创建 Android MediaSession，让蓝牙耳机/车载通过 AVRCP 控制播放
///
/// 车机蓝牙歌词显示原理：
/// - 车机通过 AVRCP 读取 MediaSession metadata（title 字段）
/// - 大部分车机只在 mediaId 变化时才重新读取 metadata
/// - 但 mediaId 频繁变化会被车机视为"快速切歌"而忽略
/// - 所以用一种折中方案：歌曲播放期间 mediaId 不变，
///   通过 PlaybackState 的 position 更新触发车机刷新 metadata
class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;
  final Future<void> Function() onPlayNext;
  final Future<void> Function() onPlayPrevious;
  MediaItem? _currentItem;
  String _baseMediaId = '';
  DateTime _lastLyricPush = DateTime(0);
  String? _lastLyricText;
  bool _btLyricCached = true;

  AudioPlayerHandler({
    required AudioPlayer player,
    required this.onPlayNext,
    required this.onPlayPrevious,
  })  : _player = player {
    _bindPlayerState();
  }

  StreamSubscription? _playbackSub;
  Timer? _posRefreshTimer;



  /// 是否启用蓝牙/车机歌词推送。从 SharedPreferences 读取。
  Future<bool> _readBluetoothLyricEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('app_settings');
      if (json == null) return true;
      final map = jsonDecode(json) as Map;
      return (map['enableBluetoothLyric'] as bool?) ?? true;
    } catch (_) {
      return true;
    }
  }

  void _bindPlayerState() {
    _playbackSub = _player.playbackEventStream.listen((event) {
      _broadcastState();
      _updatePosRefreshTimer();
    });
  }

  /// 古早车机蓝牙只在 playbackState position 变化时才刷新显示。
  void _updatePosRefreshTimer() {
    if (_player.playing) {
      _posRefreshTimer ??= Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _broadcastState(),
      );
    } else {
      _posRefreshTimer?.cancel();
      _posRefreshTimer = null;
    }
  }

  void cancelPlaybackSubscription() {
    _playbackSub?.cancel();
  }

  /// 更新媒体通知信息
  void updateNowPlaying(MusicInfo? music) {
    if (music == null) {
      _currentItem = null;
      _baseMediaId = '';
      mediaItem.add(null);
      return;
    }
    _baseMediaId = music.id;
    _lastLyricText = null;
    try {
      final item = MediaItem(
        id: music.id,
        title: music.name,
        artist: music.singer,
        album: music.album,
        artUri: _buildArtUri(music),
        duration: music.duration > 0 ? Duration(milliseconds: music.duration) : null,
        displayTitle: music.name,
        displaySubtitle: '${music.singer} · ${music.album}',
        displayDescription: music.album,
      );
      _currentItem = item;
      mediaItem.add(item);
    } catch (_) {}
  }

  void updateDuration(Duration duration) {
    if (_currentItem == null) return;
    final item = _currentItem!.copyWith(duration: duration);
    _currentItem = item;
    mediaItem.add(item);
  }

  void updateLyricLine(String? line) {
    if (_currentItem == null) return;
    final text = line ?? '';
    if (text == _lastLyricText) return;
    _lastLyricText = text;
    _lastLyricPush = DateTime.now();

    if (!_btLyricCached) return;
    _doPushLyric(line, text);
  }

  void _doPushLyric(String? line, String text) {
    try {
      final hasLine = line != null && line.isNotEmpty;
      final cur = _currentItem!;
      final dur = _player.duration;

      // 仅更新本地 _currentItem（不调 mediaItem.add）
      _currentItem = MediaItem(
        id: _baseMediaId,
        title: hasLine ? line : cur.title,
        artist: cur.artist,
        album: cur.album ?? '',
        artUri: cur.artUri,
        duration: dur ?? cur.duration,
        displayTitle: hasLine ? line : (cur.displayTitle ?? cur.title),
        displaySubtitle: cur.artist ?? '',
        displayDescription: hasLine ? line : (cur.album ?? ''),
        extras: {'lyric': line ?? ''},
      );
      // 不调 mediaItem.add()！
      // audio_service 的 setMediaItem → Java new Builder() → session.setMetadata()
      // 会覆盖 MethodChannel 刚设的歌词 metadata，导致蓝牙歌词不更新。
      // 只用 MethodChannel 直接写 session.setMetadata()，走 AVRCP。
      MediaSessionService().updateLyric(
        title: hasLine ? line! : cur.title,
        artist: cur.artist ?? '',
        album: cur.album ?? '',
        lyric: text,
        durationMs: (dur ?? cur.duration)?.inMilliseconds,
      );
    } catch (_) {}
  }

  Future<void> syncQueueToSystem(List<MusicInfo> playlist, int currentIndex) async {
    try {
      final items = playlist.map((m) => MediaItem(
        id: m.id,
        title: m.name,
        artist: m.singer,
        album: m.album,
        artUri: _buildArtUri(m),
        duration: m.duration > 0 ? Duration(milliseconds: m.duration) : null,
      )).toList();
      queue.add(items);
      if (currentIndex >= 0 && currentIndex < playlist.length) {
        final m = playlist[currentIndex];
        final item = MediaItem(
          id: m.id,
          title: m.name,
          artist: m.singer,
          album: m.album,
          artUri: _buildArtUri(m),
          duration: m.duration > 0 ? Duration(milliseconds: m.duration) : null,
          displayTitle: m.name,
          displaySubtitle: '',
          displayDescription: m.album,
        );
        _currentItem = item;
        mediaItem.add(item);
      }
    } catch (_) {}
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await onPlayIndex?.call(index);
  }

  void setPlayIndexCallback(Future<void> Function(int index)? cb) {
    onPlayIndex = cb;
  }

  Future<void> Function(int index)? onPlayIndex;

  void syncPlaybackState() => _broadcastState();

  void _broadcastState({int positionOffset = 0}) {
    try {
      final playing = _player.playing;
      final processingState = _mapProcessingState(_player.processingState);
      final ci = _player.currentIndex;
      final qLen = queue.value.length;
      final validIndex = (ci != null && ci >= 0 && ci < qLen) ? ci : null;
      var position = _player.position;
      if (positionOffset > 0) {
        position = position + Duration(milliseconds: positionOffset);
      }

      playbackState.add(PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        processingState: processingState,
        playing: playing,
        updatePosition: position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: validIndex,
      ));
    } catch (_) {}
  }

  static Uri? _buildArtUri(MusicInfo m) {
    if (m.imgUrl == null || m.imgUrl!.isEmpty) return null;
    if (m.source == 'local') return Uri.file(m.imgUrl!);
    return Uri.tryParse(m.imgUrl!);
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  @override
  Future<void> play() async {
    await _player.play();
    _btLyricCached = await _readBluetoothLyricEnabled();
    _updatePosRefreshTimer();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _updatePosRefreshTimer();
  }

  @override
  Future<void> skipToNext() async {
    await onPlayNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await onPlayPrevious();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  @override
  Future<void> stop() async {
    _posRefreshTimer?.cancel();
    _posRefreshTimer = null;
    await _player.stop();
    await super.stop();
  }
}