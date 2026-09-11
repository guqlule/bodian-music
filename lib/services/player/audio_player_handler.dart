import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/music_model.dart';

/// 音频后台服务 handler
/// 创建 Android MediaSession，让蓝牙耳机/车载通过 AVRCP 控制播放
class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;
  final Future<void> Function() onPlayNext;
  final Future<void> Function() onPlayPrevious;
  MediaItem? _currentItem;
  DateTime _lastLyricPush = DateTime(0);

  AudioPlayerHandler({
    required AudioPlayer player,
    required this.onPlayNext,
    required this.onPlayPrevious,
  })  : _player = player {
    _bindPlayerState();
  }

  StreamSubscription? _playbackSub;

  void _bindPlayerState() {
    _playbackSub = _player.playbackEventStream.listen((event) {
      _broadcastState();
    });
  }

  void cancelPlaybackSubscription() {
    _playbackSub?.cancel();
  }

  /// 更新媒体通知信息
  void updateNowPlaying(MusicInfo? music) {
    if (music == null) {
      _currentItem = null;
      mediaItem.add(null);
      return;
    }
    try {
      final subtitle = '${music.singer} · ${music.album}';
      final item = MediaItem(
        id: music.id,
        title: music.name,
        artist: music.singer,
        album: music.album,
        artUri: music.imgUrl != null && music.imgUrl!.isNotEmpty
            ? Uri.tryParse(music.imgUrl!) : null,
        duration: music.duration > 0 ? Duration(milliseconds: music.duration) : null,
        displayTitle: music.name,
        displaySubtitle: subtitle,
        displayDescription: music.album,
      );
      _currentItem = item;
      mediaItem.add(item);
    } catch (_) {}
  }

  /// 更新歌词行 — 通过 audio_service 的 mediaItem 推送到 MediaSession metadata
  /// audio_service 会将 title/artist/displayDescription 写入 MediaSession metadata，
  /// 蓝牙 AVRCP / 车机从这些字段读取歌词
  void updateLyricLine(String? line) {
    if (_currentItem == null) return;
    final now = DateTime.now();
    if (now.difference(_lastLyricPush).inMilliseconds < 300) return;
    _lastLyricPush = now;

    try {
      final hasLine = line != null && line.isNotEmpty;
      final cur = _currentItem!;
      final title = hasLine ? line : cur.title;
      final artist = hasLine
          ? '${cur.displayTitle ?? ''} · ${cur.artist ?? ''}'
          : (cur.artist ?? '');

      final updatedItem = MediaItem(
        id: cur.id,
        title: title,
        artist: artist,
        album: cur.album ?? '',
        artUri: cur.artUri,
        duration: cur.duration,
        displayTitle: title,
        displaySubtitle: artist,
        displayDescription: hasLine ? line : (cur.album ?? ''),
        extras: {
          'lyric': line ?? '',
        },
      );
      _currentItem = updatedItem;
      mediaItem.add(updatedItem);
    } catch (_) {}
  }

  /// 同步播放队列（车机浏览歌曲列表，HiCar/Jovi InCar 等使用）
  Future<void> syncQueueToSystem(List<MusicInfo> playlist, int currentIndex) async {
    try {
      final items = playlist.map((m) => MediaItem(
        id: m.id,
        title: m.name,
        artist: m.singer,
        album: m.album,
        artUri: m.imgUrl != null && m.imgUrl!.isNotEmpty
            ? Uri.tryParse(m.imgUrl!) : null,
        duration: m.duration > 0 ? Duration(milliseconds: m.duration) : null,
      )).toList();
      queue.add(items);
      // 确保当前播放项 metadata 与 queue 同步
      if (currentIndex >= 0 && currentIndex < playlist.length) {
        final m = playlist[currentIndex];
        final item = MediaItem(
          id: m.id,
          title: m.name,
          artist: m.singer,
          album: m.album,
          artUri: m.imgUrl != null && m.imgUrl!.isNotEmpty
              ? Uri.tryParse(m.imgUrl!) : null,
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

  /// 车机点选队列歌曲
  @override
  Future<void> skipToQueueItem(int index) async {
    await onPlayIndex?.call(index);
  }

  /// 设置按索引播放回调
  void setPlayIndexCallback(Future<void> Function(int index)? cb) {
    onPlayIndex = cb;
  }

  Future<void> Function(int index)? onPlayIndex;

  /// 同步播放状态给系统（蓝牙 AVRCP 依赖）
  void syncPlaybackState() => _broadcastState();

  void _broadcastState() {
    try {
      final playing = _player.playing;
      final processingState = _mapProcessingState(_player.processingState);

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
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _player.currentIndex ?? 0,
      ));
    } catch (_) {}
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

  // ==================== 蓝牙/系统媒体控制回调 ====================

  @override
  Future<void> play() async {
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
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
    await _player.stop();
    await super.stop();
  }
}
