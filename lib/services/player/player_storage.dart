import 'package:hive/hive.dart';
import '../../models/music_model.dart';
import '../../core/utils/logger.dart';

/// 播放器本地持久化（统一 Hive 'player' box 访问 + 容错）
class PlayerStorage {
  static const String historyKey = 'play_history';
  static const String modeKey = 'play_mode';
  static const String playedKey = 'played_list';
  static const String playlistKey = 'current_playlist';
  static const String indexKey = 'current_index';
  static const String speedKey = 'play_speed';

  Future<Box> _box() => Hive.openBox('player');

  /// 加载 MusicInfo 列表（逐项容错：单条损坏不影响整体）
  Future<List<MusicInfo>> loadMusicList(String key) async {
    try {
      final box = await _box();
      final json = box.get(key, defaultValue: []);
      final list = <MusicInfo>[];
      if (json is List) {
        for (final item in json) {
          try {
            if (item is Map) {
              list.add(MusicInfo.fromJson(Map<String, dynamic>.from(item)));
            }
          } catch (e) {
            logDebug('[PlayerStorage] 跳过损坏条目($key): $e');
          }
        }
      }
      return list;
    } catch (e) {
      logDebug('[PlayerStorage] 加载失败($key): $e');
      return [];
    }
  }

  /// 保存 MusicInfo 列表（写入后 flush 落盘）
  Future<void> saveMusicList(String key, List<MusicInfo> list) async {
    try {
      final box = await _box();
      await box.put(key, list.map((m) => m.toJson()).toList());
      await box.flush();
    } catch (e) {
      logDebug('[PlayerStorage] 保存失败($key): $e');
    }
  }

  Future<int> loadPlayModeIndex() async {
    try {
      final box = await _box();
      return box.get(modeKey, defaultValue: 0) as int;
    } catch (e) {
      logDebug('[PlayerStorage] 加载播放模式失败: $e');
      return 0;
    }
  }

  Future<void> savePlayModeIndex(int index) async {
    try {
      final box = await _box();
      await box.put(modeKey, index);
    } catch (e) {
      logDebug('[PlayerStorage] 保存播放模式失败: $e');
    }
  }

  Future<double> loadSpeed() async {
    try {
      final box = await _box();
      return box.get(speedKey, defaultValue: 1.0) as double;
    } catch (e) {
      logDebug('[PlayerStorage] 加载播放速度失败: $e');
      return 1.0;
    }
  }

  Future<void> saveSpeed(double speed) async {
    try {
      final box = await _box();
      await box.put(speedKey, speed);
    } catch (e) {
      logDebug('[PlayerStorage] 保存播放速度失败: $e');
    }
  }

  Future<int> loadCurrentIndex() async {
    try {
      final box = await _box();
      return box.get(indexKey, defaultValue: -1) as int;
    } catch (e) {
      logDebug('[PlayerStorage] 加载索引失败: $e');
      return -1;
    }
  }

  Future<void> saveCurrentIndex(int index) async {
    try {
      final box = await _box();
      await box.put(indexKey, index);
    } catch (e) {
      logDebug('[PlayerStorage] 保存索引失败: $e');
    }
  }
}
