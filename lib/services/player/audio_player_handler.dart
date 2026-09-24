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
  String? _lastLyricText;
  String _baseSongTitle = '';

  AudioPlayerHandler({
    required AudioPlayer player,
    required this.onPlayNext,
    required this.onPlayPrevious,
  })  : _player = player {
    _bindPlayerState();
  }

  StreamSubscription? _playbackSub;
  Timer? _posRefreshTimer;

  /// 缓存的"蓝牙歌词"开关。播放期间读取一次，避免 500ms tick 频繁读 SharedPreferences。
  bool _btLyricCached = true;

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
  /// 同时每 500ms 重写一次 LYRICS key：
  /// audio_service 的 setMediaItem 会用 createMediaMetadata 重建整个
  /// metadata bundle（不含 LYRICS key），把 MethodChannel 写入的歌词抹掉。
  /// 定期重写确保车机读到的 LYRICS 始终是当前行。
  void _updatePosRefreshTimer() {
    if (_player.playing && _btLyricCached) {
      _posRefreshTimer ??= Timer.periodic(
        const Duration(milliseconds: 500),
        (_) {
          _broadcastState();
          _rewriteLyricsMetadata();
        },
      );
    } else {
      _posRefreshTimer?.cancel();
      _posRefreshTimer = null;
    }
  }

  /// 重写 LYRICS key（不改 title，避免闪歌名）
  void _rewriteLyricsMetadata() {
    final line = _lastLyricText;
    if (line == null || line.isEmpty) return;
    // 参考 lx-music-mobile：title=歌词行，artist=歌名-歌手
    final cur = _currentItem;
    final songTitle = _baseSongTitle;
    unawaited(MediaSessionService().updateLyric(
      title: line,
      artist: songTitle.isEmpty ? (cur?.artist ?? '') : '$songTitle${(cur?.artist ?? '').isEmpty ? '' : ' - ${cur?.artist}'}',
      album: cur?.album ?? '',
      lyric: line,
      durationMs: (_player.duration ?? cur?.duration)?.inMilliseconds,
    ));
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
    _baseSongTitle = music.name;
    _lastLyricText = null;
    // 切歌时清空 session extras 歌词，避免旧歌歌词在 Jovi InCar 卡片残留
    unawaited(MediaSessionService().clearLyric());
    try {
      final subtitle = '${music.singer} · ${music.album}';
      Uri? artUri;
      if (music.imgUrl != null && music.imgUrl!.isNotEmpty) {
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

    unawaited(_readBluetoothLyricEnabled().then((enabled) {
      _btLyricCached = enabled;
      if (!enabled) return;
      _doPushLyric(line, text);
    }));
  }

  void _doPushLyric(String? line, String text) {
    try {
      final hasLine = line != null && line.isNotEmpty;
      final cur = _currentItem!;
      final dur = _player.duration;

      // 灵动岛/通知栏/Jovi InCar 卡片读 audio_service 的 this.mediaMetadata（由 mediaItem.add 驱动）
      // 蓝牙车机读 session.controller.metadata（由 MethodChannel 驱动）
      // 双路径：mediaItem.add() 走 audio_service 流，MethodChannel 直接写 session。
      // audio_service 的 Java setMediaItem 用 new Builder() 会重建 metadata，
      // 可能覆盖 MethodChannel 刚设的歌词。所以 MethodChannel 延迟 300ms 执行，确保最后写。
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
        extras: {
          'lyric': line ?? '',
          'lyrics': line ?? '',
          'android.media.metadata.LYRICS': line ?? '',
        },
      );
      mediaItem.add(_currentItem);

      Future.delayed(const Duration(milliseconds: 300), () {
        // 参考 lx-music-mobile：title=歌词行，artist=歌名-歌手
        final singer = cur.artist ?? '';
        final artistText = _baseSongTitle.isEmpty
            ? singer
            : '$_baseSongTitle${singer.isEmpty ? '' : ' - $singer'}';
        MediaSessionService().updateLyric(
          title: hasLine ? line! : cur.title,
          artist: artistText,
          album: cur.album ?? '',
          lyric: text,
          durationMs: (dur ?? cur.duration)?.inMilliseconds,
        );
        // 同时写入 PlaybackState extras（Jovi InCar 可能从这里读歌词）
        MediaSessionService().setPlaybackStateLyric(text);
      });

      // 车机蓝牙只在 PlaybackState 变化时才重新读取 metadata（androidx/media #430）。
      // mediaId 保持不变（避免车机判定"快速切歌"），所以每行歌词推送时
      // 主动触发一次 position+1ms 的 PlaybackState 更新，强制车机重读 title。
      if (hasLine) {
        _broadcastState(positionOffset: 1);
      }
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
        // Jovi InCar 可能从队列项的 MediaDescription extras 读歌词
        extras: {'lyric': '', 'lyrics': ''},
      )).toList();
      queue.add(items);
      if (currentIndex >= 0 && currentIndex < playlist.length) {
        final m = playlist[currentIndex];
        // 同一首歌：不要覆盖 _currentItem 的歌词 title/extras，
        // 否则队列同步会把歌词抹回歌名，车机显示歌名而非歌词行
        if (_currentItem?.id == m.id) {
          return;
        }
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
          extras: {'lyric': '', 'lyrics': ''},
        );
        _currentItem = item;
        _lastLyricText = null;
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