import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:audio_service/audio_service.dart';
import 'package:http/http.dart' as http;
import '../../models/music_model.dart';
import '../api/music_url_service.dart';
import '../api/music_search_service.dart';
import '../api/lyric_api_service.dart';
import '../lyric/lyric_parser.dart';
import '../local/local_music_service.dart';
import 'audio_player_handler.dart';
import 'player_storage.dart';
import '../../core/utils/logger.dart';

enum PlayMode {
  listLoop,     // 列表循环
  random,       // 随机播放
  singleLoop,   // 单曲循环
  list,         // 顺序播放
  none,         // 禁用自动切歌
}

class PlayerService {
  // 单例：保证 App 生命周期钩子与 Riverpod provider 使用同一实例
  static final PlayerService instance = PlayerService._internal();
  factory PlayerService() => instance;
  PlayerService._internal() {
    _init();
  }
  final AudioPlayer _audioPlayer = AudioPlayer();
  AudioPlayer get audioPlayer => _audioPlayer;
  final MusicUrlService _urlService = MusicUrlService();
  final MusicSearchService _searchService = MusicSearchService();
  final LyricApiService _lyricApiService = LyricApiService();
  AudioPlayerHandler? _mediaHandler;
  final Completer<void> _mediaSessionReady = Completer<void>();
  // 音质偏好：始终按最高音质请求，脚本/MusicUrlService 内部会自动降级
  String _preferredQuality = 'flac';
  bool _prefetchEnabled = true;
  void setPrefetchEnabled(bool enabled) => _prefetchEnabled = enabled;
  void setPreferredQuality(String settingsQuality) {
    // 直接映射音质档位（128k/320k/flac/flac24bit，对齐原版四档）
    _preferredQuality = settingsQuality;
    logDebug('[Quality] 音质偏好: $_preferredQuality');
  }

  final BehaviorSubject<List<MusicInfo>> _playlistController = BehaviorSubject<List<MusicInfo>>.seeded([]);
  final BehaviorSubject<List<MusicInfo>> _tempPlaylistController = BehaviorSubject<List<MusicInfo>>.seeded([]);
  final BehaviorSubject<List<MusicInfo>> _playedListController = BehaviorSubject<List<MusicInfo>>.seeded([]);
  final BehaviorSubject<int> _currentIndexController = BehaviorSubject<int>.seeded(-1);
  final BehaviorSubject<MusicInfo?> _currentMusicController = BehaviorSubject<MusicInfo?>.seeded(null);
  final BehaviorSubject<bool> _isPlayingController = BehaviorSubject<bool>.seeded(false);
  final BehaviorSubject<Duration> _positionController = BehaviorSubject<Duration>.seeded(Duration.zero);
  final BehaviorSubject<Duration?> _durationController = BehaviorSubject<Duration?>.seeded(null);
  final BehaviorSubject<PlayMode> _playModeController = BehaviorSubject<PlayMode>.seeded(PlayMode.listLoop);
  final BehaviorSubject<List<MusicInfo>> _playHistoryController = BehaviorSubject<List<MusicInfo>>.seeded([]);
  final BehaviorSubject<String> _statusTextController = BehaviorSubject<String>.seeded('');
  final BehaviorSubject<bool> _isLoadingController = BehaviorSubject<bool>.seeded(false);
  final BehaviorSubject<bool> _isSleepTimerActiveController = BehaviorSubject<bool>.seeded(false);
  final BehaviorSubject<Duration?> _sleepTimerRemainingController = BehaviorSubject<Duration?>.seeded(null);
  final BehaviorSubject<Map<String, String?>?> _lyricController = BehaviorSubject<Map<String, String?>?>.seeded(null);

  Stream<List<MusicInfo>> get playlistStream => _playlistController.stream;
  Stream<List<MusicInfo>> get tempPlaylistStream => _tempPlaylistController.stream;
  Stream<List<MusicInfo>> get playedListStream => _playedListController.stream;
  Stream<int> get currentIndexStream => _currentIndexController.stream;
  Stream<MusicInfo?> get currentMusicStream => _currentMusicController.stream;
  Stream<bool> get isPlayingStream => _isPlayingController.stream;
  Stream<String> get qualityStream => _qualityController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration?> get durationStream => _durationController.stream;
  Stream<PlayMode> get playModeStream => _playModeController.stream;
  Stream<List<MusicInfo>> get playHistoryStream => _playHistoryController.stream;
  Stream<String> get statusTextStream => _statusTextController.stream;
  Stream<bool> get isLoadingStream => _isLoadingController.stream;
  Stream<bool> get isSleepTimerActiveStream => _isSleepTimerActiveController.stream;
  Stream<Duration?> get sleepTimerRemainingStream => _sleepTimerRemainingController.stream;
  Stream<Map<String, String?>?> get lyricStream => _lyricController.stream;

  List<MusicInfo> get currentPlaylist => _playlistController.value;
  List<MusicInfo> get tempPlaylist => _tempPlaylistController.value;
  List<MusicInfo> get playedList => _playedListController.value;
  int get currentIndex => _currentIndexController.value;
  MusicInfo? get currentMusic => _currentMusicController.value;
  bool get isPlaying => _isPlayingController.value;
  PlayMode get playMode => _playModeController.value;
  List<MusicInfo> get playHistory => _playHistoryController.value;

  Timer? _retryTimer;
  Timer? _loadTimeoutTimer;
  Timer? _sleepTimer;
  Timer? _sleepTimerTickTimer;
  Timer? _playlistSaveTimer;
  Timer? _queueSyncTimer;
  int _retryCount = 0;
  int _loadRequestId = 0;
  int _lyricRequestId = 0; // 歌词请求独立ID，防止旧歌词覆盖新歌
  static const int _maxRetryCount = 2;
  static const Duration _loadTimeout = Duration(seconds: 25);
  static const Duration _retryDelay = Duration(seconds: 3);
  final Random _random = Random();

  // Stream subscriptions for cleanup
  final List<StreamSubscription> _subscriptions = [];
  final PlayerStorage _storage = PlayerStorage();
  final LocalMusicService _localMusicService = LocalMusicService();
  final BehaviorSubject<String> _qualityController = BehaviorSubject<String>.seeded('');

  static const int _maxHistorySize = 100;

  DateTime _lastMediaSync = DateTime.fromMillisecondsSinceEpoch(0);

