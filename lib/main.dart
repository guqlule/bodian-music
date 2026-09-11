import 'package:flutter/material.dart';
import '../core/utils/logger.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ui' show AppExitResponse;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/storage/storage_service.dart';
import 'core/storage/hive_adapters.dart';
import 'core/router/app_router.dart';
import 'services/api/user_api_service.dart';
import 'services/player/player_service.dart';
import 'providers/app_providers.dart';
import 'providers/settings_provider.dart';

void main() async {
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

  @override
  void initState() {
    super.initState();
    // 播放成功 → 同步最近播放
    PlayerService.onMusicPlayed = (music) {
      try {
        ref.read(recentPlayedProvider.notifier).addRecent(music);
      } catch (_) {}
    };
    // 首帧后激活自定义源脚本（JS引擎初始化耗时，不阻塞冷启动首屏）+ 同步音质设置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _activatePersistedScript();
        // 音质设置同步到播放服务
        final quality = ref.read(settingsProvider).quality;
        PlayerService.instance.setPreferredQuality(quality);
        PlayerService.instance.setPrefetchEnabled(ref.read(settingsProvider).gaplessPlayback);
      } catch (e) {
        logDebug('[Init] 初始化流程异常: $e');
      }
    });
    // 切后台/隐藏/退出时立即持久化播放队列（覆盖各种退出路径）
    _lifecycle = AppLifecycleListener(
      onPause: _persistPlaylist,
      onHide: _persistPlaylist,
      onDetach: _persistPlaylist,
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
