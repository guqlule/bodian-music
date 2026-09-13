import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final bool isDarkMode;
  final bool isAutoTheme;
  final String themeId;
  final double fontSize;
  final String language;
  final String quality;
  final bool playOnBoot;
  final bool showDesktopLyric;
  final bool enableSync;
  final String syncHost;
  final int playMode;
  final bool gaplessPlayback;

  AppSettings({
    this.isDarkMode = false,
    this.isAutoTheme = true,
    this.themeId = 'default',
    this.fontSize = 14.0,
    this.language = 'zh_CN',
    this.quality = '320k',
    this.gaplessPlayback = true,
    this.playOnBoot = false,
    this.showDesktopLyric = false,
    this.enableSync = false,
    this.syncHost = '',
    this.playMode = 0,
  });

  AppSettings copyWith({
    bool? isDarkMode,
    bool? isAutoTheme,
    String? themeId,
    double? fontSize,
    String? language,
    String? quality,
    bool? gaplessPlayback,
    bool? playOnBoot,
    bool? showDesktopLyric,
    bool? enableSync,
    String? syncHost,
    int? playMode,
  }) {
    return AppSettings(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      isAutoTheme: isAutoTheme ?? this.isAutoTheme,
      themeId: themeId ?? this.themeId,
      fontSize: fontSize ?? this.fontSize,
      language: language ?? this.language,
      quality: quality ?? this.quality,
      gaplessPlayback: gaplessPlayback ?? this.gaplessPlayback,
      playOnBoot: playOnBoot ?? this.playOnBoot,
      showDesktopLyric: showDesktopLyric ?? this.showDesktopLyric,
      enableSync: enableSync ?? this.enableSync,
      syncHost: syncHost ?? this.syncHost,
      playMode: playMode ?? this.playMode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isDarkMode': isDarkMode,
      'isAutoTheme': isAutoTheme,
      'themeId': themeId,
      'fontSize': fontSize,
      'language': language,
      'quality': quality,
      'gaplessPlayback': gaplessPlayback,
      'playOnBoot': playOnBoot,
      'showDesktopLyric': showDesktopLyric,
      'enableSync': enableSync,
      'syncHost': syncHost,
      'playMode': playMode,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      isDarkMode: json['isDarkMode'] ?? false,
      isAutoTheme: json['isAutoTheme'] ?? true,
      themeId: json['themeId'] ?? 'default',
      fontSize: (json['fontSize'] ?? 14.0).toDouble(),
      language: json['language'] ?? 'zh_CN',
      quality: json['quality'] ?? '320k',
      gaplessPlayback: json['gaplessPlayback'] ?? true,
      playOnBoot: json['playOnBoot'] ?? false,
      showDesktopLyric: json['showDesktopLyric'] ?? false,
      enableSync: json['enableSync'] ?? false,
      syncHost: json['syncHost'] ?? '',
      playMode: json['playMode'] ?? 0,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(AppSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settingsJson = prefs.getString('app_settings');
    if (settingsJson != null) {
      try {
        final json = Map<String, dynamic>.from(
          Map.from(jsonDecode(settingsJson) as Map),
        );
        state = AppSettings.fromJson(json);
      } catch (e) {
        // Use default settings
      }
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_settings', jsonEncode(state.toJson()));
  }

  void setDarkMode(bool isDark) {
    state = state.copyWith(isDarkMode: isDark);
    _saveSettings();
  }

  void setAutoTheme(bool isAuto) {
    state = state.copyWith(isAutoTheme: isAuto);
    _saveSettings();
  }

  void setThemeId(String themeId) {
    state = state.copyWith(themeId: themeId);
    _saveSettings();
  }

  void setFontSize(double size) {
    state = state.copyWith(fontSize: size);
    _saveSettings();
  }

  void setLanguage(String lang) {
    state = state.copyWith(language: lang);
    _saveSettings();
  }

  void setGaplessPlayback(bool enabled) {
    state = state.copyWith(gaplessPlayback: enabled);
    _saveSettings();
  }

  void setQuality(String quality) {
    state = state.copyWith(quality: quality);
    _saveSettings();
  }

  void setPlayOnBoot(bool enabled) {
    state = state.copyWith(playOnBoot: enabled);
    _saveSettings();
  }

  void setDesktopLyric(bool enabled) {
    state = state.copyWith(showDesktopLyric: enabled);
    _saveSettings();
  }

  void setEnableSync(bool enabled) {
    state = state.copyWith(enableSync: enabled);
    _saveSettings();
  }

  void setSyncHost(String host) {
    state = state.copyWith(syncHost: host);
    _saveSettings();
  }

  void setPlayMode(int mode) {
    state = state.copyWith(playMode: mode);
    _saveSettings();
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});
