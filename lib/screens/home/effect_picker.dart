import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/audio_visualizer.dart';

/// 特效图标映射（供选择器和顶栏共用）
IconData effectIconFor(VisualizerEffect effect) {
  switch (effect) {
    case VisualizerEffect.bars:
      return Icons.equalizer_rounded;
    case VisualizerEffect.wave:
      return Icons.waves_rounded;
    case VisualizerEffect.circle:
      return Icons.donut_large_rounded;
    case VisualizerEffect.radial:
      return Icons.radar_rounded;
    case VisualizerEffect.mirror:
      return Icons.swap_vert_rounded;
    case VisualizerEffect.line:
      return Icons.show_chart_rounded;
    case VisualizerEffect.dot:
      return Icons.grid_on_rounded;
    case VisualizerEffect.spiral:
      return Icons.autorenew_rounded;
  }
}

/// 播放特效选择底部弹窗
void showEffectPicker(
  BuildContext context, {
  required VisualizerEffect current,
  required ValueChanged<VisualizerEffect> onSelected,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    isScrollControlled: true,
    builder: (sheetContext) {
      final maxH = MediaQuery.of(context).size.height * 0.6;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('播放特效', style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: VisualizerEffect.values.length,
                    itemBuilder: (context, index) {
                      final effect = VisualizerEffect.values[index];
                      final selected = effect == current;
                      return GestureDetector(
                        onTap: () {
                          onSelected(effect);
                          Navigator.pop(sheetContext);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.primary : AppColors.card,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: selected
                                ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 8, spreadRadius: 2)]
                                : AppNeumorphic.flat,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                effectIconFor(effect),
                                color: selected ? Colors.white : AppColors.textSecondary,
                                size: 22,
                              ),
                              const SizedBox(height: 4),
                              Text(effect.label, style: TextStyle(
                                color: selected ? Colors.white : AppColors.textSecondary,
                                fontSize: 10,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                              )),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
