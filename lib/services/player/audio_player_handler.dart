import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/music_model.dart';

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
      _baseMediaId = '';
      mediaItem.add(null);
      return;
    }
    _baseMediaId = music.id;
    _lastLyricText = null;
    try {
      final subtitle = '${music.singer} · ${music.album}';
      Uri? artUri;
      if (music.imgUrl != null && music.imgUrl!.isNotEmpty) {
        // 本地文件路径转 file:// URI
        if (music.source == 'local') {
          artUri = Uri.file(music.imgUrl!);
        } else {
          artUri = Uri.tryParse(music.imgUrl!);
        }
      }
      final item = MediaItem(
        id: music.id,
        title: music.name,
        artist: music.singer,
        album: music.album,
        artUri: artUri,
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
  ///
  /// 车机蓝牙歌词刷新策略：
  /// - mediaId 保持不变（同首歌 = 同 ID），避免被车机视为快速切歌而忽略
  /// - 只在歌词文本真正变化时才推 metadata，减少不必要的 IPC
  /// - 推送间隔 2 秒，给车机足够时间处理 metadata 变更
  /// - 每次推送同时更新 playbackState，通过 position 变化触发车机刷新
  void updateLyricLine(String? line) {
    if (_currentItem == null) return;
    final now = DateTime.now();
    // 节流：2 秒内不重复推送
    if (now.difference(_lastLyricPush).inMilliseconds < 2000) return;
    // 歌词没变就不推（但允许从有到无、从无到有的切换）
    final text = line ?? '';
    if (text == _lastLyricText) return;
    _lastLyricText = text;
    _lastLyricPush = now;

    try {
      final hasLine = line != null && line.isNotEmpty;
      final cur = _currentItem!;

      final updatedItem = MediaItem(
        // mediaId 保持不变 → 车机不视为切歌 → 正常刷新 metadata
        id: _baseMediaId,
        // title 放歌词 → 灵动岛/车机 AVRCP 读取
        title: hasLine ? line : cur.title,
        // artist 保持原歌手名
        artist: cur.artist,
        album: cur.album ?? '',
        artUri: cur.artUri,
        duration: cur.duration,
        displayTitle: hasLine ? line : (cur.displayTitle ?? cur.title),
        displaySubtitle: cur.artist ?? '',
        displayDescription: hasLine ? line : (cur.album ?? ''),
        extras: {
          'lyric': line ?? '',
        },
      );
      _currentItem = updatedItem;
      mediaItem.add(updatedItem);
      // 强制推一次 playbackState，确保车机/蓝牙收到元数据变更通知
      _broadcastState();
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
        artUri: _buildArtUri(m),
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
      final ci = _player.currentIndex;
      final qLen = queue.value.length;
      final validIndex = (ci != null && ci >= 0 && ci < qLen) ? ci : null;

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
        queueIndex: validIndex,
      ));
    } catch (_) {}
  }

  /// 构建 artUri：本地文件用 file:// 协议，网络用 http(s)
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
