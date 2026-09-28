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

  /// 每行歌词的 mediaId 变体计数。
  /// 车机 AVRCP 用 mediaId 派生 UID 判断是否同一首歌，
  /// mediaId 不变车机不刷新 title → 每行换一个变体强制刷新。
  int _lyricMediaSeq = 0;
  String _currentLyricMediaId = '';

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

  /// 是否接入车机（Jovi InCar / HiCar / Android Auto）。
  /// 车机模式下 title 必须保持歌名——车机首页卡片主位是 title，
  /// 写歌词会让标题一直跳歌词；歌词改走 LYRICS / displayDescription 字段。
  /// 蓝牙 AVRCP 车机只认 title，所以非车机模式才把歌词写进 title。
  bool _carMode = false;
  String? _lastKnownLine;
  int _carModeTick = 0;

  /// 重新检测车机接入状态。状态翻转时立即重推当前歌词，切换显示策略。
  Future<void> refreshCarMode() async {
    final v = await MediaSessionService().isCarMode();
    if (v == _carMode) return;
    _carMode = v;
    final line = _lastKnownLine;
    if (line != null && line.isNotEmpty) {
      _lastLyricText = null;
      updateLyricLine(line);
    }
  }

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
          // 每 15s 复查一次车机接入状态
          if (++_carModeTick >= 30) {
            _carModeTick = 0;
            unawaited(refreshCarMode());
          }
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
    // 车机模式例外：title 保持歌名，避免 Jovi 首页卡片标题跳歌词
    final cur = _currentItem;
    final songTitle = _baseSongTitle;
    final metaTitle = _carMode
        ? (songTitle.isEmpty ? (cur?.title ?? '') : songTitle)
        : line;
    unawaited(MediaSessionService().updateLyric(
      title: metaTitle,
      artist: songTitle.isEmpty ? (cur?.artist ?? '') : '$songTitle${(cur?.artist ?? '').isEmpty ? '' : ' - ${cur?.artist}'}',
      album: cur?.album ?? '',
      lyric: line,
      durationMs: (_player.duration ?? cur?.duration)?.inMilliseconds,
      mediaId: _currentLyricMediaId.isEmpty ? null : _currentLyricMediaId,
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
    _lyricMediaSeq = 0;
    _currentLyricMediaId = '';
    _lastLyricText = null;
    _lastKnownLine = null;
    unawaited(refreshCarMode());
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
    _lastKnownLine = text;
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

      // 车机 AVRCP 用 mediaId 派生 UID 判定曲目，mediaId 不变则忽略 title 变化。
      // 每行歌词递增一个 mediaId 变体，强制车机判定"曲目变化"→重读 title（歌词行）。
      if (hasLine) {
        _lyricMediaSeq++;
        _currentLyricMediaId = '$_baseMediaId#$_lyricMediaSeq';
      } else {
        _currentLyricMediaId = '';
      }

      // 车机模式：title 保持歌名，歌词放 displaySubtitle/displayDescription/extras
      // 蓝牙模式：title 写歌词行（AVRCP 车机只认 title）
      final songTitle = _baseSongTitle.isEmpty ? cur.title : _baseSongTitle;
      final singer = cur.artist ?? '';
      final artistText = _baseSongTitle.isEmpty
          ? singer
          : '$_baseSongTitle${singer.isEmpty ? '' : ' - $singer'}';
      final metaTitle = _carMode ? songTitle : (hasLine ? line : songTitle);
      final metaSubtitle = _carMode
          ? (hasLine ? line : '')
          : (cur.artist ?? '');

      // 灵动岛/通知栏/Jovi InCar 卡片读 audio_service 的 this.mediaMetadata（由 mediaItem.add 驱动）
      // 蓝牙车机读 session.controller.metadata（由 MethodChannel 驱动）
      // 双路径：mediaItem.add() 走 audio_service 流，MethodChannel 直接写 session。
      //
      // 关键：MediaItem.id 也要用递增变体。
      // 车机 AVRCP 只在「mediaId 派生 UID 变化」时才收到 EVT_TRACK_CHANGED 并重读 title。
      // audio_service 的 setMediaItem 在后台线程执行（封面为网络 URL 时还会等封面加载），
      // 常常晚于 MethodChannel 落地。若 MediaItem.id 固定，uid 会被写回旧值，
      // 车机就永远停在第一句歌词。两路写入共用同一个变体 id，先后顺序不再重要。
      _currentItem = MediaItem(
        id: _currentLyricMediaId.isEmpty ? _baseMediaId : _currentLyricMediaId,
        title: metaTitle,
        artist: cur.artist,
        album: cur.album ?? '',
        artUri: cur.artUri,
        duration: dur ?? cur.duration,
        displayTitle: metaTitle,
        displaySubtitle: metaSubtitle,
        displayDescription: hasLine ? line : (cur.album ?? ''),
        extras: {
          'lyric': line ?? '',
          'lyrics': line ?? '',
          'android.media.metadata.LYRICS': line ?? '',
        },
      );
      mediaItem.add(_currentItem);

      Future.delayed(const Duration(milliseconds: 300), () {
        MediaSessionService().updateLyric(
          title: metaTitle,
          artist: artistText,
          album: cur.album ?? '',
          lyric: text,
          durationMs: (dur ?? cur.duration)?.inMilliseconds,
          mediaId: _currentLyricMediaId.isEmpty ? null : _currentLyricMediaId,
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
        // 注意：_currentItem.id 在推送歌词时是递增变体，所以比对 _baseMediaId
        if (_baseMediaId == m.id) {
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
    await refreshCarMode();
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