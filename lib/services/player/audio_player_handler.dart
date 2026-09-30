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

  /// 是否接入车机（Jovi InCar / HiCar / Android Auto）。
  /// 车机模式下 title 必须保持歌名——车机首页卡片主位是 title，
  /// 写歌词会让标题一直跳歌词；歌词改走 LYRICS / displayDescription 字段。
  /// 蓝牙 AVRCP 车机只认 title，所以非车机模式才把歌词写进 title。
  bool _carMode = false;
  String? _lastKnownLine;
  int _carModeTick = 0;

  /// 重新检测车机接入状态。状态翻转时立即重推当前歌词，切换显示策略。
  Future<void> refreshCarMode() async {
    // 用户可在设置里强制指定车机模式（Jovi 走通知、AVRCP 走 title，
    // 自动检测对读通知的投屏车机不可靠，所以保留手动开关）
    var mode = 'auto';
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('app_settings');
      if (json != null) {
        mode = (jsonDecode(json) as Map)['carMode'] as String? ?? 'auto';
      }
    } catch (_) {}

    final bool v;
    if (mode == 'force') {
      v = true;
    } else if (mode == 'off') {
      v = false;
    } else {
      v = await MediaSessionService().isCarMode();
    }
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

  /// 车机进度条需要播放位置持续推进，所以每 1s 推一次真实位置。
  ///
  /// 关键：这里**绝对不能**碰 metadata。
  /// 之前每 500ms 重写一次 metadata，车机收到过密的元数据变更后
  /// 会判定数据不稳定并拒收后续更新（只认第一次），
  /// 表现为蓝牙歌词永远停在第一句。参考项目 lx-music-mobile 也只
  /// 在歌词行变化时写 metadata（3~5s 一次）。
  void _updatePosRefreshTimer() {
    if (_player.playing && _btLyricCached) {
      _posRefreshTimer ??= Timer.periodic(
        const Duration(milliseconds: 1000),
        (_) {
          _broadcastState();
          // 每 15s 复查一次车机接入状态
          if (++_carModeTick >= 15) {
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

      // 车机模式：title 保持歌名，歌词写进 artist（→ 通知 android.text）
      // 蓝牙模式：title 写歌词行（AVRCP 车机只认 title）
      final songTitle = _baseSongTitle.isEmpty ? cur.title : _baseSongTitle;
      final singer = cur.artist ?? '';
      final artistText = _baseSongTitle.isEmpty
          ? singer
          : '$_baseSongTitle${singer.isEmpty ? '' : ' - $singer'}';
      final metaTitle = _carMode ? songTitle : (hasLine ? line : songTitle);

      // 灵动岛/通知栏/Jovi InCar 卡片读 audio_service 的 this.mediaMetadata（由 mediaItem.add 驱动）
      // 蓝牙车机读 session.controller.metadata（由 MethodChannel 驱动）
      //
      // 蓝牙模式：MethodChannel 是唯一写入方。
      // 不再调 mediaItem.add —— 它会让 audio_service 抢着写 metadata，
      // 两个写入方交替覆盖，车机收到过密/矛盾的元数据后拒收后续更新。
      // 车机模式：仍需 audio_service 写（title 保持歌名，歌词进 extras）。
      if (_carMode) {
        // 车机/投屏模式（Jovi InCar / HiCar）
        //
        // 现状（vivo 官方 FAQ + 实车照片确认）：
        // 波点音乐属于 Jovi InCar「体验专区」，是**投屏**而非原生适配，
        // 车机用 CarLife 协议自绘一张通用音乐卡片，只认一份固定格式。
        // 实测该卡片：
        //   主标题 = metadata title   （正确）
        //   副标题 = metadata album   （写 artist/通知文本都无效，仍显示专辑名）
        //   歌词区 = 专用字段，未命中 → 显示"暂无歌词"
        //
        // 所以短期策略：**数据写干净**，不污染 artist/通知（否则显示更糟），
        // 同时保留标准歌词 key —— 对接了协议的车机就能显示，没对接的维持现状。
        _currentItem = MediaItem(
          id: _baseMediaId,
          title: songTitle,
          artist: singer,
          album: cur.album ?? '',
          artUri: cur.artUri,
          duration: dur ?? cur.duration,
          displayTitle: songTitle,
          displaySubtitle: singer,
          displayDescription: cur.album ?? '',
          extras: {
            'lyric': line ?? '',
            'lyrics': line ?? '',
            'android.media.metadata.LYRICS': line ?? '',
          },
        );
        mediaItem.add(_currentItem);
      }

      // 立即写入，不延迟：原生端在同一次调用里 setMetadata + setPlaybackState，
      // 与参考项目 MetadataManager.updateTitles() 的时序一致。
      unawaited(Future.wait([
        MediaSessionService().updateLyric(
          title: metaTitle,
          artist: artistText,
          album: cur.album ?? '',
          lyric: text,
          durationMs: (dur ?? cur.duration)?.inMilliseconds,
          positionMs: _player.position.inMilliseconds,
        ),
        // Jovi InCar 可能从 PlaybackState extras 读歌词
        MediaSessionService().setPlaybackStateLyric(text),
      ]));
    } catch (_) {}
  }

  Future<void> syncQueueToSystem(List<MusicInfo> playlist, int currentIndex) async {
    try {
      // 只把当前歌曲推进系统队列，不要把整个播放列表（可达 600 项）塞进去。
      //
      // 原因（dumpsys 实测）：塞 600 项时 queueTitle=size=600，
      // 每次歌词更新都会触发 Android 蓝牙栈的 onQueueChanged →
      // EVT_NOW_PLAYING_CHANGED，栈忙于同步队列而忽略 metadata 变化，
      // 车机因此停在第一句歌词。QQ 音乐的 session queue size=0，
      // 参考项目 lx-music-mobile 也不推队列，两者在车机上都能正常滚动。
      if (currentIndex < 0 || currentIndex >= playlist.length) {
        queue.add(<MediaItem>[]);
        return;
      }
      final m = playlist[currentIndex];
      queue.add([MediaItem(
        id: m.id,
        title: m.name,
        artist: m.singer,
        album: m.album,
        artUri: _buildArtUri(m),
        duration: m.duration > 0 ? Duration(milliseconds: m.duration) : null,
        // Jovi InCar 可能从队列项的 MediaDescription extras 读歌词
        extras: {'lyric': '', 'lyrics': ''},
      )]);

      // 同一首歌：不要覆盖 _currentItem 的歌词 title/extras，
      // 否则队列同步会把歌词抹回歌名，车机显示歌名而非歌词行
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

  void _broadcastState({int positionOffset = 0, Duration? positionOverride}) {
    try {
      final playing = _player.playing;
      final processingState = _mapProcessingState(_player.processingState);
      final ci = _player.currentIndex;
      final qLen = queue.value.length;
      final validIndex = (ci != null && ci >= 0 && ci < qLen) ? ci : null;
      var position = positionOverride ?? _player.position;
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