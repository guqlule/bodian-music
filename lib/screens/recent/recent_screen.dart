import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/music_model.dart';
import '../../providers/app_providers.dart';
import '../../core/theme/app_theme.dart';

class RecentScreen extends ConsumerStatefulWidget {
  const RecentScreen({super.key});

  @override
  ConsumerState<RecentScreen> createState() => _RecentScreenState();
}

class _RecentScreenState extends ConsumerState<RecentScreen> {
  @override
  Widget build(BuildContext context) {
    final recent = ref.watch(recentPlayedProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('最近播放 (${recent.length})'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (recent.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: GestureDetector(
                onTap: _showClearDialog,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.delete_outline_rounded,
                      color: AppColors.textSecondary, size: 18),
                ),
              ),
            ),
        ],
      ),
      body: recent.isEmpty ? _buildEmpty() : _buildList(recent),
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
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppNeumorphic.soft,
            ),
            child: Icon(Icons.history_rounded, size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          Text('暂无播放记录', style: TextStyle(
            color: AppColors.textSecondary, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildList(List<MusicInfo> recent) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: recent.length,
      itemBuilder: (context, index) {
        final song = recent[index];
        return Container(
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
              icon: Icon(Icons.delete_outline_rounded,
                  color: AppColors.textHint, size: 20),
              onPressed: () {
                ref.read(recentPlayedProvider.notifier).removeFromRecent(song.id);
              },
            ),
            onTap: () {
              final playerService = ref.read(playerServiceProvider);
              playerService.setPlaylist(recent, startIndex: index);
            },
          ),
        );
      },
    );
  }

  Widget _thumb() {
    return Container(
      width: 44, height: 44,
      color: AppColors.primarySoft,
      child: Icon(Icons.music_note_rounded, color: AppColors.primary, size: 20),
    );
  }

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('清空历史',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Text('确定要清空播放历史吗？',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              ref.read(recentPlayedProvider.notifier).clearRecent();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('历史已清空')),
              );
            },
            child: Text('清空', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