  void _init() {
    _subscriptions.add(_audioPlayer.positionStream.listen((position) {
      // 节流：仅当秒数变化或首尾时才更新，避免60fps触发rebuild
      final last = _positionController.value;
      if (position.inMilliseconds - last.inMilliseconds >= 200 ||
          position == Duration.zero ||
          (_durationController.value != null && position >= _durationController.value!)) {
        _positionController.add(position);
      }
      // 节流：歌词同步 + MediaSession 同步限频至每1秒一次
      final now = DateTime.now();
      if (now.difference(_lastMediaSync).inMilliseconds >= 1000) {
        _lastMediaSync = now;
        _updateMediaLyric(position);
        _mediaHandler?.syncPlaybackState();
      }
    }));

    _subscriptions.add(_audioPlayer.durationStream.listen((duration) {
      _durationController.add(duration);
      // 本地歌曲：首次获取到真实时长时更新本地库
      final music = _currentMusicController.value;
      if (music != null && (music.source == 'local' || music.source == 'webdav') && duration != null && duration.inMilliseconds > 0) {
        _localMusicService.updateSongDuration(music.id, duration.inMilliseconds);
      }
      // 实际播放时长已知时，更新 MediaItem 以让灵动岛/车机显示进度条
      // music.duration 经常为 0（API 未返回），但实际音频有完整时长
      // 等待 handler 就绪后调用（避免 init 顺序导致早期 updateDuration 失效）
      if (duration != null && duration.inMilliseconds > 0) {
        _applyDurationUpdate(duration);
      }
    }));

    _subscriptions.add(_audioPlayer.playerStateStream.listen((state) {
      _isPlayingController.add(state.playing);

      if (state.processingState == ProcessingState.completed) {
        _addToHistory(currentMusic);
        playNext(isAutoToggle: true);
      } else if (state.processingState == ProcessingState.buffering) {
        _statusTextController.add('缓冲中...');
      } else if (state.processingState == ProcessingState.idle && !state.playing) {
        if (_currentMusicController.value != null && !_isLoadingController.value) {
          // ExoPlayer 因源错误(404)回退到 idle → 自动跳下一首
          logDebug('[Player] 感知到异常 idle，自动跳下一首');
          _statusTextController.add('');
          playNext(isAutoToggle: true);
        }
      }
    }));

    // 初始化系统媒体会话（蓝牙/耳机线控/通知栏控制）
    _initMediaSession();

    // 队列/索引变化时自动持久化（armed 防止订阅时的种子值/恢复值误触发保存）
    _subscriptions.add(_playlistController.listen((_) => _schedulePlaylistSave()));
    _subscriptions.add(_currentIndexController.listen((_) => _schedulePlaylistSave()));

    _loadPlayHistory();
    _loadPlayMode();
    _loadPlayedList();
    _loadPlaylist();
  }

  // ==================== 播放队列持久化 ====================

  // 防止 BehaviorSubject 订阅时的种子值([])在加载完成前覆盖存储
  bool _playlistSaveArmed = false;

  Future<void> _loadPlaylist() async {
    final playlist = await _storage.loadMusicList(PlayerStorage.playlistKey);
    final index = await _storage.loadCurrentIndex();
    _playlistController.add(playlist);
    if (playlist.isNotEmpty && index >= 0 && index < playlist.length) {
      _currentIndexController.add(index);
      // 恢复当前歌曲（不自动播放）
      _currentMusicController.add(playlist[index]);
    }
    // 恢复完成，允许后续变化触发保存
    _playlistSaveArmed = true;
    logDebug('[Playlist] 恢复播放队列: ${playlist.length}首, index=$index');
  }

  /// 立即保存队列（App 切后台/退出时调用）
  /// 注意：加载完成前（_playlistSaveArmed=false）禁止保存，
  /// 否则启动早期 lifecycle 回调会把内存空列表写入存储，覆盖已有歌单！
  Future<void> savePlaylistNow() async {
    if (!_playlistSaveArmed) {
      logDebug('[Playlist] 跳过保存（数据尚未加载完成）');
      return;
    }
    await _savePlaylist();
  }

  Future<void> _savePlaylist() async {
    if (!_playlistSaveArmed) return; // 加载完成前绝不写盘
    await _storage.saveMusicList(PlayerStorage.playlistKey, currentPlaylist);
    await _storage.saveCurrentIndex(currentIndex);
  }

  /// 队列/索引变化时自动保存（防抖：合并300ms内的连续变化）
  void _schedulePlaylistSave() {
    if (!_playlistSaveArmed) return;
    _playlistSaveTimer?.cancel();
    _playlistSaveTimer = Timer(const Duration(milliseconds: 300), () {
      _savePlaylist();
    });
  }

