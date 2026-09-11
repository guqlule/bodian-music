import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:lx_music_flutter/core/storage/storage_service.dart';
import 'package:lx_music_flutter/models/music_model.dart';
import 'package:lx_music_flutter/models/playlist_model.dart';

/// 回归测试：歌单保存→重载（模拟App重启）后必须完整恢复
/// 修复的bug：Hive 反序列化的 Map<dynamic,dynamic> 传给
/// MusicInfo.fromJson(Map<String,dynamic>) 抛类型错误，导致歌单加载永远为空
void main() {
  late Directory tempDir;
  late StorageService storage;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('lx_playlist_test');
    storage = StorageService();
    // 传入本地路径绕过 path_provider 插件（测试环境）
    await storage.init(hivePath: tempDir.path);
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('Playlist roundtrip: save -> reload simulates app restart', () async {
    // 1. 创建歌单并保存（模拟导入/创建）
    final playlist = PlaylistInfo(
      id: 'import_tx_7945460847',
      name: '测试歌单',
      createTime: DateTime.now(),
      updateTime: DateTime.now(),
      songs: [
        MusicInfo(
          id: 'tx_001', name: '歌曲一', singer: '歌手A', album: '专辑A',
          duration: 200000, source: 'tx', songId: '1', songmid: 'm1',
        ),
        MusicInfo(
          id: 'tx_002', name: '歌曲二', singer: '歌手B', album: '专辑B',
          duration: 180000, source: 'tx', songId: '2', songmid: 'm2',
        ),
      ],
    );
    await storage.savePlaylist(
        playlist.id, playlist.songs.map((s) => s.toJson()).toList());
    await storage.savePlaylistMeta(playlist.id, {
      'name': playlist.name,
      'createTime': playlist.createTime.toIso8601String(),
      'updateTime': playlist.updateTime.toIso8601String(),
      'coverUrl': playlist.coverUrl,
      'description': playlist.description,
    });

    // 2. 模拟重启：重新走 PlaylistNotifier 的加载逻辑
    final ids = storage.getAllPlaylistIds();
    expect(ids, contains('import_tx_7945460847'));

    final raw = storage.getPlaylist('import_tx_7945460847');
    expect(raw, isNotNull);

    final json = {
      'id': 'import_tx_7945460847',
      'songs': raw,
      ...?storage.getPlaylistMeta('import_tx_7945460847'),
    };

    // 3. 关键：从 Hive 恢复的数据（Map<dynamic,dynamic>）必须能解析
    final restored = PlaylistInfo.fromJson(Map<String, dynamic>.from(json));
    expect(restored.name, '测试歌单');
    expect(restored.songs.length, 2);
    expect(restored.songs[0].name, '歌曲一');
    expect(restored.songs[0].source, 'tx');
    expect(restored.songs[1].singer, '歌手B');
  });

  test('Meta 缺失时（旧数据）也不抛异常', () {
    final json = {
      'id': 'old_list',
      'songs': [
        {'id': 'kw_1', 'name': '歌', 'singer': '人', 'album': '', 'duration': 1},
      ],
      // 无 createTime/updateTime/name
    };
    final restored = PlaylistInfo.fromJson(Map<String, dynamic>.from(json));
    expect(restored.id, 'old_list');
    expect(restored.songs.length, 1);
    expect(restored.name, '未命名歌单');
  });
}
