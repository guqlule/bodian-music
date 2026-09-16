import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../models/music_model.dart';
import '../../providers/app_providers.dart';

/// 迷你播放器 —— 底部悬浮条，显示当前播放歌曲信息和基本控制
/// 在搜索、设置、歌单等子页面底部自动显示
///
/// 性能优化：进度条使用独立的 _MiniProgressBar 子组件（只监听 position）
/// 主 widget 只在歌曲/播放状态变化时重建，不再每200ms重建一次
class MiniPlayer extends ConsumerWidget {
  final VoidCallback? onTap;

  const MiniPlayer({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final music = ref.watch(currentMusicProvider).valueOrNull;
    if (music == null) return const SizedBox.shrink();

    final isPlaying = ref.watch(isPlayingProvider).valueOrNull ?? false;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.card,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          children: [
            // 进度条：独立组件，只在 position/duration 变化时重建
            const _MiniProgressBar(),
            // 内容
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    // 封面
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primarySoftColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: music.imgUrl != null && music.imgUrl!.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: _buildCover(music),
                            )
                          : Icon(Icons.music_note_rounded, color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    // 歌曲信息
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(music.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppColors.textPrimary,
                              fontSize: 13, fontWeight: FontWeight.w500)),
                          Text(music.singer,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        ],
                      ),
                    ),
                    // 控制按钮
                    IconButton(
                      icon: Icon(Icons.skip_previous_rounded, color: AppColors.textPrimary, size: 24),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32),
                      onPressed: () => ref.read(playerServiceProvider).playPrevious(),
                    ),
                    IconButton(
                      icon: Icon(
                        isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        color: AppColors.primary, size: 36),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 40),
                      onPressed: () {
                        final player = ref.read(playerServiceProvider);
                        if (isPlaying) {
                          player.pause();
                        } else {
                          player.play();
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.skip_next_rounded, color: AppColors.textPrimary, size: 24),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32),
                      onPressed: () => ref.read(playerServiceProvider).playNext(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(MusicInfo music) {
    if (music.source == 'local' && music.imgUrl != null) {
      return Image.asset(
        music.imgUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackIcon(),
      );
    }
    return Image.network(
      music.imgUrl!,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _fallbackIcon(),
    );
  }

  Widget _fallbackIcon() {
    return Container(
      color: AppColors.primarySoftColor,
      child: Icon(Icons.music_note_rounded, color: AppColors.primary, size: 20),
    );
  }
}

/// 独立的迷你进度条组件 ——使用 ref.listen + setState 局部更新
/// 不再随主 MiniPlayer 每200ms rebuild 整个封面/歌名/控制按钮树
class _MiniProgressBar extends ConsumerStatefulWidget {
  const _MiniProgressBar();

  @override
  ConsumerState<_MiniProgressBar> createState() => _MiniProgressBarState();
}

class _MiniProgressBarState extends ConsumerState<_MiniProgressBar> {
  // 仅用 ref.watch 触发重建，移除冗余的 ref.listen + setState
  @override
  Widget build(BuildContext context) {
    final pos = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final dur = ref.watch(durationProvider).valueOrNull;
    final value = (dur != null && dur.inMilliseconds > 0)
        ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return LinearProgressIndicator(
      value: value,
      minHeight: 2,
      backgroundColor: AppColors.divider,
      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
    );
  }
}