  Future<void> _initMediaSession() async {
    try {
      final handler = await AudioService.init(
        builder: () => AudioPlayerHandler(
          player: _audioPlayer,
          onPlayNext: () => playNext(),
          onPlayPrevious: () => playPrevious(),
        ),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.salt.music.playback',
          androidNotificationChannelName: '音乐播放',
          androidNotificationIcon: 'mipmap/ic_launcher',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
      _mediaHandler = handler;
      handler.setPlayIndexCallback((index) => playIndex(index));
      if (!_mediaSessionReady.isCompleted) _mediaSessionReady.complete();

      // 当前歌曲变化时更新 metadata（队列同步由 combineLatest2 统一处理）
      _subscriptions.add(_currentMusicController.listen((music) {
        _mediaHandler?.updateNowPlaying(music);
      }));
      // 队列变化时同步给车机（HiCar/Jovi InCar 浏览+播放卡片用）
      // 每次切歌都同步队列+当前索引，HiCar 需要正确索引才能显示播放卡片
      _queueSyncTimer = null;
      int lastQueueLen = -1;
      int lastIndex = -1;
      _subscriptions.add(Rx.combineLatest2<List<MusicInfo>, int, (List<MusicInfo>, int)>(
        _playlistController.stream,
        _currentIndexController.stream,
        (playlist, index) => (playlist, index),
      ).listen((record) {
        if (record.$1.isEmpty) return; // 播放器未就绪，跳过
        final listChanged = record.$1.length != lastQueueLen;
        final indexChanged = record.$2 != lastIndex;
        lastQueueLen = record.$1.length;
        lastIndex = record.$2;
        if (!listChanged && !indexChanged) return;
        _queueSyncTimer?.cancel();
        _queueSyncTimer = Timer(const Duration(milliseconds: 300), () {
          if (record.$2 >= 0 && record.$2 < record.$1.length) {
            _mediaHandler?.syncQueueToSystem(record.$1, record.$2);
          }
        });
      }));
      // 播放状态变化时同步系统播放状态
      _subscriptions.add(_audioPlayer.playbackEventStream.listen((_) {
        _mediaHandler?.syncPlaybackState();
      }));
      // 歌词数据到达时解析，用于车机通知栏歌词
      _subscriptions.add(_lyricController.listen((data) {
        _mediaLyricLines = LyricParser.parse(data?['lyric'] ?? '');
        _lastMediaLyricIndex = -2; // 重置，触发更新
      }));
    } catch (e) {
      logDebug('[MediaSession] 初始化失败: $e');
      if (!_mediaSessionReady.isCompleted) _mediaSessionReady.complete();
    }
  }

  /// 等待 handler 就绪后更新 MediaItem.duration
  /// 修复：首次播放时 durationStream 可能在 init 完成前就触发了
  void _applyDurationUpdate(Duration duration) {
    if (_mediaHandler != null) {
      _mediaHandler!.updateDuration(duration);
      return;
    }
    // handler 未就绪，等到就绪后立即调用
    _mediaSessionReady.future.then((_) {
      _mediaHandler?.updateDuration(duration);
    }).catchError((_) {});
  }

  // 车机通知栏歌词
  List<LyricLine> _mediaLyricLines = [];
  int _lastMediaLyricIndex = -2;

  /// 同步当前歌词行到媒体通知（车机显示）
  void _updateMediaLyric(Duration pos) {
    if (_mediaLyricLines.isEmpty) return;
    // handler 未就绪则延迟调用
    if (_mediaHandler == null) {
      _mediaSessionReady.future.then((_) {
        if (_mediaLyricLines.isNotEmpty) {
          _doUpdateMediaLyric(pos);
        }
      }).catchError((_) {});
      return;
    }
    _doUpdateMediaLyric(pos);
  }

  void _doUpdateMediaLyric(Duration pos) {
    // 单调递增：pos 单调推进，idx 也单调推进或不变
    // 但用户可能 seek 后退 → 检测 pos < 当前行起始时间 → 从头搜索
    int start;
    int idx;
    final n = _mediaLyricLines.length;
    if (_lastMediaLyricIndex >= 0 &&
        _lastMediaLyricIndex < n &&
        pos >= _mediaLyricLines[_lastMediaLyricIndex].time) {
      // 正常前进：从上次位置继续
      start = _lastMediaLyricIndex;
      idx = _lastMediaLyricIndex;
    } else {
      // seek 后退或初始化：从头搜索
      start = 0;
      idx = -1;
    }
    while (start < n && pos >= _mediaLyricLines[start].time) {
      idx = start;
      start++;
    }
    if (idx != _lastMediaLyricIndex) {
      _lastMediaLyricIndex = idx;
    }
    final line = idx >= 0 ? _mediaLyricLines[idx].text : null;
    _mediaHandler?.updateLyricLine(line);
  }

  Future<void> _loadPlayHistory() async {
    _playHistoryController.add(await _storage.loadMusicList(PlayerStorage.historyKey));
  }

  Future<void> _savePlayHistory() async {
    await _storage.saveMusicList(PlayerStorage.historyKey, playHistory);
  }

  Future<void> _loadPlayMode() async {
    final index = await _storage.loadPlayModeIndex();
    if (index >= 0 && index < PlayMode.values.length) {
      _playModeController.add(PlayMode.values[index]);
    }
  }

  Future<void> _savePlayMode() async {
    await _storage.savePlayModeIndex(playMode.index);
  }

  Future<void> _loadPlayedList() async {
    _playedListController.add(await _storage.loadMusicList(PlayerStorage.playedKey));
  }

  Future<void> _savePlayedList() async {
    await _storage.saveMusicList(PlayerStorage.playedKey, playedList);
  }

  /// 歌曲播放成功回调（供 UI 层挂载，例如同步最近播放）
  static void Function(MusicInfo music)? onMusicPlayed;

  void _addToHistory(MusicInfo? music) {
    if (music == null) return;

    final history = List<MusicInfo>.from(_playHistoryController.value);
    history.removeWhere((m) => m.id == music.id);
    history.insert(0, music);

    if (history.length > _maxHistorySize) {
      history.removeRange(_maxHistorySize, history.length);
    }

    _playHistoryController.add(history);
    _savePlayHistory();
    // 通知最近播放
    try {
      onMusicPlayed?.call(music);
    } catch (_) {}
  }

  void _addToPlayedList(MusicInfo music) {
    final played = List<MusicInfo>.from(_playedListController.value);
    if (!played.any((m) => m.id == music.id)) {
      played.add(music);
      _playedListController.add(played);
      _savePlayedList();
    }
  }

  void _clearPlayedList() {
    _playedListController.add([]);
    _savePlayedList();
  }

  List<MusicInfo> _filterPlayedList(List<MusicInfo> list, List<MusicInfo> played) {
    if (played.isEmpty) return list;
    
    final filtered = List<MusicInfo>.from(list);
    for (final music in played) {
      filtered.removeWhere((m) => m.id == music.id);
    }
    
    // 如果所有歌曲都已播放过，清空已播放列表，重新开始
    if (filtered.isEmpty && played.isNotEmpty) {
      _clearPlayedList();
      return List<MusicInfo>.from(list);
    }
    
    return filtered;
  }

  MusicInfo? _getNextPlayMusicInfo({bool isManualToggle = false}) {
    // 1. 优先检查稍后播放列表
    if (tempPlaylist.isNotEmpty) {
      return tempPlaylist.first;
    }

    final playlist = currentPlaylist;
    if (playlist.isEmpty || currentIndex < 0) return null;

    // 2. 手动切歌时，非循环模式降级为列表循环
    var effectiveMode = playMode;
    if (isManualToggle) {
      switch (effectiveMode) {
        case PlayMode.list:
        case PlayMode.singleLoop:
        case PlayMode.none:
          effectiveMode = PlayMode.listLoop;
          break;
        default:
          break;
      }
    }

    // 3. 根据播放模式计算下一首
    MusicInfo? nextMusic;
    switch (effectiveMode) {
      case PlayMode.listLoop:
        int nextIndex = currentIndex + 1;
        if (nextIndex >= playlist.length) {
          nextIndex = 0;
        }
        nextMusic = playlist[nextIndex];
        break;
      case PlayMode.random:
        // 随机模式：优先从已播放列表回退
        if (playedList.isNotEmpty) {
          final currentId = currentMusic?.id;
          int playedIndex = playedList.indexWhere((m) => m.id == currentId);
          if (playedIndex >= 0 && playedIndex + 1 < playedList.length) {
            nextMusic = playedList[playedIndex + 1];
          }
        }
        // 没有可回退的歌曲，随机选择
        if (nextMusic == null) {
          final filtered = _filterPlayedList(playlist, playedList);
          if (filtered.isNotEmpty) {
            final randomIndex = _random.nextInt(filtered.length);
            nextMusic = filtered[randomIndex];
          }
        }
        break;
      case PlayMode.singleLoop:
        nextMusic = playlist[currentIndex];
        break;
      case PlayMode.list:
        int nextIndex = currentIndex + 1;
        if (nextIndex >= playlist.length) {
          return null; // 顺序播放到末尾停止
        }
        nextMusic = playlist[nextIndex];
        break;
      case PlayMode.none:
        return null; // 禁用自动切歌
    }

    return nextMusic;
  }

  // ==================== URL 缓存 + 预取 ====================

  // 歌曲URL缓存（LRU，最多30条）：播放成功后缓存，切歌命中直接秒开
  final Map<String, ({String url, DateTime time})> _urlCache = {};
  static const Duration _urlCacheMaxAge = Duration(hours: 2);
  static const String _urlCacheKey = 'url_cache_v1';
  bool _urlCacheLoaded = false;

  /// 从 Hive 恢复 URL 缓存（对齐原版 saveMusicUrl：重启也命中，二次播放秒开）
  Future<void> _loadUrlCacheFromStorage() async {
    if (_urlCacheLoaded) return;
    _urlCacheLoaded = true;
    try {
      final box = await Hive.openBox('player');
      final raw = box.get(_urlCacheKey);
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is Map) {
            final url = v['url']?.toString() ?? '';
            final time = DateTime.tryParse(v['time']?.toString() ?? '');
            if (url.isNotEmpty && time != null) {
              _urlCache[k.toString()] = (url: url, time: time);
            }
          }
        });
        _urlCache.removeWhere((_, e) => DateTime.now().difference(e.time) > _urlCacheMaxAge);
        logDebug('[URLCache] 从磁盘恢复 ${_urlCache.length} 条');
      }
    } catch (e) {
      logDebug('[URLCache] 恢复失败: $e');
    }
  }

  Future<void> _saveUrlCacheToStorage() async {
    try {
      final box = await Hive.openBox('player');
      await box.put(_urlCacheKey, {
        for (final e in _urlCache.entries)
          e.key: {'url': e.value.url, 'time': e.value.time.toIso8601String()},
      });
    } catch (_) {}
  }

  void _putUrlCache(String musicId, String url) {
    _urlCache[musicId] = (url: url, time: DateTime.now());
    if (_urlCache.length > 30) {
      _urlCache.remove(_urlCache.keys.first);
    }
    _saveUrlCacheToStorage();
  }

  // 跨源备选预热缓存：主源取 URL 的同时并行搜索备选，
  // 主源失败时搜索已完成 → 立即进入并行竞速，省掉整段搜索等待
  final Map<String, List<MusicInfo>> _altCandidatesCache = {};
  final Map<String, DateTime> _altCacheTime = {};
  static const Duration _altCacheMaxAge = Duration(minutes: 10);

  String _altCacheKey(MusicInfo music) =>
      '${music.source}|${music.name}|${music.singer}';

  /// fire-and-forget：并行搜索其它源，结果写缓存（供换源时立即使用）
  /// 注意：占位条目不写时间戳（time 为 null = in-flight），完成后才写时间戳
  void _prefetchAltSources(MusicInfo music) {
    final key = _altCacheKey(music);
    if (_altCandidatesCache.containsKey(key)) return;
    // 占位（无时间戳），避免并发重复搜索；完成前 _getAltCandidates 会等待
    _altCandidatesCache[key] = const [];

    // kw 排最后（用户要求）
    const allSources = ['wy', 'kg', 'mg', 'tx', 'kw'];
    final searchSources = allSources
        .where((s) => s != music.source && _urlService.supportsSource(s))
        .toList();

    Future(() async {
      final searchFutures = searchSources.map((source) =>
          _searchService.search(
            keyword: '${music.name} ${music.singer}',
            source: source,
            page: 1,
            pageSize: 5,
          ).timeout(const Duration(seconds: 3), onTimeout: () {
            return SearchResult(list: [], total: 0, page: 1, pageSize: 5, source: source);
          }).catchError((_) => SearchResult(list: [], total: 0, page: 1, pageSize: 5, source: source)));
      final results = await Future.wait(searchFutures);

      // 歌名/歌手匹配过滤（同 _tryAlternativeSource 的标准）
      final matched = <MusicInfo>[];
      for (final result in results) {
        for (final alt in result.list) {
          final nameMatch = alt.name == music.name ||
              alt.name.contains(music.name) ||
              music.name.contains(alt.name);
          final singerMatch = alt.singer == music.singer ||
              alt.singer.contains(music.singer) ||
              music.singer.contains(alt.singer);
          if (!nameMatch && !singerMatch) continue;
          if (matched.any((c) => c.id == alt.id)) continue;
          matched.add(alt);
          if (matched.length >= 4) break;
        }
        if (matched.length >= 4) break;
      }
      _altCandidatesCache[key] = matched;
      _altCacheTime[key] = DateTime.now(); // 写时间戳 = 完成
      logDebug('[AltSource] 备选预热完成: ${matched.length} 个候选 (${music.name})');
    }).catchError((_) {
      // 预热失败也写时间戳（空结果），避免调用方死等
      _altCacheTime[key] = DateTime.now();
    });
  }

  // 异步回调过期守卫：调用方拿到旧的 requestId/lrId 时直接放弃
  bool _isStaleLoad(int requestId) => _loadRequestId != requestId;
  bool _isStaleLyric(int lrId) => _lyricRequestId != lrId;

  /// 取已预热的备选：in-flight 时等待完成（最多 10s）；缓存完成且未过期直接用
  Future<List<MusicInfo>> _getAltCandidates(MusicInfo music, int requestId) async {
    final key = _altCacheKey(music);

    // 有预热且已完成（有时间戳）且未过期 → 直接返回
    if (_altCacheTime[key] != null) {
      final cached = _altCandidatesCache[key];
      final time = _altCacheTime[key]!;
      if (cached != null && cached.isNotEmpty && DateTime.now().difference(time) < _altCacheMaxAge) {
        logDebug('[AltSource] 命中备选预热缓存: ${cached.length} 个候选');
        return cached;
      }
      // 过期或空 → 清理后现搜
      _altCandidatesCache.remove(key);
      _altCacheTime.remove(key);
    }

    // 有 in-flight 预热但还没完成 → 等一下（最多 2s），不重复启动
    if (_altCandidatesCache.containsKey(key)) {
      final started = DateTime.now();
      while (DateTime.now().difference(started) < const Duration(seconds: 2)) {
        await Future.delayed(const Duration(milliseconds: 50));
        if (_isStaleLoad(requestId)) return const [];
        if (_altCacheTime[key] != null) {
          return _altCandidatesCache[key] ?? const [];
        }
      }
      // 2s 内没完成 → 不等了，下面立即现搜
    }

    // 立即搜索（对齐原版：失败后立即搜，不依赖预热）
    logDebug('[AltSource] 立即搜索备选源 (${music.name} - ${music.singer})');
    return _runAltSearch(music, requestId);
  }

  /// 立即搜索备选源（对齐原版 findMusic：并行搜所有源，匹配排序，返回候选）
  Future<List<MusicInfo>> _runAltSearch(MusicInfo music, int requestId) async {
    final key = _altCacheKey(music);
    // 写占位避免并发
    _altCandidatesCache[key] = const [];

    const allSources = ['wy', 'kg', 'mg', 'tx', 'kw'];
    final searchSources = allSources
        .where((s) => s != music.source && _urlService.supportsSource(s))
        .toList();

    try {
      final searchFutures = searchSources.map((source) =>
          _searchService.search(
            keyword: '${music.name} ${music.singer}',
            source: source,
            page: 1,
            pageSize: 5,
          ).timeout(const Duration(seconds: 3), onTimeout: () {
            return SearchResult(list: [], total: 0, page: 1, pageSize: 5, source: source);
          }).catchError((_) => SearchResult(list: [], total: 0, page: 1, pageSize: 5, source: source)));
      final results = await Future.wait(searchFutures);

      if (_isStaleLoad(requestId)) return const [];

      final matched = <MusicInfo>[];
      for (final result in results) {
        for (final alt in result.list) {
          final nameMatch = alt.name == music.name ||
              alt.name.contains(music.name) ||
              music.name.contains(alt.name);
          final singerMatch = alt.singer == music.singer ||
              alt.singer.contains(music.singer) ||
              music.singer.contains(alt.singer);
          if (!nameMatch && !singerMatch) continue;
          if (matched.any((c) => c.id == alt.id)) continue;
          matched.add(alt);
          if (matched.length >= 4) break;
        }
        if (matched.length >= 4) break;
      }
      _altCandidatesCache[key] = matched;
      _altCacheTime[key] = DateTime.now();
      logDebug('[AltSource] 搜索完成: ${matched.length} 个候选 (${music.name})');
      return matched;
    } catch (_) {
      _altCacheTime[key] = DateTime.now();
      return const [];
    }
  }

  String? _getCachedUrl(String musicId) {
    final entry = _urlCache[musicId];
    if (entry == null) return null;
    // 过期检查（链接通常有时效）
    if (DateTime.now().difference(entry.time) > _urlCacheMaxAge) {
      _urlCache.remove(musicId);
      return null;
    }
    return entry.url;
  }

  /// 后台预取下一首的播放地址（切歌时命中缓存秒开）
  /// 走并行通道（临时 JS 运行时），不与用户切歌争抢 JS 锁
  void _prefetchNextUrl(MusicInfo current) {
    final next = _getNextPlayMusicInfo(isManualToggle: false);
    if (next == null || next.source == 'local' || next.source == 'webdav') return;
    if (_urlCache.containsKey(next.id)) return;
    // 延迟2秒执行，避开主播放请求的高峰
    Future.delayed(const Duration(seconds: 2), () async {
      try {
        if (_urlCache.containsKey(next.id)) return;
        final apiId = _urlService.currentScript?.id;
        if (apiId == null) return;
        final url = await _urlService.getMusicUrlParallel(music: next, quality: _preferredQuality);
        if (url != null && url.isNotEmpty) {
          _putUrlCache(next.id, url);
          logDebug('[URLCache] 预取成功: ${next.name}');
        }
      } catch (_) {}
    });
  }

  Future<void> playMusic(MusicInfo music, {bool isManualToggle = false}) async {
    // 等待 MediaSession 初始化完成（Android 音频会话必须就绪才能播放）
    try { await _mediaSessionReady.future.timeout(Duration(seconds: 5)); } catch (_) {}
    await _loadUrlCacheFromStorage();
    _loadRequestId++;
    _lyricRequestId++;
    final requestId = _loadRequestId;
    
    // 先标记 loading（必须在 stop() 之前，防止 idle 误触发自动跳歌）
    _isLoadingController.add(true);
    try { await _audioPlayer.stop(); } catch (_) {}
    _cancelLoadTimeout();
    _retryTimer?.cancel();
    
    _statusTextController.add('获取链接中...');
    _retryCount = 0;
    _lyricController.add(null);
    _currentMusicController.add(music);

    try {
      await _fetchAndPlay(music, requestId);
    } catch (e) {
      if (_loadRequestId == requestId) {
        _statusTextController.add('播放失败: $e');
        _isLoadingController.add(false);
      }
    }
  }

  Future<void> _fetchAndPlay(MusicInfo music, int requestId) async {
    _startLoadTimeout();

    try {
      String? url;

      // 本地音乐/WebDAV 直接使用本地路径或 HTTP URL
      if (music.source == 'local' || music.source == 'webdav') {
        url = music.songUrl;
      } else {
        // 始终并行获取歌词（不依赖URL缓存）
        _fetchLyricParallel(music);
        // 并行补全封面图（自定义源搜索结果可能缺少 imgUrl）
        if (music.imgUrl == null || music.imgUrl!.isEmpty) {
          _fetchCoverParallel(music);
        }
        // 优先命中 URL 缓存（命中则跳过预热，省 CPU/带宽；未命中才预热）
        url = _getCachedUrl(music.id);
        if (url == null) {
          // 并行预热跨源备选（主源失败后无需再等搜索）
          _prefetchAltSources(music);
          url = await _urlService.getMusicUrl(music: music, quality: _preferredQuality);
        } else {
          logDebug('[URLCache] 命中缓存: ${music.name}');
        }
      }

      // 检查请求是否已被取消
      if (_isStaleLoad(requestId)) {
        print('[Player] STALE at 787, requestId=$requestId current=$_loadRequestId');
        return;
      }
      print('[Player] AFTER_STALE_787, url=$url');

      if (url == null || url.isEmpty) {
        print('[Player] URL_NULL_OR_EMPTY, url=$url');
        // 未激活自定义源时直接抛出，不重试（重试无意义）
        if (!_urlService.isUserApiActive) {
          throw Exception('NO_SCRIPT');
        }
        // 脚本不支持该音源 → 直接尝试其他音源（重试同源无意义）
        if (!_urlService.supportsSource(music.source ?? 'kw')) {
          _statusTextController.add('${music.source ?? ''} 源不支持，尝试其他源...');
          await _tryAlternativeSource(music, requestId);
          return;
        }
        throw Exception('获取播放地址失败');
      }

      _cancelLoadTimeout();
      debugPrint('[Player] 进入播放前, url=$url');

      final musicWithUrl = music.copyWith(songUrl: url);

      final playlist = _playlistController.value;
      final index = playlist.indexWhere((m) => m.id == music.id);

      // 仅当歌曲不在队列时追加（避免每次播放都重发整个队列：
      // 否则会触发首页全量重建 + 车机队列同步 + Hive 全量写盘，列表越长越卡）
      if (index < 0) {
        final newPlaylist = List<MusicInfo>.from(playlist)..add(musicWithUrl);
        _playlistController.add(newPlaylist);
      }

      _currentMusicController.add(musicWithUrl);
      _currentIndexController.add(index >= 0 ? index : _playlistController.value.length - 1);

      // 如果是随机模式，将当前歌曲加入已播放列表
      if (playMode == PlayMode.random) {
        _addToPlayedList(musicWithUrl);
      }

      // 从稍后播放列表中移除
      if (tempPlaylist.isNotEmpty && tempPlaylist.first.id == music.id) {
        final newTemp = List<MusicInfo>.from(tempPlaylist)..removeAt(0);
        _tempPlaylistController.add(newTemp);
      }

      // 再次检查请求是否已被取消
      if (_isStaleLoad(requestId)) {
        debugPrint('[Player] STALE at 836, requestId=$requestId current=$_loadRequestId');
        return;
      }

      debugPrint('[Player] 准备 setUrl: $url');
      await _audioPlayer.setUrl(url).timeout(const Duration(seconds: 30), onTimeout: () {
        logDebug('[Player] setUrl 超时 30s');
        throw TimeoutException('SETURL_TIMEOUT');
      });
      debugPrint('[Player] setUrl 完成');
      if (_isStaleLoad(requestId)) return;
      debugPrint('[Player] 调 play()');
      _audioPlayer.play().catchError((e) {
        logDebug('[Player] play() 失败: $e，尝试 seek(0) + 重播');
        try {
          _audioPlayer.seek(Duration.zero).then((_) => _audioPlayer.play());
        } catch (_) {}
      });
      debugPrint('[Player] play() 已调');

      _addToHistory(musicWithUrl);
      _isLoadingController.add(false);
      _statusTextController.add('');

      // 防御性重试：如果 1 秒后仍未播放，尝试 seek(0) + 重播
      Future.delayed(const Duration(seconds: 1), () {
        if (_isStaleLoad(requestId)) return;
        if (!_isPlayingController.value &&
            _currentMusicController.value?.id == musicWithUrl.id) {
          logDebug('[Player] 1秒后未播放，尝试重新 seek + play');
          try {
            _audioPlayer.seek(Duration.zero).then((_) {
              if (_loadRequestId == requestId) {
                _audioPlayer.play();
              }
            });
          } catch (e) {
            logDebug('[Player] 重试播放失败: $e');
          }
        }
      });

      // 写入 URL 缓存（来回切歌/重播时秒开）
      _putUrlCache(musicWithUrl.id, url);
      if (_urlCache.length > 30) {
        _urlCache.remove(_urlCache.keys.first);
      }

      // 预取下一首 URL（歌词已在URL获取前并行启动）
      _prefetchNextUrl(musicWithUrl);
    } catch (e) {
      _cancelLoadTimeout();
      
      // 只有当请求仍然有效时才处理错误
      if (_isStaleLoad(requestId)) return;
      
      // 未激活自定义源，不重试，直接提示
      if (e.toString().contains('NO_SCRIPT')) {
        _isLoadingController.add(false);
        final hasScript = _urlService.currentScript != null;
        _statusTextController.add(hasScript
            ? '脚本初始化失败，请在自定义源页面重新激活'
            : '请先导入自定义源脚本');
        return;
      }

      // 脚本明确错误：全局错误（IP封禁/限流/签名失败）重试无意义直接提示；
      // 单歌错误（如转链失败）值得跨源换源恢复
      if (e is MusicUrlException) {
        if (!e.retryable) {
          _isLoadingController.add(false);
          _statusTextController.add('获取失败: $e');
          return;
        }
        _statusTextController.add('${music.source} 源转链失败，尝试其他源...');
        await _tryAlternativeSource(music, requestId);
        return;
      }
      
      if (e is TimeoutException || e.toString().contains('TimeoutException')) {
        // JS 锁/网络超时：直接换源（备选已预热，重试大概率同样超时）
        _statusTextController.add('${music.source} 源超时，尝试其他源...');
        await _tryAlternativeSource(music, requestId);
        return;
      }

      // 单次快速重试：脚本偶发网络抖动可能自愈；备选已预热，不在此浪费多次等待
      if (_retryCount < 1) {
        _retryCount++;
        _statusTextController.add('重试中 ($_retryCount/1)...');
        _retryTimer = Timer(const Duration(milliseconds: 500), () {
          if (_loadRequestId == requestId) {
            _fetchAndPlay(music, requestId);
          }
        });
      } else {
        _statusTextController.add('播放失败，尝试其他源...');
        _tryAlternativeSource(music, requestId);
      }
    }
  }

  /// 异步获取歌词
  Future<void> _fetchLyric(MusicInfo music) async {
    try {
      final lrId = _lyricRequestId;

      // 本地歌曲：先读同名 .lrc 文件，无则在线搜索兜底
      if (music.source == 'local') {
        final lyricData = await _localMusicService.getLocalLyric(music);
        if (_isStaleLyric(lrId)) return;
        if (lyricData != null && lyricData['lyric'] != null && lyricData['lyric']!.isNotEmpty) {
          logDebug('[Lyric] 本地歌词成功: ${music.name}');
          _lyricController.add(lyricData);
        } else {
          // 无本地 .lrc → 尝试在线搜索
          logDebug('[Lyric] 本地无歌词文件，在线搜索: ${music.name} - ${music.singer}');
          try {
            final onlineLyric = await _lyricApiService
                .searchLyricByKeyword(music.name, music.singer)
                .timeout(const Duration(seconds: 10));
            if (_isStaleLyric(lrId)) return;
            if (onlineLyric != null && onlineLyric['lyric'] != null && onlineLyric['lyric']!.isNotEmpty) {
              logDebug('[Lyric] 本地歌曲在线歌词成功');
              _lyricController.add(onlineLyric);
            } else {
              logDebug('[Lyric] 本地歌曲在线搜索无结果');
              _lyricController.add(null);
            }
          } catch (e) {
            logDebug('[Lyric] 本地歌曲在线歌词失败: $e');
            _lyricController.add(null);
          }
        }
        return;
      }

      logDebug('[Lyric] 开始获取歌词: ${music.name} - ${music.singer} (source=${music.source}, songId=${music.songId})');

      // 内置API优先获取歌词
      Map<String, String?>? lyricData;
      try {
        lyricData = await _lyricApiService
            .getLyric(music)
            .timeout(const Duration(seconds: 15));

        if (lyricData != null && lyricData['lyric'] != null && lyricData['lyric']!.isNotEmpty) {
          logDebug('[Lyric] 内置API歌词成功');
          if (_isStaleLyric(lrId)) return;
          _lyricController.add(lyricData);
          return;
        }
      } catch (e) {
        logDebug('[Lyric] 内置API歌词失败: $e');
      }

      // 内置API无歌词 → 回退用户源
      if (_urlService.isUserApiActive) {
        try {
          logDebug('[Lyric] 内置API无歌词，尝试用户源');
          lyricData = await _urlService.getLyric(music: music);
          if (lyricData != null && lyricData['lyric'] != null && lyricData['lyric']!.isNotEmpty) {
            logDebug('[Lyric] 用户源歌词成功');
            if (_isStaleLyric(lrId)) return;
            _lyricController.add(lyricData);
            return;
          }
        } catch (e) {
          logDebug('[Lyric] 用户源歌词失败: $e');
        }
      }

      _lyricController.add(lyricData);
    } catch (e) {
      logDebug('[Lyric] 获取歌词失败: $e');
      _lyricController.add(null);
    }
  }

  /// 公开重新拉取当前歌歌词（车机小窗/卡片进入时主动补拉， lyricProvider 已有值则不变）
  void refetchLyric() {
    final music = _currentMusicController.value;
    if (music == null) return;
    _lyricRequestId++;
    _fetchLyricParallel(music);
  }

  /// 并行获取歌词（不阻塞播放，结果异步写入控制器）
  void _fetchLyricParallel(MusicInfo music) {
    final lrId = _lyricRequestId;
    _fetchLyric(music).then((_) {
      // 歌词到达时检查是否已被新请求取代
      if (_isStaleLyric(lrId)) return;
    }).catchError((_) {});
  }

  /// 并行补全封面图（自定义源可能缺少 imgUrl）
  void _fetchCoverParallel(MusicInfo music) {
    final reqId = _loadRequestId;
    _fetchCoverUrl(music).then((imgUrl) {
      if (_loadRequestId != reqId) return;
      if (imgUrl == null || imgUrl.isEmpty) return;
      // 更新当前歌曲的封面
      final current = _currentMusicController.value;
      if (current != null && current.id == music.id && (current.imgUrl == null || current.imgUrl!.isEmpty)) {
        _currentMusicController.add(current.copyWith(imgUrl: imgUrl));
        // 同步更新播放列表中的封面
        final playlist = _playlistController.value;
        final idx = playlist.indexWhere((m) => m.id == music.id);
        if (idx >= 0) {
          final updated = List<MusicInfo>.from(playlist);
          updated[idx] = updated[idx].copyWith(imgUrl: imgUrl);
          _playlistController.add(updated);
        }
        logDebug('[Cover] 封面补全: $imgUrl');
      }
    }).catchError((_) {});
  }

  /// 获取歌曲封面 URL（按优先级尝试多种API）
  Future<String?> _fetchCoverUrl(MusicInfo music) async {
    try {
      // 酷狗：通过 songId 获取
      if (music.source == 'kg' && (music.songId?.isNotEmpty ?? false)) {
        return await _getKgCover(music);
      }
      // 酷我：通过 musicId 获取
      if (music.source == 'kw' && ((music.songId?.isNotEmpty ?? false) || music.id.isNotEmpty)) {
        return await _getKwCover(music);
      }
      // 通用：通过歌词API的返回中可能包含封面
    } catch (e) {
      logDebug('[Cover] 获取封面失败: $e');
    }
    return null;
  }

  Future<String?> _getKgCover(MusicInfo music) async {
    try {
      final url = Uri.parse(
        'https://wwwapi.kugou.com/yy/index.php?r=play/getdata'
        '&hash=${music.songId}&dfid=&mid=0&platid=4&_= ${DateTime.now().millisecondsSinceEpoch}',
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        'Cookie': 'kg_mid=0',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final img = data['data']?['img']?.toString();
        if (img != null && img.isNotEmpty && img.startsWith('http')) return img;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _getKwCover(MusicInfo music) async {
    try {
      final musicId = (music.songId?.isNotEmpty ?? false) ? music.songId! : music.id;
      final url = Uri.parse('https://m.kuwo.cn/newh5/singles/songinfoandlrc?musicId=$musicId');
      final response = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)',
        'Referer': 'https://m.kuwo.cn/',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final img = data['data']?['pic']?.toString();
        if (img != null && img.isNotEmpty && img.startsWith('http')) return img;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _tryAlternativeSource(MusicInfo music, int requestId) async {
    try {
      // kw 排最后（用户要求）
      const allSources = ['tx', 'wy', 'kg', 'mg', 'git', 'kw'];
      final supportedSources = allSources
          .where((s) => _urlService.supportsSource(s))
          .toList();

      logDebug('[AltSource] 当前源=${music.source}, 可用音源=$supportedSources');

      if (supportedSources.where((s) => s != music.source).isEmpty) {
        _isLoadingController.add(false);
        _statusTextController.add(supportedSources.isEmpty
            ? '未注册任何音源，请在自定义源页面激活脚本'
            : '仅支持 ${supportedSources.join(", ")}，无法切换到其他源');
        return;
      }

      // 取备选（预热命中则 0 等待；否则最多等 10s 现搜）
      final candidates = await _getAltCandidates(music, requestId);

      if (_isStaleLoad(requestId)) return;

      if (candidates.isEmpty) {
        _isLoadingController.add(false);
        _statusTextController.add('其他源未找到匹配歌曲');
        logDebug('[AltSource] 备选候选为空');
        return;
      }

      // 逐个尝试（最多 4 个备选）—— 并行竞速：
      // 所有候选同时用独立临时 JS 运行时取 URL（互不抢 JS 锁），
      // 谁先返回有效 URL 就用谁 —— 换源耗时 ≈ 最快候选，而非串行累加
      String? fatalMsg;
      MusicInfo? winnerMusic;
      String? winnerUrl;
      try {
        await Future.wait(candidates.map((alternative) async {
          if (winnerMusic != null) return; // 已有胜者，放弃后续
          try {
            final url = await _urlService.getMusicUrlParallel(
              music: alternative,
              quality: _preferredQuality,
            );
            if (_isStaleLoad(requestId)) return;
            if (url != null && url.isNotEmpty && winnerMusic == null) {
              winnerMusic = alternative;
              winnerUrl = url;
            }
          } on MusicUrlException catch (e) {
            // 全局错误（封禁/限流）换源同样失败，记录后整体终止
            fatalMsg ??= e.message;
          } catch (_) {}
        })).timeout(const Duration(seconds: 20), onTimeout: () {
          logDebug('[AltSource] Future.wait 超时 20s');
          return [];
        });
      } catch (_) {}

      if (_isStaleLoad(requestId)) return;

      final altMusic = winnerMusic;
      final altUrl = winnerUrl;
      if (altMusic != null && altUrl != null) {
        final alternativeWithUrl = altMusic.copyWith(songUrl: altUrl);
        final playlist = _playlistController.value;
        final index = playlist.indexWhere((m) => m.id == music.id);
        if (index < 0) {
          final newPlaylist = List<MusicInfo>.from(playlist)..add(alternativeWithUrl);
          _playlistController.add(newPlaylist);
        }

        _currentMusicController.add(alternativeWithUrl);
        await _audioPlayer.setUrl(altUrl).timeout(const Duration(seconds: 30), onTimeout: () {
          logDebug('[Player] alt setUrl 超时 30s');
          throw TimeoutException('SETURL_TIMEOUT');
        });
        if (_isStaleLoad(requestId)) return;
        _audioPlayer.play();

        _addToHistory(alternativeWithUrl);
        _putUrlCache(alternativeWithUrl.id, altUrl);
        _qualityController.add(_urlService.lastUsedQuality ?? '');
        _isLoadingController.add(false);
        _statusTextController.add('');
        _fetchLyricParallel(alternativeWithUrl);
        return;
      }

      _isLoadingController.add(false);
      if (fatalMsg != null) {
        _statusTextController.add('获取失败: $fatalMsg');
      } else {
        _statusTextController.add('所有源均无法播放');
      }
      logDebug('[AltSource] 所有备选源均无法获取播放地址');
    } catch (e) {
      if (_loadRequestId == requestId) {
        _isLoadingController.add(false);
        _statusTextController.add('播放失败');
      }
    }
  }

  void _startLoadTimeout() {
    _cancelLoadTimeout();
    _loadTimeoutTimer = Timer(_loadTimeout, () {
      if (_currentMusicController.value != null) {
        _statusTextController.add('加载超时');
        playNext(isAutoToggle: true);
      }
    });
  }

  void _cancelLoadTimeout() {
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = null;
  }

  Future<void> setPlaylist(List<MusicInfo> songs, {int startIndex = 0}) async {
    _playlistController.add(songs);
    _tempPlaylistController.add([]);
    _clearPlayedList();
    if (songs.isNotEmpty && startIndex >= 0 && startIndex < songs.length) {
      await playMusic(songs[startIndex]);
    }
  }

  /// 添加单首到播放队列末尾
  void addToQueue(MusicInfo song) {
    final current = List<MusicInfo>.from(currentPlaylist);
    current.add(song);
    _playlistController.add(current);
  }

  /// 添加到播放队列并立即播放
  Future<void> addToPlaylist(MusicInfo song) async {
    final current = List<MusicInfo>.from(currentPlaylist);
    current.add(song);
    _playlistController.add(current);
    await playMusic(song);
  }

  Future<void> playIndex(int index, {bool isManualToggle = false}) async {
    final playlist = currentPlaylist;
    if (index < 0 || index >= playlist.length) return;
    await playMusic(playlist[index], isManualToggle: isManualToggle);
  }

  Future<void> play() async {
    final music = currentMusic;
    if (music == null) return;

    if (_audioPlayer.audioSource == null) {
      await playMusic(music);
      return;
    }

    try {
      await _audioPlayer.play();
    } catch (e) {
      logDebug('[Player] play() 异常，尝试重新加载: $e');
      await playMusic(music);
    }
  }

  Future<void> pause() async {
    await _audioPlayer.pause();
  }

  Future<void> stop() async {
    _cancelLoadTimeout();
    _retryTimer?.cancel();
    _isLoadingController.add(true);
    await _audioPlayer.stop();
    _statusTextController.add('');
    _isLoadingController.add(false);
  }

  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
  }

  /// 清空播放列表并停止播放
  Future<void> clearPlaylist() async {
    _cancelLoadTimeout();
    _retryTimer?.cancel();
    _isLoadingController.add(true);
    await _audioPlayer.stop();
    _playlistController.add([]);
    _currentMusicController.add(null);
    _currentIndexController.add(-1);
    _lyricController.add(null);
    _isLoadingController.add(false);
    _statusTextController.add('');
  }

  Future<void> playNext({bool isAutoToggle = false}) async {
    final nextMusic = _getNextPlayMusicInfo(isManualToggle: !isAutoToggle);
    
    if (nextMusic == null) {
      if (isAutoToggle) {
        // 自动切歌时，根据模式决定是否停止
        if (playMode == PlayMode.list || playMode == PlayMode.none) {
          await stop();
        }
      }
      return;
    }

    // 如果是稍后播放列表的歌曲，移除后再播放
    if (tempPlaylist.isNotEmpty && tempPlaylist.first.id == nextMusic.id) {
      final newTemp = List<MusicInfo>.from(tempPlaylist)..removeAt(0);
      _tempPlaylistController.add(newTemp);
    }

    await playMusic(nextMusic);
  }

  Future<void> playPrevious() async {
    final playlist = currentPlaylist;
    if (playlist.isEmpty) return;

    // 优先从已播放列表回退
    if (playedList.isNotEmpty && playMode == PlayMode.random) {
      final currentId = currentMusic?.id;
      int playedIndex = playedList.indexWhere((m) => m.id == currentId);
      if (playedIndex > 0) {
        final prevMusic = playedList[playedIndex - 1];
        await playMusic(prevMusic);
        return;
      }
    }

    int prevIndex;
    switch (playMode) {
      case PlayMode.random:
        prevIndex = _random.nextInt(playlist.length);
        break;
      case PlayMode.singleLoop:
        prevIndex = currentIndex;
        break;
      case PlayMode.list:
        prevIndex = currentIndex - 1;
        if (prevIndex < 0) {
          prevIndex = 0;
        }
        break;
      case PlayMode.listLoop:
      default:
        prevIndex = currentIndex - 1;
        if (prevIndex < 0) {
          prevIndex = playlist.length - 1;
        }
        break;
    }
    await playIndex(prevIndex, isManualToggle: true);
  }

  Future<void> togglePlayMode() async {
    final modes = PlayMode.values;
    final nextIndex = (playMode.index + 1) % modes.length;
    final newMode = modes[nextIndex];
    
    _playModeController.add(newMode);
    
    // 切换模式时清空已播放列表
    if (playedList.isNotEmpty) {
      _clearPlayedList();
    }
    
    // 如果切换到随机模式，将当前歌曲加入已播放列表
    if (newMode == PlayMode.random && currentMusic != null) {
      _addToPlayedList(currentMusic!);
    }
    
    await _savePlayMode();
  }

  Future<void> setPlayMode(PlayMode mode) async {
    _playModeController.add(mode);
    
    if (playedList.isNotEmpty) {
      _clearPlayedList();
    }
    
    if (mode == PlayMode.random && currentMusic != null) {
      _addToPlayedList(currentMusic!);
    }
    
    await _savePlayMode();
  }

  Future<void> addToTempPlaylist(List<MusicInfo> songs, {bool isTop = false}) async {
    final current = List<MusicInfo>.from(_tempPlaylistController.value);
    if (isTop) {
      current.insertAll(0, songs);
    } else {
      current.addAll(songs);
    }
    _tempPlaylistController.add(current);
  }

  Future<void> removeFromTempPlaylist(int index) async {
    final current = List<MusicInfo>.from(_tempPlaylistController.value);
    if (index >= 0 && index < current.length) {
      current.removeAt(index);
      _tempPlaylistController.add(current);
    }
  }

  Future<void> clearTempPlaylist() async {
    _tempPlaylistController.add([]);
  }

  Future<void> clearPlayHistory() async {
    _playHistoryController.add([]);
    await _savePlayHistory();
  }

  Future<void> removeFromHistory(String musicId) async {
    final history = List<MusicInfo>.from(_playHistoryController.value);
    history.removeWhere((m) => m.id == musicId);
    _playHistoryController.add(history);
    await _savePlayHistory();
  }

  Future<void> startSleepTimer(Duration duration) async {
    cancelSleepTimer();
    
    _isSleepTimerActiveController.add(true);
    _sleepTimerRemainingController.add(duration);
    
    _sleepTimerTickTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = _sleepTimerRemainingController.value;
      if (remaining != null && remaining.inSeconds > 0) {
        _sleepTimerRemainingController.add(remaining - const Duration(seconds: 1));
      } else {
        cancelSleepTimer();
      }
    });
    
    _sleepTimer = Timer(duration, () async {
      await pause();
      cancelSleepTimer();
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimerTickTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerTickTimer = null;
    _isSleepTimerActiveController.add(false);
    _sleepTimerRemainingController.add(null);
  }

  String getPlayModeText() {
    switch (playMode) {
      case PlayMode.listLoop:
        return '列表循环';
      case PlayMode.random:
        return '随机播放';
      case PlayMode.singleLoop:
        return '单曲循环';
      case PlayMode.list:
        return '顺序播放';
      case PlayMode.none:
        return '禁用自动切歌';
    }
  }
}
