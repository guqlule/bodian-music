import 'dart:io';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/utils/logger.dart';
import '../../models/music_model.dart';
import '../lyric/lyric_parser.dart';
import '../platform/metadata_service.dart';

/// 本地音乐扫描/管理
/// - 导入文件夹（用户选择的目录）递归扫描音频文件
/// - 同名 .lrc 歌词自动匹配（song.mp3 → song.lrc）
/// - 已扫描歌单持久化到 Hive（重启不丢）
class LocalMusicService {
  static final LocalMusicService _instance = LocalMusicService._internal();
  factory LocalMusicService() => _instance;
  LocalMusicService._internal();

  static const String _libraryKey = 'local_music_library';
  static const String _foldersKey = 'local_music_folders';

  List<MusicInfo> _localSongs = [];
  List<String> _folders = [];
  bool _isScanning = false;
  String? _scanProgress;

  List<MusicInfo> get localSongs => List.unmodifiable(_localSongs);
  List<String> get folders => List.unmodifiable(_folders);
  bool get isScanning => _isScanning;
  String? get scanProgress => _scanProgress;

  Future<Box> get _box => Hive.openBox('local_music');

  /// 启动时从 Hive 恢复歌单（并校验文件仍存在）
  Future<void> loadLibrary() async {
    try {
      final box = await _box;
      final raw = box.get(_libraryKey);
      final folders = box.get(_foldersKey);
      if (folders is List) {
        _folders = folders.map((f) => f.toString()).toList();
      }
      if (raw is List) {
        final loaded = <MusicInfo>[];
        for (final item in raw) {
          try {
            if (item is Map) {
              final m = MusicInfo.fromJson(Map<String, dynamic>.from(item));
              // 文件已被删除/移动的歌曲剔除
              if (m.songUrl != null && await File(m.songUrl!).exists()) {
                loaded.add(m);
              }
            }
          } catch (_) {}
        }
        _localSongs = loaded;
      }

      // 自动注册下载目录（首次 / 从未登记过）
      final downloadDir = await _getDownloadDir();
      if (downloadDir != null && await Directory(downloadDir).exists()
          && !_folders.contains(downloadDir)) {
        _folders.add(downloadDir);
        await _saveLibrary();
        logDebug('[LocalMusic] 自动注册下载目录: $downloadDir');
      }

      logDebug('[LocalMusic] 恢复 ${_localSongs.length} 首本地歌曲');
    } catch (e) {
      logDebug('[LocalMusic] 恢复失败: $e');
    }
  }

  /// 下载完成后即时追加到本地库（由 DownloadService 触发）
  Future<void> addDownloadedFile(MusicInfo song) async {
    if (_localSongs.any((s) => s.id == song.id)) return;
    _localSongs.add(song);
    await _saveLibrary();
    logDebug('[LocalMusic] 追加下载歌曲: ${song.name}');
  }

  Future<String?> _getDownloadDir() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final downloadDir = '${directory.path}/lx_music/downloads';
      return downloadDir;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveLibrary() async {
    try {
      final box = await _box;
      await box.put(_libraryKey, _localSongs.map((m) => m.toJson()).toList());
      await box.put(_foldersKey, _folders);
    } catch (e) {
      logDebug('[LocalMusic] 保存失败: $e');
    }
  }

  /// 导入文件夹：递归扫描音频 + 歌词，追加到歌单（按路径去重）
  /// 返回新增数量
  Future<int> importFolder(String folderPath) async {
    if (_isScanning) return 0;
    _isScanning = true;
    _scanProgress = '正在扫描...';
    var added = 0;

    try {
      final dir = Directory(folderPath);
      if (!await dir.exists()) return 0;

      // 记录已导入路径
      final existingPaths = _localSongs.map((s) => s.songUrl).toSet();

      final supportedExtensions = [
        '.mp3', '.flac', '.wav', '.aac', '.m4a', '.ogg', '.ape',
        '.wma', '.opus', '.alac', '.aiff', '.ac3', '.dts',
      ];
      final files = <File>[];
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final lower = entity.path.toLowerCase();
          if (supportedExtensions.any((e) => lower.endsWith(e))) {
            files.add(entity);
          }
        }
      }

      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        _scanProgress = '扫描中 (${i + 1}/${files.length})';
        if (existingPaths.contains(file.path)) continue;

