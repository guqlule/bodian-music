import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../core/utils/logger.dart';
import 'package:flutter/services.dart';
import 'dart:ui' show AppExitResponse, PlatformDispatcher;
import 'core/theme/app_theme.dart';
import 'core/storage/storage_service.dart';
import 'core/storage/hive_adapters.dart';
import 'core/router/app_router.dart';

import 'services/api/user_api_service.dart';
import 'services/player/player_service.dart';
import 'services/sync/sync_service.dart';
import 'models/playlist_model.dart';
import 'models/music_model.dart';
import 'providers/app_providers.dart';
import 'providers/settings_provider.dart';

void main() async {
  // 全局错误处理器：捕获 just_audio 等插件抛出的未捕获 PlatformException，
  // 防止连续播放失败时异常未处理导致 App 崩溃退出
  PlatformDispatcher.instance.onError = (error, stack) {
    logDebug('[Global] 未捕获异常: $error');
    return true;
  };
  FlutterError.onError = (details) {
    logDebug('[Flutter] 框架异常: ${details.exception}');
  };
  runZonedGuarded(() async {
    await _startApp();
  }, (error, stack) {
    logDebug('[Zone] 异常: $error');
  });
}

Future<void> _startApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 全局图片缓存配置：减少内存占用（音乐播放器封面图较多）
  PaintingBinding.instance.imageCache.maximumSize = 200;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20; // 50MB

  // 设置系统UI样式（深色模式状态由 build 中随设置更新）
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  // Register Hive adapters
  HiveAdapters.registerAdapters();

  // Initialize storage
  await StorageService().init();

  // Pre-initialize UserApiService so it's ready when player needs it
  // （仅加载脚本列表，很快；脚本激活（JS引擎初始化轮询最多10秒）延后到首帧后，
  //   避免阻塞冷启动白屏）
  await UserApiService().init();

  runApp(ProviderScope(
    child: LxMusicApp(),
  ));
}

class LxMusicApp extends ConsumerStatefulWidget {
  const LxMusicApp({super.key});

  @override
  ConsumerState<LxMusicApp> createState() => _LxMusicAppState();
}

class _LxMusicAppState extends ConsumerState<LxMusicApp> {
  AppLifecycleListener? _lifecycle;
  Timer? _persistFallbackTimer;
  StreamSubscription<List<Map<String, dynamic>>>? _remoteListsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _remoteHistorySub;
  /// 标记：本次歌单/历史变化来自远端拉取合并，跳过回推（防 push/pull 死循环）
  bool _mergingRemote = false;

  /// 歌单/不喜欢/播放历史变化时推送到同步服务器（仅在已连接且开启同步时）
  void _tryPushSync() {
    try {
      if (_mergingRemote) return; // 远端合并触发的变化不回推
      final settings = ref.read(settingsProvider);
      if (!settings.enableSync) return;
      final svc = SyncService();
      if (!svc.isConnected) return;
      unawaited(svc.syncLists(ref.read(playlistProvider)));
      unawaited(svc.syncDislikeList(ref.read(dislikeListProvider)));
      unawaited(svc.syncHistory(ref.read(playHistoryProvider).valueOrNull ?? []));
    } catch (_) {}
  }

  /// 服务器下发远端播放历史 → 合并进本地（按 id 去重，远端新条目置顶保留）
  void _mergeRemoteHistory(List<Map<String, dynamic>> remote) {
    if (remote.isEmpty) return;
    final local = ref.read(playHistoryProvider).valueOrNull ?? [];
    final localIds = local.map((m) => m.id).toSet();
    final remoteSongs = <MusicInfo>[];
    for (final raw in remote) {
      try {
        final m = MusicInfo.fromJson(Map<String, dynamic>.from(raw));
        if (m.id.isNotEmpty && !localIds.contains(m.id)) remoteSongs.add(m);
      } catch (_) {}
    }
    if (remoteSongs.isEmpty) return;
    _mergingRemote = true;
    try {
      final merged = [...remoteSongs, ...local];
      unawaited(PlayerService.instance.importHistory(merged));
    } finally {
      Future.delayed(Duration.zero, () => _mergingRemote = false);
    }
  }

  /// 服务器下发远端歌单 → 合并进本地（远端 id 不存在则新增，updateTime 更新则覆盖）
  void _mergeRemoteLists(List<Map<String, dynamic>> remote) {
    if (remote.isEmpty) return;
    final local = ref.read(playlistProvider);
    final localById = {for (final p in local) p.id: p};
    _mergingRemote = true;
    try {
      final notifier = ref.read(playlistProvider.notifier);
      for (final raw in remote) {
        try {
          final remotePl = PlaylistInfo.fromJson(raw);
          if (remotePl.id.isEmpty) continue;
          final exists = localById[remotePl.id];
          if (exists == null) {
            notifier.addPlaylist(remotePl);
          } else if (remotePl.updateTime.isAfter(exists.updateTime)) {
            notifier.updatePlaylist(remotePl);
          }
        } catch (_) {}
      }
    } finally {
      // 给 ref.listen 一个宏任务间隙，让其读到的是合并后的最终值
      Future.delayed(Duration.zero, () => _mergingRemote = false);
    }
  }

