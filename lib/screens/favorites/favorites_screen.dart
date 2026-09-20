import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/music_model.dart';
import '../../providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../services/player/player_service.dart' show PlayMode;

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(favoritesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('我喜欢 (${favorites.length})'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (favorites.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.shuffle_rounded, size: 20),
              tooltip: '随机播放',
              onPressed: _shuffle,
            ),
            IconButton(
              icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
              tooltip: '播放全部',
              onPressed: _playAll,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              tooltip: '清空',
              onPressed: () => _showClearDialog(),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: favorites.isEmpty ? _buildEmpty() : _buildList(favorites),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.primarySoftColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppNeumorphic.soft,
            ),
            child: Icon(Icons.favorite_rounded, size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          Text('暂无收藏', style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
          const SizedBox(height: 8),
          Text('在搜索结果菜单中点击"我喜欢"收藏', style: TextStyle(
            color: AppColors.textHint, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildList(List<MusicInfo> favorites) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final song = favorites[index];
        return Dismissible(
          key: Key('fav_${song.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22),
                SizedBox(height: 2),
                Text('移除', style: TextStyle(color: Colors.white, fontSize: 11)),
              ],
            ),
          ),
          onDismissed: (_) {
            final removed = song;
            ref.read(favoritesProvider.notifier).removeFavorite(song.id);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('已移除「${song.name}」'),
              action: SnackBarAction(
                label: '撤销',
                onPressed: () {
                  ref.read(favoritesProvider.notifier).addFavorite(removed);
                },
              ),
            ));
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppNeumorphic.flat,
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: song.imgUrl != null
                    ? Image.network(song.imgUrl!, cacheWidth: 88, width: 44, height: 44,
                        fit: BoxFit.cover, errorBuilder: (_, __, ___) => _thumb())
                    : _thumb(),
              ),
              title: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              subtitle: Text(song.singer, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              trailing: IconButton(
                icon: Icon(Icons.more_vert_rounded, color: AppColors.textHint, size: 20),
                onPressed: () => _showSongActions(context, song, index),
              ),
              onTap: () {
                final playerService = ref.read(playerServiceProvider);
                playerService.setPlaylist(favorites, startIndex: index);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _thumb() {
    return Container(
      width: 44, height: 44,
      color: AppColors.primarySoftColor,
      child: Icon(Icons.music_note_rounded, color: AppColors.primary, size: 20),
    );
  }

  void _playAll() async {
    final favorites = ref.read(favoritesProvider);
    if (favorites.isEmpty) return;
    await ref.read(playerServiceProvider).setPlaylist(favorites);
  }

  void _shuffle() async {
    final favorites = ref.read(favoritesProvider);
    if (favorites.isEmpty) return;
    final playerService = ref.read(playerServiceProvider);
    await playerService.setPlayMode(PlayMode.random);
    await playerService.setPlaylist(favorites);
    await playerService.playMusic(favorites.first);
  }

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('清空收藏', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Text('确定要清空我的收藏吗？',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              ref.read(favoritesProvider.notifier).clearFavorites();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('收藏已清空')),
              );
            },
            child: Text('清空', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _showSongActions(BuildContext context, MusicInfo song, int index) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(song.name,
                  style:
                      TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: Icon(Icons.play_arrow_rounded, color: AppColors.primary, size: 20),
              title: Text('从这首播放', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              onTap: () {
                Navigator.pop(sheetContext);
                final favorites = ref.read(favoritesProvider);
                ref.read(playerServiceProvider).setPlaylist(favorites, startIndex: index);
              },
            ),
            ListTile(
              leading: Icon(Icons.favorite_rounded, color: AppColors.error, size: 20),
              title: Text('取消喜欢', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              onTap: () {
                Navigator.pop(sheetContext);
                ref.read(favoritesProvider.notifier).removeFavorite(song.id);
                messenger?.showSnackBar(SnackBar(
                    content: Text('已取消喜欢「${song.name}」')));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
