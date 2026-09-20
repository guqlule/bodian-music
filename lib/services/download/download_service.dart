import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/logger.dart';
import '../../models/music_model.dart';
import '../local/local_music_service.dart';

class DownloadService {
  final Dio _dio = Dio();
  final String _downloadPath = 'lx_music/downloads';

  static const String _downloadQueueKey = 'download_queue';
  static const String _downloadedKey = 'downloaded_songs';

  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  // 每任务一个取消令牌（不能用 _dio.close()——会杀死单例 Dio 永久不可用）
  final Map<String, CancelToken> _cancelTokens = {};
  // 并发守卫：防止 addToDownloadQueue/retry 同时触发多个 _processQueue
  bool _isProcessing = false;
  // 进度写盘节流
  Timer? _progressSaveTimer;

  // 实时进度广播流 —— 供 UI 层（DownloadNotifier）监听，无需反复读 SharedPreferences
  final StreamController<DownloadTask> _taskStreamController =
      StreamController<DownloadTask>.broadcast();
  Stream<DownloadTask> get taskStream => _taskStreamController.stream;

  void _emitTask(DownloadTask task) {
    if (!_taskStreamController.isClosed) {
      _taskStreamController.add(task);
    }
  }

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${directory.path}/$_downloadPath');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir.path;
  }

  Future<List<DownloadTask>> getDownloadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final queueJson = prefs.getStringList(_downloadQueueKey) ?? [];
    final result = <DownloadTask>[];
    // 逐项容错：单条损坏不影响队列
    for (final json in queueJson) {
      try {
        result.add(DownloadTask.fromJson(json));
      } catch (e) {
        logDebug('[Download] 跳过损坏任务: $e');
      }
    }
    return result;
  }

  Future<void> _saveDownloadQueue(List<DownloadTask> queue) async {
    final prefs = await SharedPreferences.getInstance();
    final queueJson = queue.map((task) => task.toJson()).toList();
    await prefs.setStringList(_downloadQueueKey, queueJson);
  }

  Future<List<MusicInfo>> getDownloadedSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final songsJson = prefs.getStringList(_downloadedKey) ?? [];
    final result = <MusicInfo>[];
    for (final json in songsJson) {
      try {
        // 兼容历史损坏数据：可能存的是 toString() 而非 JSON
        if (!json.startsWith('{')) continue;
        result.add(MusicInfo.fromJson(
            Map<String, dynamic>.from(jsonDecode(json) as Map)));
      } catch (e) {
        logDebug('[Download] 跳过损坏歌曲记录: $e');
      }
    }
    return result;
  }

  Future<void> _saveDownloadedSongs(List<MusicInfo> songs) async {
    final prefs = await SharedPreferences.getInstance();
    // 修复：之前用 toJson().toString()（Map.toString 不是 JSON），读取必抛
    final songsJson = songs.map((song) => jsonEncode(song.toJson())).toList();
    await prefs.setStringList(_downloadedKey, songsJson);
  }

  Future<void> addToDownloadQueue(MusicInfo music, {String quality = '320'}) async {
    final queue = await getDownloadQueue();

    if (queue.any((task) => task.music.id == music.id)) {
      return;
    }

    final task = DownloadTask(
      music: music,
      quality: quality,
      status: DownloadStatus.pending,
      progress: 0,
      addedTime: DateTime.now(),
    );

    queue.add(task);
    await _saveDownloadQueue(queue);

    _processQueue();
  }

  Future<void> _processQueue() async {
    // 并发守卫：同时只处理一个任务，完成后自动继续
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      while (true) {
        final queue = await getDownloadQueue();
        // 卡死任务恢复：上次进程被杀时 status=downloading 的任务重置为 pending
        var recovered = false;
        for (final t in queue) {
          if (t.status == DownloadStatus.downloading) {
            t.status = DownloadStatus.pending;
            t.progress = 0;
            t.error = null;
            recovered = true;
          }
        }
        if (recovered) {
          await _saveDownloadQueue(queue);
        }

        final pendingTasks =
            queue.where((task) => task.status == DownloadStatus.pending).toList();
        if (pendingTasks.isEmpty) break;

        final currentTask = pendingTasks.first;
        currentTask.status = DownloadStatus.downloading;
        currentTask.progress = 0;
        await _saveDownloadQueue(queue);
        _emitTask(currentTask);

        try {
          final downloadDir = await _localPath;
          final ext = currentTask.quality == 'flac' ||
                  currentTask.quality == 'flac24bit'
              ? 'flac'
              : 'mp3';
          final fileName =
              '${currentTask.music.id}_${currentTask.quality}.$ext';
          final filePath = '$downloadDir/$fileName';
          // 清理上次失败/取消残留的部分文件
          final partialFile = File(filePath);
          if (await partialFile.exists()) {
            await partialFile.delete();
          }

          final cancelToken = CancelToken();
          _cancelTokens[currentTask.music.id] = cancelToken;

          await _dio.download(
            currentTask.music.songUrl ?? '',
            filePath,
            cancelToken: cancelToken,
            onReceiveProgress: (received, total) {
              if (total != -1) {
                currentTask.progress = (received / total * 100).toInt();
                _scheduleQueueSave(queue);
                _emitTask(currentTask);
              }
            },
          );
          _cancelTokens.remove(currentTask.music.id);

          currentTask.status = DownloadStatus.completed;
          currentTask.filePath = filePath;
          currentTask.progress = 100;
          await _saveDownloadQueue(queue);
          _emitTask(currentTask);

          final downloadedSongs = await getDownloadedSongs();
          final updatedMusic = currentTask.music.copyWith(songUrl: filePath);
          downloadedSongs.removeWhere((s) => s.id == updatedMusic.id);
          downloadedSongs.add(updatedMusic);
          await _saveDownloadedSongs(downloadedSongs);

          // 即时追加到本地音乐库（无需等待刷新）
          LocalMusicService().addDownloadedFile(updatedMusic);
          // 成功后 while 循环继续处理下一个 pending
        } catch (e) {
          _cancelTokens.remove(currentTask.music.id);
          // 清理失败/取消残留的部分文件
          final downloadDir2 = await _localPath;
          final ext2 = currentTask.quality == 'flac' ||
                  currentTask.quality == 'flac24bit'
              ? 'flac'
              : 'mp3';
          final partialFile2 =
              File('$downloadDir2/${currentTask.music.id}_${currentTask.quality}.$ext2');
          if (await partialFile2.exists()) {
            await partialFile2.delete();
          }
          // 用户主动取消的任务已从队列移除，这里只处理真正失败的任务
          final stillExists = (await getDownloadQueue())
              .any((t) => t.music.id == currentTask.music.id);
          if (stillExists) {
            currentTask.status = DownloadStatus.failed;
            currentTask.error = e.toString();
            await _saveDownloadQueue(queue);
            _emitTask(currentTask);
          }
          // 失败后继续队列中的下一个任务（修复：失败卡死队列）
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  // 进度写盘节流（每秒一次，避免高频写 SharedPreferences）
  void _scheduleQueueSave(List<DownloadTask> queue) {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(const Duration(milliseconds: 800), () {
      _saveDownloadQueue(List<DownloadTask>.from(queue));
    });
  }

  /// 公开入口：供启动时恢复卡死任务 / 触发队列处理
  Future<void> processQueue() => _processQueue();

  Future<void> retryDownload(String musicId) async {
    final queue = await getDownloadQueue();
    final task = queue.firstWhere(
      (task) => task.music.id == musicId,
      orElse: () => throw Exception('Task not found'),
    );

    task.status = DownloadStatus.pending;
    task.progress = 0;
    task.error = null;
    await _saveDownloadQueue(queue);

    _processQueue();
  }

  Future<void> removeFromDownloadQueue(String musicId) async {
    final queue = await getDownloadQueue();
    queue.removeWhere((task) => task.music.id == musicId);
    await _saveDownloadQueue(queue);
  }

  Future<void> cancelDownload(String musicId) async {
    // 用 CancelToken 取消当前请求（之前用 _dio.close() 会永久杀死单例 Dio）
    _cancelTokens[musicId]?.cancel('user cancelled');
    _cancelTokens.remove(musicId);

    final queue = await getDownloadQueue();
    queue.removeWhere((task) => task.music.id == musicId);
    await _saveDownloadQueue(queue);
  }

  Future<void> deleteDownloadedSong(MusicInfo music) async {
    final downloadedSongs = await getDownloadedSongs();
    downloadedSongs.removeWhere((song) => song.id == music.id);
    await _saveDownloadedSongs(downloadedSongs);

    if (music.songUrl != null) {
      final file = File(music.songUrl!);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<bool> isDownloaded(String musicId) async {
    final downloadedSongs = await getDownloadedSongs();
    return downloadedSongs.any((song) => song.id == musicId);
  }

  Future<String?> getLocalPath(String musicId) async {
    final downloadedSongs = await getDownloadedSongs();
    final song = downloadedSongs.firstWhere(
      (song) => song.id == musicId,
      orElse: () => throw Exception('Song not found'),
    );
    return song.songUrl;
  }
}

enum DownloadStatus {
  pending,
  downloading,
  completed,
  failed,
}

class DownloadTask {
  final MusicInfo music;
  final String quality;
  DownloadStatus status;
  int progress;
  String? filePath;
  String? error;
  final DateTime addedTime;

  DownloadTask({
    required this.music,
    required this.quality,
    required this.status,
    required this.progress,
    this.filePath,
    this.error,
    required this.addedTime,
  });

  // 修复：之前用 '|' 拼接（用户文本含 | 会解析崩溃），改用 JSON
  String toJson() {
    return jsonEncode({
      'music': music.toJson(),
      'quality': quality,
      'status': status.index,
      'progress': progress,
      'filePath': filePath,
      'error': error,
      'addedTime': addedTime.toIso8601String(),
    });
  }

  factory DownloadTask.fromJson(String json) {
    final map = Map<String, dynamic>.from(jsonDecode(json) as Map);
    return DownloadTask(
      music: MusicInfo.fromJson(
          Map<String, dynamic>.from(map['music'] as Map)),
      quality: map['quality']?.toString() ?? '320',
      status: DownloadStatus.values[(map['status'] as int?) ?? 0],
      progress: (map['progress'] as int?) ?? 0,
      filePath: map['filePath']?.toString(),
      error: map['error']?.toString(),
      addedTime: map['addedTime'] != null
          ? DateTime.tryParse(map['addedTime'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
