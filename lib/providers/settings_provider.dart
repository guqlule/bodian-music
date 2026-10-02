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

  /// 车机模式：auto=自动检测 / force=强制车机模式 / off=强制蓝牙模式
  /// 车机模式 title 保持歌名、歌词写通知副标题（Jovi InCar 等读通知的投屏车机）；
  /// 蓝牙模式 title 写歌词行（AVRCP 车机只认 title）。
  final String carMode;

  /// 歌词源偏好：auto=自动（按歌曲来源取，失败再跨源兜底）
  /// kg=酷狗(KRC 逐字) / wy=网易云 / tx=QQ / kw=酷我 / user=用户脚本
  /// 注意 tx/kw 只能用本源的 songId，跨源歌曲取不到。
  final String lyricSource;

  AppSettings({
    this.isDarkMode = false,
    this.fontSize = 14.0,
    this.quality = '320k',
    this.gaplessPlayback = true,
    this.enableSync = false,
    this.syncHost = '',
    this.syncCode = '',
    this.enableBluetoothLyric = true,
this.carMode = 'auto',
    this.lyricSource = 'auto',
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
String? carMode,
    String? lyricSource,
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
carMode: carMode ?? this.carMode,
      lyricSource: lyricSource ?? this.lyricSource,
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
'carMode': carMode,
      'lyricSource': lyricSource,
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
carMode: json['carMode'] ?? 'auto',
      lyricSource: json['lyricSource'] ?? 'auto',
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

void setCarMode(String mode) {
    state = state.copyWith(carMode: mode);
    _saveSettings();
  }

  void setLyricSource(String source) {
    state = state.copyWith(lyricSource: source);
    _saveSettings();
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});
