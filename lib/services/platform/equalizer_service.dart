import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EqualizerService {
  static const _channel = MethodChannel('com.lxmusic/equalizer');
  static final EqualizerService _instance = EqualizerService._internal();
  factory EqualizerService() => _instance;
  EqualizerService._internal();

  bool _initialized = false;
  static const _prefKeyEnabled = 'eq_enabled';
  static const _prefKeyPreset = 'eq_preset';
  static const _prefKeyBands = 'eq_bands';

  /// 连接到音频会话
  Future<void> attachSession(int sessionId) async {
    try {
      await _channel.invokeMethod('attachSession', {'sessionId': sessionId});
      _initialized = true;
    } catch (e) {
      _initialized = false;
    }
  }

  /// 启用/禁用均衡器
  Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setEnabled', {'enabled': enabled});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyEnabled, enabled);
    } catch (_) {}
  }

  /// 设置指定频段的增益（单位: 0.1dB）
  Future<void> setBandLevel(int index, int level) async {
    try {
      await _channel.invokeMethod('setBandLevel', {
        'index': index,
        'level': level,
      });
    } catch (_) {}
  }

  /// 批量设置频段并持久化
  Future<void> setBandLevels(List<int> levels, String preset) async {
    try {
      for (int i = 0; i < levels.length; i++) {
        await _channel.invokeMethod('setBandLevel', {
          'index': i,
          'level': levels[i],
        });
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefKeyBands, levels.map((l) => l.toString()).toList());
      await prefs.setString(_prefKeyPreset, preset);
    } catch (_) {}
  }

  /// 获取均衡器信息（频段数、范围等）
  Future<EqInfo?> getInfo() async {
    try {
      final result = await _channel.invokeMethod<Map>('getBands');
      if (result == null) return null;
      return EqInfo.fromMap(result);
    } catch (_) {
      return null;
    }
  }

  /// 加载持久化的均衡器设置
  Future<EqPersistedSettings?> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_prefKeyEnabled);
      final preset = prefs.getString(_prefKeyPreset);
      final bands = prefs.getStringList(_prefKeyBands);
      if (enabled == null && preset == null && bands == null) return null;
      return EqPersistedSettings(
        enabled: enabled ?? true,
        preset: preset ?? 'flat',
        bandLevels: bands?.map(int.parse).toList(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 释放均衡器
  Future<void> release() async {
    try {
      await _channel.invokeMethod('release');
      _initialized = false;
    } catch (_) {}
  }

  bool get isInitialized => _initialized;
}

class EqPersistedSettings {
  final bool enabled;
  final String preset;
  final List<int>? bandLevels;

  EqPersistedSettings({
    required this.enabled,
    required this.preset,
    this.bandLevels,
  });
}

class EqInfo {
  final bool enabled;
  final int bandCount;
  final List<EqBandInfo> bands;

  EqInfo({
    required this.enabled,
    required this.bandCount,
    required this.bands,
  });

  factory EqInfo.fromMap(Map map) {
    final bandsList = (map['bands'] as List?)
            ?.map((b) => EqBandInfo.fromMap(b))
            .toList() ??
        [];
    return EqInfo(
      enabled: map['enabled'] == true,
      bandCount: map['bandCount'] ?? 0,
      bands: bandsList,
    );
  }
}

class EqBandInfo {
  final int index;
  final int centerFreq;
  final int minLevel;
  final int maxLevel;
  final int currentLevel;

  EqBandInfo({
    required this.index,
    required this.centerFreq,
    required this.minLevel,
    required this.maxLevel,
    required this.currentLevel,
  });

  factory EqBandInfo.fromMap(Map map) {
    return EqBandInfo(
      index: map['index'] ?? 0,
      centerFreq: map['centerFreq'] ?? 0,
      minLevel: map['minLevel'] ?? 0,
      maxLevel: map['maxLevel'] ?? 0,
      currentLevel: map['currentLevel'] ?? 0,
    );
  }

  /// 频率（Hz）转换为可读格式
  String get displayFreq {
    if (centerFreq >= 1000) {
      final k = centerFreq / 1000;
      return k == k.roundToDouble() ? '${k.toInt()}k' : '${k.toStringAsFixed(1)}k';
    }
    return centerFreq.toString();
  }
}
