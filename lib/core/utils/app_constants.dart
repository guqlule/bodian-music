class AppConstants {
  // Storage Keys
  static const String settingsBox = 'settings';
  static const String playlistBox = 'playlists';
  static const String cacheBox = 'cache';
  static const String searchHistoryBox = 'search_history';

  // Default Settings
  static const bool defaultDarkMode = false;
  static const double defaultFontSize = 14.0;
  static const String defaultLanguage = 'zh_CN';
  static const String defaultQuality = 'standard';

  // API
  static const String apiBaseUrl = 'https://api.lxmusic.example.com';
  static const int apiTimeout = 30000;

  // Player
  static const int maxRecentPlayed = 50;
  static const int maxSearchHistory = 20;

  // Cache
  static const int maxCacheSize = 500 * 1024 * 1024; // 500MB
  static const Duration cacheDuration = Duration(days: 7);
}
