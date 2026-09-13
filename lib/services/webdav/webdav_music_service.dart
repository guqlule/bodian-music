import 'package:hive/hive.dart';
import '../../core/utils/logger.dart';
import '../../models/music_model.dart';
import 'webdav_service.dart';

/// 支持的音频文件扩展名
const Set<String> audioExtensions = {
  'mp3', 'flac', 'wav', 'aac', 'm4a', 'ogg', 'ape', 'wma', 'opus', 'alac', 'aiff', 'ac3', 'dts',
};

/// WebDAV 音乐扫描/管理
class WebdavMusicService {
  static final WebdavMusicService _instance = WebdavMusicService._internal();
  factory WebdavMusicService() => _instance;
  WebdavMusicService._internal();

  static const String _libraryKey = 'webdav_library';
  static const String _configKey = 'webdav_config';

  List<MusicInfo> _songs = [];
  bool _isScanning = false;
  String? _scanProgress;
  int _totalFound = 0;
  int _scannedDirs = 0;

  List<MusicInfo> get songs => List.unmodifiable(_songs);
  bool get isScanning => _isScanning;
  String? get scanProgress => _scanProgress;
  int get totalFound => _totalFound;
  int get scannedDirs => _scannedDirs;

  Future<Box> get _box => Hive.openBox('webdav_music');

  /// 启动时从 Hive 恢复配置和歌曲列表
  Future<void> loadLibrary() async {
    try {
      final box = await _box;

      // 恢复配置
      final configRaw = box.get(_configKey);
      if (configRaw is Map) {
        final config = WebdavConfig.fromJson(Map<String, dynamic>.from(configRaw));
        if (config.host.isNotEmpty) {
          try {
            await WebdavService().connect(config);
          } catch (_) {
            // 连接失败不影响恢复歌曲列表
          }
        }
      }

      // 恢复歌曲列表
      final raw = box.get(_libraryKey);
      if (raw is List) {
        final loaded = <MusicInfo>[];
        for (final item in raw) {
          try {
            if (item is Map) {
              loaded.add(MusicInfo.fromJson(Map<String, dynamic>.from(item)));
            }
          } catch (_) {}
        }
        _songs = loaded;
        _totalFound = loaded.length;
      }
      logDebug('[WebdavMusic] 恢复 ${_songs.length} 首 WebDAV 歌曲');
    } catch (e) {
      logDebug('[WebdavMusic] 恢复失败: $e');
    }
  }

  /// 保存配置到 Hive
  Future<void> saveConfig(WebdavConfig config) async {
    try {
      final box = await _box;
      await box.put(_configKey, config.toJson());
    } catch (e) {
      logDebug('[WebdavMusic] 保存配置失败: $e');
    }
  }

  /// 扫描远程目录（递归）
  Future<int> scanRemote() async {
    final webdav = WebdavService();
    if (!webdav.isConnected) {
      throw WebdavException('WebDAV 未连接');
    }

    _isScanning = true;
    _scanProgress = '准备扫描...';
    _totalFound = 0;
    _scannedDirs = 0;

    try {
      final config = webdav.config!;
      final found = <MusicInfo>[];
      await _scanDirectory(webdav, config.remotePath, found, 0);

      _songs = found;
      _totalFound = found.length;
      _scanProgress = null;
      _isScanning = false;

      await _saveLibrary();
      logDebug('[WebdavMusic] 扫描完成，共 ${found.length} 首歌曲，${_scannedDirs} 个目录');
      return found.length;
    } catch (e) {
      _isScanning = false;
      _scanProgress = null;
      logDebug('[WebdavMusic] 扫描失败: $e');
      rethrow;
    }
  }

  Future<void> _scanDirectory(WebdavService webdav, String path, List<MusicInfo> found, int depth) async {
    // 防止目录嵌套过深
    if (depth > 10) return;

    try {
      final entries = await webdav.readDir(path);
      _scanProgress = path;
      _scannedDirs++;

      for (final entry in entries) {
        final name = entry.name ?? '';
        if (name.isEmpty || name.startsWith('.')) continue;

        final isDir = entry.isDir == true;
        final fullPath = '$path/$name';

        if (isDir) {
          await _scanDirectory(webdav, fullPath, found, depth + 1);
        } else {
          final ext = _getExtension(name).toLowerCase();
          if (audioExtensions.contains(ext)) {
            final songUrl = webdav.buildFileUrl(fullPath);
            final music = _buildMusicInfo(name, songUrl, fullPath);
            // 去重（按 songUrl）
            if (!found.any((s) => s.songUrl == songUrl)) {
              found.add(music);
              _totalFound = found.length;
            }
          }
        }
      }
    } on WebdavException catch (e) {
      logDebug('[WebdavMusic] 跳过目录 $path: ${e.message}');
      // 单个目录失败不中断整个扫描
    } catch (e) {
      logDebug('[WebdavMusic] 扫描目录失败: $path, $e');
    }
  }

  MusicInfo _buildMusicInfo(String fileName, String songUrl, String remotePath) {
    String name = fileName;
    String singer = '';
    String album = '';

    final nameWithoutExt = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;

    // 解析 "歌手 - 歌名" 格式
    if (nameWithoutExt.contains(' - ')) {
      final parts = nameWithoutExt.split(' - ');
      if (parts.length >= 2) {
        singer = parts[0].trim();
        name = parts.sublist(1).join(' - ').trim();
      }
    }

    // 用远程路径的父目录名作为专辑名
    final lastSlash = remotePath.lastIndexOf('/');
    if (lastSlash > 0) {
      final dirName = remotePath.substring(0, lastSlash).split('/').last;
      if (dirName.isNotEmpty) album = dirName;
    }

    return MusicInfo(
      id: 'webdav_${DateTime.now().millisecondsSinceEpoch}_${name.hashCode}',
      name: name,
      singer: singer,
      album: album,
      duration: 0,
      source: 'webdav',
      songUrl: songUrl,
      imgUrl: null,
      lyric: null,
      addTime: DateTime.now(),
    );
  }

  String _getExtension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot < 0) return '';
    return fileName.substring(lastDot + 1);
  }

  Future<void> _saveLibrary() async {
    try {
      final box = await _box;
      final jsonList = _songs.map((s) => s.toJson()).toList();
      await box.put(_libraryKey, jsonList);
    } catch (e) {
      logDebug('[WebdavMusic] 保存失败: $e');
    }
  }

  /// 删除一首歌
  Future<void> removeSong(String id) async {
    _songs.removeWhere((s) => s.id == id);
    await _saveLibrary();
  }

  /// 清空库
  Future<void> clearLibrary() async {
    _songs = [];
    await _saveLibrary();
  }
}
