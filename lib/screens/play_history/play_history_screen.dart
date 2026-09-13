import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../models/music_model.dart';

class PlayHistoryScreen extends ConsumerWidget {
  const PlayHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(playHistoryProvider).valueOrNull ?? [];
    final currentMusicId = ref.watch(currentMusicProvider.select((v) => v.valueOrNull?.id));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('播放历史 (${history.length})'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_sweep, color: AppColors.error),
              onPressed: () => _showClearDialog(context, ref),
              tooltip: '清空历史',
            ),
        ],
      ),
      body: history.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              itemCount: history.length,
              itemBuilder: (context, index) {
                final music = history[index];
                return _buildHistoryItem(context, ref, music, index, currentMusicId);
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: AppColors.textHint),
          const SizedBox(height: 16),
          Text('暂无播放历史', style: TextStyle(
            fontSize: 18, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(
    BuildContext context,
    WidgetRef ref,
    MusicInfo music,
    int index,
    String? currentMusicId,
  ) {
    final isPlaying = currentMusicId == music.id;

    return Dismissible(
      key: Key(music.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: AppColors.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) {
        ref.read(playerServiceProvider).removeFromHistory(music.id);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        decoration: BoxDecoration(
          color: isPlaying ? AppColors.primarySoftColor : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppNeumorphic.flat,
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          leading: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: isPlaying ? AppColors.primary : AppColors.primarySoftColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: isPlaying
                ? Icon(Icons.equalizer_rounded, color: Colors.white, size: 18)
                : Center(child: Text('${index + 1}',
                    style: TextStyle(color: AppColors.primary,
                      fontSize: 13, fontWeight: FontWeight.w600))),
          ),
          title: Text(music.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isPlaying ? AppColors.primary : AppColors.textPrimary,
              fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: Text('${music.singer} · ${music.album}',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          trailing: PopupMenuButton(
            icon: Icon(Icons.more_vert_rounded, color: AppColors.textHint, size: 18),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'play', child: Text('播放')),
              const PopupMenuItem(value: 'next', child: Text('下一首播放')),
              const PopupMenuItem(value: 'add_to_playlist', child: Text('添加到播放列表')),
              const PopupMenuItem(value: 'add_to_favorite', child: Text('添加到收藏')),
              const PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
            onSelected: (value) => _handleMenuAction(context, ref, value, music),
          ),
          onTap: () {
            final playerService = ref.read(playerServiceProvider);
            final history = ref.read(playHistoryProvider).valueOrNull ?? [];
            playerService.setPlaylist(history, startIndex: index);
          },
        ),
      ),
    );
  }

  void _handleMenuAction(BuildContext context, WidgetRef ref, String action, MusicInfo music) {
    final playerService = ref.read(playerServiceProvider);

    switch (action) {
      case 'play':
        final history = ref.read(playHistoryProvider).valueOrNull ?? [];
        final idx = history.indexOf(music);
        if (idx >= 0) playerService.setPlaylist(history, startIndex: idx);
        break;
      case 'next':
        playerService.addToTempPlaylist([music]);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已添加到下一首播放')));
        break;
      case 'add_to_playlist':
        _showAddToPlaylistDialog(context, ref, music);
        break;
      case 'add_to_favorite':
        ref.read(favoritesProvider.notifier).addFavorite(music);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已添加到收藏')));
        break;
      case 'delete':
        playerService.removeFromHistory(music.id);
        break;
    }
  }

  void _showAddToPlaylistDialog(BuildContext context, WidgetRef ref, MusicInfo music) {
    final playlists = ref.read(playlistProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('添加到播放列表', style: TextStyle(color: AppColors.textPrimary)),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return ListTile(
                leading: Icon(Icons.queue_music_rounded, color: AppColors.primary, size: 20),
                title: Text(playlist.name, style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                subtitle: Text('${playlist.songs.length}首歌曲',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                onTap: () {
                  ref.read(playlistProvider.notifier).addToPlaylist(playlist.id, music);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已添加到${playlist.name}')));
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: AppColors.textSecondary))),
        ],
      ),
    );
  }

  void _showClearDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('清空播放历史', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('确定要清空所有播放历史吗？',
          style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: AppColors.textSecondary))),
          TextButton(onPressed: () {
            ref.read(playerServiceProvider).clearPlayHistory();
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已清空播放历史')));
          }, child: Text('确定', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
  }
}
