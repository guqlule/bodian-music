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
  int _lyricSeq = 0; // 歌词序号：微调 mediaId 强制车机重新读取 metadata

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
    _lyricSeq = 0;
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

  /// 更新实际播放时长 — 当 audioService 首次获取到真实时长时调用
  /// 用于修复 music.duration=0 时灵动岛/车机不显示进度条的问题
  void updateDuration(Duration duration) {
    if (_currentItem == null) return;
    final cur = _currentItem!;
    // 避免重复推送相同时长
    if (cur.duration == duration) return;
    final updatedItem = cur.copyWith(duration: duration);
    _currentItem = updatedItem;
    mediaItem.add(updatedItem);
  }

  /// 更新歌词行 — 通过 audio_service 的 mediaItem 推送到 MediaSession metadata
  /// audio_service 会将 title/artist/displayDescription 写入 MediaSession metadata，
  /// 蓝牙 AVRCP / 车机从这些字段读取歌词
  ///
  /// 车机蓝牙歌词刷新策略（参考 androidx/media Issue #430 + 小Q/洛雪音乐）：
  /// - 车机的 Bluetooth.apk 只有在 playback state 变化时才重新读取 metadata
  /// - 单纯推 metadata 变化，车机不会刷新显示
  /// - 所以每次推歌词时，同时推 playback state（position 微调），触发车机重新读取
  /// - **仅在歌词行实际变化时推**（小Q/洛雪音乐的做法），不做时间节流
  /// - 歌词行通常 3-8 秒一行，避免每秒强制刷新
  void updateLyricLine(String? line) {
    if (_currentItem == null) return;
    // 歌词没变就不推（但允许从有到无、从无到有的切换）
    final text = line ?? '';
    if (text == _lastLyricText) return;
    _lastLyricText = text;
    _lastLyricPush = DateTime.now();

    try {
      final hasLine = line != null && line.isNotEmpty;
      final cur = _currentItem!;

      // 微调 mediaId 后缀强制车机重新读取 metadata
      // 不同车机对 mediaId 变化敏感程度不同，加序号确保触发
      _lyricSeq++;
      final updatedItem = MediaItem(
        id: '$_baseMediaId#$_lyricSeq',
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
      // 关键：同时推 playback state（带 position 微调）
      // 车机 Bluetooth.apk 只在 playback state 变化时重新读取 metadata
      _broadcastState(positionOffset: 1);
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
  /// [positionOffset] 用于歌词推送时微调 position，触发车机重新读取 metadata
  void syncPlaybackState() => _broadcastState();

  void _broadcastState({int positionOffset = 0}) {
    try {
      final playing = _player.playing;
      final processingState = _mapProcessingState(_player.processingState);
      final ci = _player.currentIndex;
      final qLen = queue.value.length;
      final validIndex = (ci != null && ci >= 0 && ci < qLen) ? ci : null;
      // 微调 position → 车机检测到 playback state 变化 → 重新读取 metadata
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
