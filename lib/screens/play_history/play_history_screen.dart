import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_providers.dart';
import '../../models/music_model.dart';

class PlayHistoryScreen extends ConsumerWidget {
  const PlayHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(playHistoryProvider).valueOrNull ?? [];
    // 在列表级别 watch currentMusicProvider，避免每个列表项都 watch
    final currentMusicId = ref.watch(currentMusicProvider.select((v) => v.valueOrNull?.id));

    return Scaffold(
      appBar: AppBar(
        title: Text('播放历史 (${history.length})'),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: () => _showClearDialog(context, ref),
              tooltip: '清空历史',
            ),
        ],
      ),
      body: history.isEmpty
          ? _buildEmptyState(context)
          : ListView.builder(
              itemCount: history.length,
              itemBuilder: (context, index) {
                final music = history[index];
                return _buildHistoryItem(context, ref, music, index, currentMusicId);
              },
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: color),
          const SizedBox(height: 16),
          Text(
            '暂无播放历史',
            style: TextStyle(fontSize: 18, color: color),
          ),
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
        color: Colors.red,
        child: const Icon(
          Icons.delete,
          color: Colors.white,
        ),
      ),
      onDismissed: (direction) {
        ref.read(playerServiceProvider).removeFromHistory(music.id);
      },
      child: ListTile(
        leading: isPlaying
            ? Icon(
                Icons.equalizer,
                color: Theme.of(context).colorScheme.primary,
              )
            : CircleAvatar(
                child: Text('${index + 1}'),
              ),
        title: Text(
          music.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isPlaying ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
        subtitle: Text(
          '${music.singer} - ${music.album}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'play',
              child: Text('播放'),
            ),
            const PopupMenuItem(
              value: 'next',
              child: Text('下一首播放'),
            ),
            const PopupMenuItem(
              value: 'add_to_playlist',
              child: Text('添加到播放列表'),
            ),
            const PopupMenuItem(
              value: 'add_to_favorite',
              child: Text('添加到收藏'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('删除'),
            ),
          ],
          onSelected: (value) => _handleMenuAction(context, ref, value, music),
        ),
        onTap: () {
          final playerService = ref.read(playerServiceProvider);
          // 历史列表 ≠ 当前播放队列，必须用 setPlaylist 从该首开始播（之前 playIndex 用队列索引会放错歌）
          final history = ref.read(playHistoryProvider).valueOrNull ?? [];
          playerService.setPlaylist(history, startIndex: index);
        },
      ),
    );
  }

  void _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    MusicInfo music,
  ) {
    final playerService = ref.read(playerServiceProvider);

    switch (action) {
      case 'play':
        // 同上：历史列表 ≠ 播放队列，用 setPlaylist
        final history = ref.read(playHistoryProvider).valueOrNull ?? [];
        final idx = history.indexOf(music);
        if (idx >= 0) {
          playerService.setPlaylist(history, startIndex: idx);
        }
        break;
      case 'next':
        playerService.addToTempPlaylist([music]);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已添加到下一首播放')),
        );
        break;
      case 'add_to_playlist':
        _showAddToPlaylistDialog(context, ref, music);
        break;
      case 'add_to_favorite':
        ref.read(favoritesProvider.notifier).addFavorite(music);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已添加到收藏')),
        );
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
        title: const Text('添加到播放列表'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return ListTile(
                leading: const Icon(Icons.queue_music),
                title: Text(playlist.name),
                subtitle: Text('${playlist.songs.length}首歌曲'),
                onTap: () {
                  ref.read(playlistProvider.notifier).addToPlaylist(playlist.id, music);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已添加到${playlist.name}')),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _showClearDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空播放历史'),
        content: const Text('确定要清空所有播放历史吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              ref.read(playerServiceProvider).clearPlayHistory();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已清空播放历史')),
              );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
