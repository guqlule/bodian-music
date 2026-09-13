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
}

class DownloadNotifier extends StateNotifier<DownloadState> {
  final DownloadService _downloadService;

  DownloadNotifier(this._downloadService) : super(DownloadState()) {
    _loadData();
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
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> download(MusicInfo music, {String quality = '320'}) async {
    await _downloadService.addToDownloadQueue(music, quality: quality);
    await _loadData();
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

  Future<bool> isDownloaded(String musicId) async {
    return await _downloadService.isDownloaded(musicId);
  }

  Future<void> refresh() async {
    await _loadData();
  }
}

final downloadProvider = StateNotifierProvider<DownloadNotifier, DownloadState>((ref) {
  final downloadService = ref.watch(downloadServiceProvider);
  return DownloadNotifier(downloadService);
});
