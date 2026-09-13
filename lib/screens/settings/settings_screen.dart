import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/settings_provider.dart';
import '../../services/player/player_service.dart';
import '../../core/storage/storage_service.dart';
import '../../core/theme/app_theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 外观设置卡片
          _buildSectionCard(
            title: '外观',
            children: [
              _buildSwitchTile(
                icon: Icons.dark_mode_rounded,
                title: '深色模式',
                subtitle: '切换深色/浅色主题',
                value: settings.isDarkMode,
                onChanged: (value) => settingsNotifier.setDarkMode(value),
              ),
              const _Divider(),
              _buildTapTile(
                icon: Icons.text_fields_rounded,
                title: '字体大小',
                subtitle: '${settings.fontSize.toStringAsFixed(0)} sp',
                onTap: () => _showFontSizeDialog(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 播放设置卡片
          _buildSectionCard(
            title: '播放',
            children: [
              _buildTapTile(
                icon: Icons.equalizer_rounded,
                title: '音质选择',
                subtitle: _qualityLabel(settings.quality),
                onTap: () => _showQualityDialog(context, ref),
              ),
              const _Divider(),
              _buildSwitchTile(
                icon: Icons.sync_rounded,
                title: '无缝播放',
                subtitle: '预取下一首，切歌更流畅',
                value: settings.gaplessPlayback,
                onChanged: (value) {
                  settingsNotifier.setGaplessPlayback(value);
                  PlayerService.instance.setPrefetchEnabled(value);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 播放源卡片
          _buildSectionCard(
            title: '播放源',
            children: [
              _buildTapTile(
                icon: Icons.code_rounded,
                title: '自定义源',
                subtitle: '管理音源脚本',
                onTap: () => context.push('/user-api'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 存储设置卡片
          _buildSectionCard(
            title: '存储',
            children: [
              _buildTapTile(
                icon: Icons.cleaning_services_rounded,
                title: '清除缓存',
                subtitle: '清除临时文件',
                onTap: () => _showClearCacheDialog(context),
              ),
              const _Divider(),
              _buildTapTile(
                icon: Icons.download_rounded,
                title: '下载管理',
                subtitle: '查看已下载的歌曲',
                onTap: () => context.push('/download'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 关于卡片
          _buildSectionCard(
            title: '关于',
            children: [
              _buildTapTile(
                icon: Icons.info_outline_rounded,
                title: '版本',
                subtitle: 'v1.0.0',
                onTap: () {},
              ),
              const _Divider(),
              _buildTapTile(
                icon: Icons.code_rounded,
                title: '开源许可',
                onTap: () {
                  showLicensePage(
                    context: context,
                    applicationName: '波点音乐',
                    applicationVersion: '1.0.0',
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppNeumorphic.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(title, style: TextStyle(
              color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.textSecondary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(
                  color: AppColors.textHint, fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
            activeTrackColor: AppColors.primaryLight,
            inactiveTrackColor: AppColors.divider,
          ),
        ],
      ),
    );
  }

  Widget _buildTapTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.textSecondary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(
                      color: AppColors.textHint, fontSize: 11)),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 20),
          ],
        ),
      ),
    );
  }

  void _showFontSizeDialog(BuildContext context, WidgetRef ref) {
    final settings = ref.read(settingsProvider);
    double fontSize = settings.fontSize;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('字体大小'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Slider(
                  value: fontSize,
                  min: 12, max: 20, divisions: 8,
                  label: '${fontSize.toStringAsFixed(0)} sp',
                  thumbColor: AppColors.primary,
                  onChanged: (value) => setState(() => fontSize = value),
                ),
                Text('${fontSize.toStringAsFixed(0)} sp',
                  style: TextStyle(color: AppColors.textPrimary)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('取消', style: TextStyle(color: AppColors.textSecondary)),
              ),
              TextButton(
                onPressed: () {
                  ref.read(settingsProvider.notifier).setFontSize(fontSize);
                  Navigator.pop(context);
                },
                child: Text('确定', style: TextStyle(color: AppColors.primary)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showQualityDialog(BuildContext context, WidgetRef ref) {
    final settings = ref.read(settingsProvider);

    // 四档音质（对齐原版 player.playQuality：128k/320k/flac/flac24bit）
    const options = [
      ('128k', '标准', '128kbps'),
      ('320k', '高品', '320kbps MP3'),
      ('flac', '无损', 'FLAC'),
      ('flac24bit', 'Hi-Res', 'FLAC 24bit'),
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('音质选择'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((opt) => RadioListTile<String>(
              title: Text(opt.$2), subtitle: Text(opt.$3),
              value: opt.$1, groupValue: settings.quality,
              activeColor: AppColors.primary,
              onChanged: (value) {
                if (value != null) {
                  ref.read(settingsProvider.notifier).setQuality(value);
                  PlayerService.instance.setPreferredQuality(value);
                  Navigator.pop(context);
                }
              },
            )).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  String _qualityLabel(String quality) {
    const map = {'128k': '标准 (128k)', '320k': '高品 (320k)', 'flac': '无损 (FLAC)', 'flac24bit': 'Hi-Res (FLAC 24bit)'};
    return map[quality] ?? quality;
  }

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('确定要清除所有缓存吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // 接通真实缓存清理（之前只弹提示）
              await StorageService().clearCache();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('缓存已清除')),
                );
              }
            },
            child: Text('确定', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, color: AppColors.divider),
    );
  }
}
