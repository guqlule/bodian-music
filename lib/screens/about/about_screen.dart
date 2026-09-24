import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import 'privacy_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('关于'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 32),
          // App Icon - 孟菲斯风
          Center(
            child: Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                color: AppColors.primarySoftColor,
                borderRadius: BorderRadius.circular(28),
                boxShadow: AppNeumorphic.light,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 12, right: 12,
                    child: Container(width: 16, height: 16, decoration: BoxDecoration(
                      color: AppColors.accent1.withValues(alpha: 0.5), shape: BoxShape.circle)),
                  ),
                  Positioned(
                    bottom: 16, left: 16,
                    child: Container(width: 12, height: 12, decoration: BoxDecoration(
                      color: AppColors.accent2.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4))),
                  ),
                  Icon(Icons.music_note_rounded, size: 48, color: AppColors.primary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(child: Text('波点音乐', style: TextStyle(
            fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary))),
          const SizedBox(height: 8),
          Center(child: Text('v1.0.0', style: TextStyle(
            fontSize: 14, color: AppColors.textSecondary))),
          const SizedBox(height: 32),
          // 描述卡片
          _buildCard(
            child: Text('波点音乐是一款基于 Flutter 的跨平台音乐播放器应用，支持多源搜索、歌词显示、下载管理等功能。',
              style: TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.6)),
          ),
          const SizedBox(height: 16),
          // 功能卡片
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('主要功能', style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                _FeatureItem(icon: Icons.search_rounded, text: '多源音乐搜索'),
                _FeatureItem(icon: Icons.leaderboard_rounded, text: '排行榜浏览'),
                _FeatureItem(icon: Icons.favorite_rounded, text: '收藏管理'),
                _FeatureItem(icon: Icons.download_rounded, text: '下载管理'),
                _FeatureItem(icon: Icons.lyrics_rounded, text: '歌词显示'),
                _FeatureItem(icon: Icons.queue_music_rounded, text: '播放列表管理'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 链接卡片
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('相关链接', style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                ListTile(
                  leading: Icon(Icons.code_rounded, color: AppColors.primary),
                  title: Text('GitHub', style: TextStyle(color: AppColors.textPrimary)),
                  subtitle: Text('查看源代码', style: TextStyle(color: AppColors.textSecondary)),
                  contentPadding: EdgeInsets.zero,
                  trailing: Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
                  onTap: () => launchUrl(
                    Uri.parse('https://github.com/guqlule/bodian-music'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.bug_report_rounded, color: AppColors.primary),
                  title: Text('问题反馈', style: TextStyle(color: AppColors.textPrimary)),
                  subtitle: Text('报告 Bug 或提出建议', style: TextStyle(color: AppColors.textSecondary)),
                  contentPadding: EdgeInsets.zero,
                  trailing: Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
                  onTap: () => launchUrl(
                    Uri.parse('https://github.com/guqlule/bodian-music/issues'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.privacy_tip_rounded, color: AppColors.primary),
                  title: Text('隐私协议', style: TextStyle(color: AppColors.textPrimary)),
                  subtitle: Text('查看隐私政策和免责声明', style: TextStyle(color: AppColors.textSecondary)),
                  contentPadding: EdgeInsets.zero,
                  trailing: Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PrivacyScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(child: Text('© 2024 波点音乐', style: TextStyle(
            fontSize: 12, color: AppColors.textHint))),
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppNeumorphic.soft,
      ),
      child: child,
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FeatureItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: AppColors.primarySoftColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Text(text, style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
        ],
      ),
    );
  }
}