        final song = await _buildSongFromFile(file);
        _localSongs.add(song);
        added++;
      }

      // 记录文件夹（下次刷新用）
      if (!_folders.contains(folderPath)) {
        _folders.add(folderPath);
      }
      await _saveLibrary();
      _scanProgress = null;
      logDebug('[LocalMusic] 导入完成: +$added 首（共 ${_localSongs.length}）');
      return added;
    } catch (e) {
      _scanProgress = null;
      _isScanning = false;
      logDebug('[LocalMusic] 扫描失败: $e');
      rethrow;
    } finally {
      _isScanning = false;
    }
  }

  /// 从单文件构建 MusicInfo（优先读取 ID3 标签，回退到文件名解析）
  Future<MusicInfo> _buildSongFromFile(File file) async {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final dotIdx = fileName.lastIndexOf('.');
    final baseName = dotIdx > 0 ? fileName.substring(0, dotIdx) : fileName;

    // 默认值（文件名解析）
    var name = baseName;
    var singer = '本地音乐';
    var album = '本地';
    var duration = 0;
    String? artPath;

    // 尝试从 ID3 标签提取元数据
    try {
      final metadata = await MetadataService().extractMetadata(file.path);
      if (metadata != null) {
        final metaTitle = metadata['title'] as String?;
        final metaArtist = metadata['artist'] as String?;
        final metaAlbum = metadata['album'] as String?;
        final metaDuration = metadata['duration'] as int?;
        artPath = metadata['artPath'] as String?;

        if (metaTitle != null && metaTitle.isNotEmpty) name = metaTitle;
        if (metaArtist != null && metaArtist.isNotEmpty) singer = metaArtist;
        if (metaAlbum != null && metaAlbum.isNotEmpty) album = metaAlbum;
        if (metaDuration != null && metaDuration > 0) duration = metaDuration;
      }
    } catch (_) {
      // 提取失败，回退到文件名解析
    }

    // 无 ID3 标签时，从文件名解析 "歌手 - 歌名"
    if (singer == '本地音乐') {
      final sepIdx = baseName.indexOf(' - ');
      if (sepIdx > 0) {
        singer = baseName.substring(0, sepIdx).trim();
        name = baseName.substring(sepIdx + 3).trim();
      }
    }

    // 无真实时长时，粗略估算
    if (duration == 0) {
      try {
        final size = file.lengthSync();
        final ext = file.path.toLowerCase();
        if (ext.endsWith('.flac') || ext.endsWith('.ape')) {
          duration = (size / 524288 * 60000).round();
        } else {
          duration = (size / 1048576 * 60000).round();
        }
      } catch (_) {}
    }

    return MusicInfo(
      id: 'local_${file.path.hashCode}',
      name: name,
      singer: singer,
      album: album,
      duration: duration,
      source: 'local',
      songUrl: file.path,
      imgUrl: artPath,
      addTime: DateTime.now(),
    );
  }

  /// 获取本地歌词（同名 .lrc 文件），找不到返回 null
  Future<Map<String, String?>?> getLocalLyric(MusicInfo song) async {
    try {
      final path = song.songUrl;
      if (path == null) return null;
      final dotIdx = path.lastIndexOf('.');
      final base = dotIdx > 0 ? path.substring(0, dotIdx) : path;

      // 优先同名 .lrc；其次 .txt
      for (final ext in ['.lrc', '.txt']) {
        final f = File('$base$ext');
        if (await f.exists()) {
          final lyricText = await f.readAsString();
          if (lyricText.trim().isNotEmpty) {
            return {'lyric': lyricText, 'tlyric': null};
          }
        }
      }
      return null;
    } catch (e) {
      logDebug('[LocalMusic] 歌词读取失败: $e');
      return null;
    }
  }

  /// 同步解析歌词（播放器拿到 lyric map 后调 LyricParser.parse）
  List<LyricLine> parseLyric(String lyricText) => LyricParser.parse(lyricText);

  /// 重新扫描所有已登记文件夹（清理失效文件）
  Future<void> refresh() async {
    if (_isScanning) return;
    // 先剔除失效文件
    final valid = <MusicInfo>[];
    for (final s in _localSongs) {
      if (s.songUrl != null && await File(s.songUrl!).exists()) {
        valid.add(s);
      }
    }
    _localSongs = valid;
    final folders = List<String>.from(_folders);
    for (final folder in folders) {
      if (!await Directory(folder).exists()) {
        _folders.remove(folder);
        continue;
      }
      await importFolder(folder);
    }
    await _saveLibrary();
  }

  /// 移除文件夹及其歌曲
  Future<void> removeFolder(String folderPath) async {
    _folders.remove(folderPath);
    _localSongs.removeWhere((s) => s.songUrl?.startsWith(folderPath) ?? false);
    await _saveLibrary();
  }

  /// 清空本地歌单（不删文件）
  Future<void> clearLibrary() async {
    _localSongs = [];
    _folders = [];
    await _saveLibrary();
  }

  /// 从列表移除单首（不删文件）
  Future<void> removeSong(String songId) async {
    _localSongs.removeWhere((s) => s.id == songId);
    await _saveLibrary();
  }

  /// 测试辅助：追加单条（不做去重/解析）
  Future<void> appendEntry(MusicInfo song) async {
    _localSongs.add(song);
    await _saveLibrary();
  }

  /// 测试辅助：按文件重建条目
  Future<MusicInfo> rebuildEntry(File file) => _buildSongFromFile(file);

  /// 更新歌曲实际时长（播放器获取到真实时长后调用）
  Future<void> updateSongDuration(String songId, int durationMs) async {
    final idx = _localSongs.indexWhere((s) => s.id == songId);
    if (idx < 0) return;
    final old = _localSongs[idx];
    if (old.duration == durationMs) return;
    _localSongs[idx] = MusicInfo(
      id: old.id,
      name: old.name,
      singer: old.singer,
      album: old.album,
      duration: durationMs,
      source: old.source,
      songUrl: old.songUrl,
      imgUrl: old.imgUrl,
      songId: old.songId,
      addTime: old.addTime,
    );
    await _saveLibrary();
  }
}
