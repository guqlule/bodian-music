import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_providers.dart';
import '../../providers/download_providers.dart';
import '../../services/download/download_service.dart';
import '../../core/theme/app_theme.dart';

class DownloadScreen extends ConsumerStatefulWidget {
  const DownloadScreen({super.key});

  @override
  ConsumerState<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends ConsumerState<DownloadScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloadState = ref.watch(downloadProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('下载管理'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: '下载中 (${downloadState.downloadingCount})'),
            Tab(text: '已完成 (${downloadState.downloadedSongs.length})'),
          ],
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textHint,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDownloadingList(downloadState),
          _buildDownloadedList(downloadState),
        ],
      ),
    );
  }

  Widget _buildDownloadingList(DownloadState state) {
    if (state.isLoading) return Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (state.error != null) return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 64, height: 64, decoration: BoxDecoration(
          color: AppColors.surface, borderRadius: BorderRadius.circular(20), boxShadow: AppNeumorphic.soft),
          child: Icon(Icons.error_outline_rounded, size: 32, color: AppColors.error)),
        const SizedBox(height: 16), Text(state.error!, style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        GestureDetector(onTap: () => ref.read(downloadProvider.notifier).refresh(), child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), boxShadow: AppNeumorphic.soft),
          child: Text('重试', style: TextStyle(color: AppColors.primary, fontSize: 13)))),
      ]),
    );

    final downloadingTasks = state.queue.where(
      (task) => task.status == DownloadStatus.downloading || task.status == DownloadStatus.pending,
    ).toList();

    if (downloadingTasks.isEmpty) {
      return Center(child: Text('没有正在下载的任务', style: TextStyle(color: AppColors.textHint)));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: downloadingTasks.length,
      itemBuilder: (context, index) => _buildDownloadingItem(downloadingTasks[index]),
    );
  }

  Widget _buildDownloadingItem(DownloadTask task) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card, borderRadius: BorderRadius.circular(16), boxShadow: AppNeumorphic.flat),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14), color: AppColors.primarySoftColor),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: task.music.imgUrl != null
                  ? Image.network(task.music.imgUrl!, cacheWidth: 96, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _defaultThumb())
                  : _defaultThumb(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(task.music.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: task.progress / 100,
                backgroundColor: AppColors.divider,
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(4),
                minHeight: 4,
              ),
              const SizedBox(height: 4),
              Text('${task.progress}%', style: TextStyle(color: AppColors.textHint, fontSize: 11)),
            ],
          )),
          IconButton(
            icon: Icon(Icons.close_rounded, color: AppColors.textHint, size: 20),
            onPressed: () => ref.read(downloadProvider.notifier).cancel(task.music.id),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadedList(DownloadState state) {
    if (state.isLoading) return Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (state.downloadedSongs.isEmpty) {
      return Center(child: Text('没有已下载的歌曲', style: TextStyle(color: AppColors.textHint)));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: state.downloadedSongs.length,
      itemBuilder: (context, index) {
        final song = state.downloadedSongs[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppColors.card, borderRadius: BorderRadius.circular(16), boxShadow: AppNeumorphic.flat),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14), color: AppColors.primarySoftColor),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: song.imgUrl != null
                    ? Image.network(song.imgUrl!, cacheWidth: 96, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _defaultThumb())
                    : _defaultThumb(),
              ),
            ),
            title: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
            subtitle: Text('${song.singer} - ${song.album}', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            trailing: PopupMenuButton(
              icon: Icon(Icons.more_vert_rounded, color: AppColors.textHint, size: 20),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'play', child: Text('播放')),
                const PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
              onSelected: (value) {
                if (value == 'play') {
                  ref.read(playerServiceProvider).setPlaylist([song]);
                } else if (value == 'delete') {
                  // 接通删除功能（之前静默无反应）
                  ref.read(downloadProvider.notifier).deleteDownloaded(song);
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已删除「${song.name}」')));
                }
              },
            ),
          ),
        );
      },
    );
  }

  Widget _defaultThumb() {
    return Container(
      width: 48, height: 48,
      decoration: BoxDecoration(color: AppColors.primarySoftColor, borderRadius: BorderRadius.circular(14)),
      child: Icon(Icons.music_note_rounded, color: AppColors.primary, size: 22),
    );
  }
}
