import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final bool isDarkMode;
  final double fontSize;
  final String quality;
  final bool enableSync;
  final String syncHost;
  final String syncCode;
  final bool gaplessPlayback;
  final bool enableBluetoothLyric;

  AppSettings({
    this.isDarkMode = false,
    this.fontSize = 14.0,
    this.quality = '320k',
    this.gaplessPlayback = true,
    this.enableSync = false,
    this.syncHost = '',
    this.syncCode = '',
    this.enableBluetoothLyric = true,
  });

  AppSettings copyWith({
    bool? isDarkMode,
    double? fontSize,
    String? quality,
    bool? gaplessPlayback,
    bool? enableSync,
    String? syncHost,
    String? syncCode,
    bool? enableBluetoothLyric,
  }) {
    return AppSettings(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      fontSize: fontSize ?? this.fontSize,
      quality: quality ?? this.quality,
      gaplessPlayback: gaplessPlayback ?? this.gaplessPlayback,
      enableSync: enableSync ?? this.enableSync,
      syncHost: syncHost ?? this.syncHost,
      syncCode: syncCode ?? this.syncCode,
      enableBluetoothLyric: enableBluetoothLyric ?? this.enableBluetoothLyric,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isDarkMode': isDarkMode,
      'fontSize': fontSize,
      'quality': quality,
      'gaplessPlayback': gaplessPlayback,
      'enableSync': enableSync,
      'syncHost': syncHost,
      'syncCode': syncCode,
      'enableBluetoothLyric': enableBluetoothLyric,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      isDarkMode: json['isDarkMode'] ?? false,
      fontSize: (json['fontSize'] ?? 14.0).toDouble(),
      quality: json['quality'] ?? '320k',
      gaplessPlayback: json['gaplessPlayback'] ?? true,
      enableSync: json['enableSync'] ?? false,
      syncHost: json['syncHost'] ?? '',
      syncCode: json['syncCode'] ?? '',
      enableBluetoothLyric: json['enableBluetoothLyric'] ?? true,
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

  void setFontSize(double size) {
    state = state.copyWith(fontSize: size);
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

  void setEnableSync(bool enabled) {
    state = state.copyWith(enableSync: enabled);
    _saveSettings();
  }

  void setSyncConfig(String host, String code) {
    state = state.copyWith(syncHost: host, syncCode: code, enableSync: true);
    _saveSettings();
  }

  void setBluetoothLyric(bool enabled) {
    state = state.copyWith(enableBluetoothLyric: enabled);
    _saveSettings();
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});
