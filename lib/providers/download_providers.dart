import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/music_model.dart';
import '../../services/download/download_service.dart';

final downloadServiceProvider = Provider<DownloadService>((ref) {
  return DownloadService();
});

class DownloadState {
  final List<DownloadTask> queue;
  final List<MusicInfo> downloadedSongs;
  final bool isLoading;
  final String? error;

  DownloadState({
    this.queue = const [],
    this.downloadedSongs = const [],
    this.isLoading = false,
    this.error,
  });

  DownloadState copyWith({
    List<DownloadTask>? queue,
    List<MusicInfo>? downloadedSongs,
    bool? isLoading,
    String? error,
  }) {
    return DownloadState(
      queue: queue ?? this.queue,
      downloadedSongs: downloadedSongs ?? this.downloadedSongs,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  int get downloadingCount => queue.where(
    (task) => task.status == DownloadStatus.downloading || task.status == DownloadStatus.pending,
  ).length;

  int get completedCount => queue.where(
    (task) => task.status == DownloadStatus.completed,
  ).length;

  int get failedCount => queue.where(
    (task) => task.status == DownloadStatus.failed,
  ).length;

  /// 判断某首歌是否已下载完成（用于菜单 badge）
  bool isDownloaded(String musicId) =>
      downloadedSongs.any((s) => s.id == musicId);
}

class DownloadNotifier extends StateNotifier<DownloadState> {
  final DownloadService _downloadService;
  late StreamSubscription _taskSub;

  DownloadNotifier(this._downloadService) : super(DownloadState()) {
    _loadData();
    // 监听实时进度流，每个任务状态/进度变化自动刷新 state
    _taskSub = _downloadService.taskStream.listen((task) {
      // 更新当前队列中该任务的状态（只更新 status/progress，不重新读 SharedPreferences）
      final queue = List<DownloadTask>.from(state.queue);
      final idx = queue.indexWhere((t) => t.music.id == task.music.id);
      if (idx >= 0) {
        queue[idx] = task;
        state = state.copyWith(queue: queue);
      }
      // 完成的任务同步到 downloadedSongs
      if (task.status == DownloadStatus.completed) {
        final updatedMusic = task.music.copyWith(songUrl: task.filePath);
        final downloaded = List<MusicInfo>.from(state.downloadedSongs);
        downloaded.removeWhere((s) => s.id == updatedMusic.id);
        downloaded.add(updatedMusic);
        state = state.copyWith(downloadedSongs: downloaded);
      }
    });
  }

  @override
  void dispose() {
    _taskSub.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    state = state.copyWith(isLoading: true);
    try {
      final queue = await _downloadService.getDownloadQueue();
      final downloaded = await _downloadService.getDownloadedSongs();
      state = state.copyWith(
        queue: queue,
        downloadedSongs: downloaded,
        isLoading: false,
      );
      // 启动时恢复卡死的 downloading 任务（上次进程被杀）
      _downloadService.processQueue();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> download(MusicInfo music, {String quality = '320'}) async {
    await _downloadService.addToDownloadQueue(music, quality: quality);
    final q = await _downloadService.getDownloadQueue();
    final d = await _downloadService.getDownloadedSongs();
    state = state.copyWith(queue: q, downloadedSongs: d);
  }

  Future<void> retry(String musicId) async {
    await _downloadService.retryDownload(musicId);
    await _loadData();
  }

  Future<void> remove(String musicId) async {
    await _downloadService.removeFromDownloadQueue(musicId);
    await _loadData();
  }

  Future<void> cancel(String musicId) async {
    await _downloadService.cancelDownload(musicId);
    await _loadData();
  }

  Future<void> deleteDownloaded(MusicInfo music) async {
    await _downloadService.deleteDownloadedSong(music);
    await _loadData();
  }

  Future<void> refresh() async {
    await _loadData();
  }
}

final downloadProvider = StateNotifierProvider<DownloadNotifier, DownloadState>((ref) {
  final downloadService = ref.watch(downloadServiceProvider);
  return DownloadNotifier(downloadService);
});
