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
  double? _scrub;

  @override
  Widget build(BuildContext context) {
    final pos = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final dur = ref.watch(durationProvider).valueOrNull;
    final buffered = ref.watch(bufferedProvider).valueOrNull ?? Duration.zero;

    final maxMs = (dur?.inMilliseconds ?? 0).clamp(0, 1000000000).toDouble();
    final scrubbing = _scrub != null;
    final activeMs = (scrubbing ? _scrub! : pos.inMilliseconds.toDouble()).clamp(0.0, maxMs);
    final bufferedMs = buffered.inMilliseconds.toDouble().clamp(0.0, maxMs);
    final activeRatio = maxMs > 0 ? activeMs / maxMs : 0.0;
    final bufferedRatio = maxMs > 0 ? (bufferedMs / maxMs).clamp(0.0, 1.0) : 0.0;

    if (maxMs <= 0) {
      return const SizedBox(height: 4);
    }

    return SizedBox(
      height: 24,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          // 迷你进度条轨道几何：高度 24，轨道居中。
          // 用极小 thumb（1.5）让轨道看起来像细进度条，仍可拖动。
          const trackH = 3.0;
          const thumbR = 4.0;
          final inset = thumbR;
          final trackCenterY = (24.0 - trackH) / 2;

          return Stack(
            children: [
              // 缓冲段（浅主色）
              Positioned.fill(
                child: CustomPaint(
                  painter: _MiniBufferedPainter(
                    activeRatio: activeRatio,
                    bufferedRatio: bufferedRatio,
                    inset: inset,
                    trackH: trackH,
                    trackCenterY: trackCenterY,
                    color: AppColors.primary.withValues(alpha: 0.25),
                  ),
                ),
              ),
              // 可拖动 Slider
              Positioned.fill(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: AppColors.divider,
                    thumbColor: AppColors.card,
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: thumbR, elevation: 1),
                    overlayShape: RoundSliderOverlayShape(overlayRadius: thumbR),
                    trackHeight: trackH,
                    overlayColor: AppColors.primarySoftColor,
                  ),
                  child: Slider(
                    value: activeMs,
                    max: maxMs,
                    onChanged: (v) {
                      _scrub = v.clamp(0.0, maxMs);
                      setState(() {});
                    },
                    onChangeEnd: (v) {
                      _scrub = null;
                      ref.read(playerServiceProvider).seek(Duration(milliseconds: v.toInt()));
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 迷你进度条的缓冲段 painter（几何与 Slider 对齐）
class _MiniBufferedPainter extends CustomPainter {
  final double activeRatio;
  final double bufferedRatio;
  final double inset;
  final double trackH;
  final double trackCenterY;
  final Color color;

  _MiniBufferedPainter({
    required this.activeRatio,
    required this.bufferedRatio,
    required this.inset,
    required this.trackH,
    required this.trackCenterY,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bufferedRatio <= activeRatio) return;
    final usableW = (size.width - inset * 2).clamp(0.0, size.width);
    final startX = inset + usableW * activeRatio;
    final endX = inset + usableW * bufferedRatio;
    final rect = Rect.fromLTRB(
      startX,
      trackCenterY - trackH / 2,
      endX,
      trackCenterY + trackH / 2,
    );
    final paint = Paint()..color = color;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(trackH / 2)), paint);
  }

  @override
  bool shouldRepaint(covariant _MiniBufferedPainter old) =>
      old.activeRatio != activeRatio ||
      old.bufferedRatio != bufferedRatio ||
      old.color != color ||
      old.inset != inset ||
      old.trackH != trackH ||
      old.trackCenterY != trackCenterY;
}
