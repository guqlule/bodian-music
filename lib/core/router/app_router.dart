import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/search/search_screen.dart';
import '../../screens/equalizer/equalizer_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../screens/songlist_detail/songlist_detail_screen.dart';
import '../../screens/my_list/my_list_screen.dart';
import '../../screens/local_music/local_music_screen.dart';
import '../../screens/playlist_detail/playlist_detail_screen.dart';
import '../../screens/download/download_screen.dart';
import '../../screens/lyric/lyric_screen.dart';
import '../../screens/favorites/favorites_screen.dart';
import '../../screens/recent/recent_screen.dart';
import '../../screens/about/about_screen.dart';
import '../../screens/user_api/user_api_screen.dart';
import '../../screens/sleep_timer/sleep_timer_screen.dart';
import '../../screens/play_history/play_history_screen.dart';
import '../../screens/leaderboard/leaderboard_screen.dart';
import '../../screens/webdav/webdav_music_screen.dart';
import '../../screens/webdav/webdav_settings_screen.dart';

/// 全局路由状态：非首页时为 true（显示迷你播放器）
final ValueNotifier<bool> subPageNotifier = ValueNotifier<bool>(false);

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
        routes: [
          GoRoute(
            path: 'search',
            pageBuilder: (context, state) => CustomTransitionPage(
              child: const SearchScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  )),
                  child: child,
                );
              },
            ),
          ),
          GoRoute(
            path: 'equalizer',
            builder: (context, state) => const EqualizerScreen(),
          ),
          GoRoute(
            path: 'settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: 'songlist-detail/:id',
            builder: (context, state) {
              final extra = state.extra as Map<String, String>?;
              return SonglistDetailScreen(
                songlistId: state.pathParameters['id']!,
                songlistName: extra?['name'] ?? '歌单',
                source: extra?['source'] ?? 'kw',
              );
            },
          ),
          GoRoute(
            path: 'my-list',
            builder: (context, state) => const MyListScreen(),
          ),
          GoRoute(
            path: 'local-music',
            builder: (context, state) => const LocalMusicScreen(),
          ),
          GoRoute(
            path: 'playlist-detail/:id',
            builder: (context, state) {
              final extra = state.extra as Map<String, String>?;
              return PlaylistDetailScreen(
                playlistId: state.pathParameters['id']!,
                playlistName: extra?['name'] ?? '播放列表',
              );
            },
          ),
          GoRoute(
            path: 'download',
            builder: (context, state) => const DownloadScreen(),
          ),
          GoRoute(
            path: 'lyric',
            builder: (context, state) => const LyricScreen(),
          ),
          GoRoute(
            path: 'favorites',
            builder: (context, state) => const FavoritesScreen(),
          ),
          GoRoute(
            path: 'recent',
            builder: (context, state) => const RecentScreen(),
          ),
          GoRoute(
            path: 'about',
            builder: (context, state) => const AboutScreen(),
          ),
          GoRoute(
            path: 'user-api',
            builder: (context, state) => const UserApiScreen(),
          ),
          GoRoute(
            path: 'sleep-timer',
            builder: (context, state) => const SleepTimerScreen(),
          ),
          GoRoute(
            path: 'play-history',
            builder: (context, state) => const PlayHistoryScreen(),
          ),
          GoRoute(
            path: 'leaderboard',
            builder: (context, state) => const LeaderboardScreen(),
          ),
          GoRoute(
            path: 'webdav',
            builder: (context, state) => const WebdavMusicScreen(),
          ),
          GoRoute(
            path: 'webdav-settings',
            builder: (context, state) => const WebdavSettingsScreen(),
          ),
        ],
      ),
    ],
  );
}
