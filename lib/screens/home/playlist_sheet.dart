import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/music_model.dart';
import '../../providers/app_providers.dart';
import '../../core/theme/app_theme.dart';

/// 播放列表底部弹窗（实时监听队列）
void showPlaylistSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _PlaylistSheet(),
  );
}

class _PlaylistSheet extends ConsumerStatefulWidget {
  const _PlaylistSheet();

  @override
  ConsumerState<_PlaylistSheet> createState() => _PlaylistSheetState();
}

class _PlaylistSheetState extends ConsumerState<_PlaylistSheet> {
  void _confirmClear(BuildContext sheetContext) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('清空播放列表',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Text('将移除全部歌曲并停止播放',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              ref.read(playerServiceProvider).clearPlaylist();
              Navigator.pop(dialogContext); // 关对话框
              Navigator.pop(sheetContext); // 关弹窗（列表已空）
            },
            child: Text('清空', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playlist = ref.watch(currentPlaylistProvider).valueOrNull ?? const <MusicInfo>[];
    final currentIndex = ref.watch(currentIndexProvider).valueOrNull ?? -1;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        children: [
          // 拖拽条
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Text('播放列表 (${playlist.length})', style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (playlist.isNotEmpty)
                  GestureDetector(
                    onTap: () => _confirmClear(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline_rounded,
                              color: AppColors.textSecondary, size: 14),
                          SizedBox(width: 4),
                          Text('清空', style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('关闭', style: TextStyle(color: AppColors.primary, fontSize: 12)),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.divider),
          Expanded(
            child: playlist.isEmpty
                ? Center(child: Text('暂无歌曲', style: TextStyle(color: AppColors.textHint)))
                : ListView.builder(
                    itemCount: playlist.length,
                    itemBuilder: (context, index) {
                      final song = playlist[index];
                      final isCurrent = index == currentIndex;
                      return ListTile(
                        leading: Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: isCurrent ? AppColors.primarySoft : AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text('${index + 1}', style: TextStyle(
                              color: isCurrent ? AppColors.primary : AppColors.textSecondary,
                              fontSize: 11, fontWeight: FontWeight.w500)),
                          ),
                        ),
                        title: Text(song.name, style: TextStyle(
                          color: isCurrent ? AppColors.primary : AppColors.textPrimary,
                          fontSize: 13, fontWeight: isCurrent ? FontWeight.w500 : FontWeight.normal),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(song.singer, style: TextStyle(
                          color: AppColors.textHint, fontSize: 11),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          Navigator.pop(context);
                          ref.read(playerServiceProvider).playIndex(index);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