  void _persistPlaylist() {
    try {
      PlayerService.instance.savePlaylistNow();
    } catch (_) {}
  }

  /// 首帧后激活持久化的自定义源脚本
  Future<void> _activatePersistedScript() async {
    final persistedId = UserApiService().getPersistedActiveScriptId();
    if (persistedId != null && UserApiService().getScript(persistedId) != null) {
      try {
        await UserApiService().activateScript(persistedId);
        logDebug('[Init] 自定义源激活成功: $persistedId');
      } catch (e) {
        logDebug('[Init] 自定义源激活失败: $e');
      }
    } else {
      logDebug('[Init] 无已激活的自定义源脚本');
    }
  }

  /// 启动时若配置了同步服务器且开启同步，自动连接
  void _tryConnectSync(AppSettings settings) {
    if (!settings.enableSync || settings.syncHost.isEmpty || settings.syncCode.isEmpty) return;
    try {
      SyncService().connect(host: settings.syncHost, syncCode: settings.syncCode);
      logDebug('[Init] 同步服务自动连接: ${settings.syncHost}');
    } catch (e) {
      logDebug('[Init] 同步连接失败: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    // 播放成功 → 同步最近播放
    PlayerService.onMusicPlayed = (music) {
      try {
        ref.read(recentPlayedProvider.notifier).addRecent(music);
      } catch (_) {}
    };
    // 歌单/不喜欢的列表变化时，推送到同步服务器（用 ref.listen 在 build 中触发）
    // 服务器下发远端歌单/播放历史 → 合并进本地（双向同步的拉取半边）
    _remoteListsSub = SyncService().remoteListsStream.listen(_mergeRemoteLists);
    _remoteHistorySub = SyncService().remoteHistoryStream.listen(_mergeRemoteHistory);
    // 首帧后激活自定义源脚本（JS引擎初始化耗时，不阻塞冷启动首屏）+ 同步音质设置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _activatePersistedScript();
        // 音质设置同步到播放服务
        final quality = ref.read(settingsProvider).quality;
        PlayerService.instance.setPreferredQuality(quality);
        PlayerService.instance.setPrefetchEnabled(ref.read(settingsProvider).gaplessPlayback);
        // 启动时若配置了同步服务器且开启同步，自动连接
        _tryConnectSync(ref.read(settingsProvider));
      } catch (e) {
        logDebug('[Init] 初始化流程异常: $e');
      }
    });
    // 切后台/隐藏/退出时立即持久化播放队列（覆盖各种退出路径）
    _lifecycle = AppLifecycleListener(
      onPause: _persistPlaylist,
      onHide: _persistPlaylist,
      onDetach: _persistPlaylist,
      onResume: () {
        // 后台 → 前台：audio_session 已恢复。
        // 如果之前在播放（wasPlaying），调 play() 唤醒 ExoPlayer，
        // 让 positionStream 重新发射，MiniKtvLyricBar 的 ticker 才会算出正确位置。
        logDebug('[Lifecycle] onResume 触发');
        try {
          final player = PlayerService.instance;
          final music = player.currentMusic;
          logDebug('[Lifecycle] onResume currentMusic=$music isPlaying=${player.isPlaying}');
          if (music != null && !player.isPlaying) {
            logDebug('[Lifecycle] onResume 调 play()');
            player.audioPlayer.play();
          }
        } catch (e) {
          logDebug('[Lifecycle] onResume 异常: $e');
        }
      },
      onExitRequested: () async {
        _persistPlaylist();
        return AppExitResponse.exit;
      },
    );
    // App 启动后 30 秒再兜底保存一次（确保初始状态也已写入）
    _persistFallbackTimer = Timer(const Duration(seconds: 30), _persistPlaylist);
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _persistFallbackTimer?.cancel();
    _remoteListsSub?.cancel();
    _remoteHistorySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 主题/字体跟随设置（深色模式开关实时生效）
    final settings = ref.watch(settingsProvider);
    // 全局色板门控：在 MaterialApp 构建前显式设置（不能依赖 _build 副作用——
    // MaterialApp 求值 light/dark 主题的顺序不定，会把 isDark 残留为 true）
    AppColors.isDark = settings.isDarkMode;
    // Key 绑定主题模式：切换深浅色时强制整树重建
      // 歌单 / 不喜欢列表 / 播放历史 变化时推送到同步服务器
      ref.listen(playlistProvider, (_, _) => _tryPushSync());
      ref.listen(dislikeListProvider, (_, _) => _tryPushSync());
      ref.listen(playHistoryProvider, (_, _) => _tryPushSync());
      // （页面用 AppColors 静态色板，不依赖 Theme inherited，不会随 Theme 变化自动重建）
    return MaterialApp.router(
      key: ValueKey('app_theme_${settings.isDarkMode}'),
      title: '波点音乐',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      routerConfig: AppRouter.router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        // 字体缩放（设置 → 字体大小）
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(settings.fontSize / 14),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
