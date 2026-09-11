import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('隐私协议'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildSection('更新日期', '2024年1月1日'),
          _buildSection('生效日期', '2024年1月1日'),
          const SizedBox(height: 16),
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('一、产品定位', style: _titleStyle),
                const SizedBox(height: 8),
                Text(
                  '波点音乐是一款开源的本地音乐播放器工具，仅提供音频文件的本地播放功能。本应用不提供任何在线音乐内容的存储、上传、下载或分发服务。',
                  style: _bodyStyle,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('二、数据收集', style: _titleStyle),
                const SizedBox(height: 8),
                Text(
                  '本应用不收集任何用户个人信息。应用运行所需的数据（如播放列表、收藏记录、搜索历史）均仅存储在用户设备本地，不会上传至任何服务器。',
                  style: _bodyStyle,
                ),
                const SizedBox(height: 8),
                Text('本应用不会：', style: _bodyStyle),
                _buildBullet('收集设备标识信息（IMEI、OAID、序列号等）'),
                _buildBullet('获取用户位置信息'),
                _buildBullet('读取通讯录、短信等隐私数据'),
                _buildBullet('使用第三方统计或广告 SDK'),
                _buildBullet('将任何用户数据传输至外部服务器'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('三、网络访问', style: _titleStyle),
                const SizedBox(height: 8),
                Text(
                  '本应用的网络访问仅用于以下用途：',
                  style: _bodyStyle,
                ),
                _buildBullet('获取用户自行导入的在线播放源脚本所请求的数据'),
                _buildBullet('获取专辑封面、歌词等媒体元数据'),
                Text(
                  '上述网络请求的目标服务器、请求内容均由用户自行配置的播放源脚本决定，与本应用开发者无关。',
                  style: _bodyStyle,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('四、第三方服务', style: _titleStyle),
                const SizedBox(height: 8),
                Text(
                  '本应用不集成任何第三方服务（包括但不限于广告平台、数据分析平台、推送服务）。用户自行导入的第三方脚本不受本应用开发者控制，其数据处理行为由对应脚本作者负责。',
                  style: _bodyStyle,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('五、免责声明', style: _titleStyle),
                const SizedBox(height: 8),
                Text(
                  '本应用为开源工具，仅供学习交流使用。用户通过自行导入的在线播放源脚本获取的内容，其合法性及版权责任由用户自行承担。本应用开发者不参与、不鼓励、不担保任何通过第三方脚本获取的内容的合法性。',
                  style: _bodyStyle,
                ),
                const SizedBox(height: 8),
                Text(
                  '用户使用本应用即视为已阅读并理解本协议，并自行承担使用本应用产生的一切风险与责任。',
                  style: _bodyStyle,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('六、未成年人使用', style: _titleStyle),
                const SizedBox(height: 8),
                Text(
                  '本应用不针对未满 14 周岁的未成年人提供服务。若未成年人使用本应用，应在监护人指导下进行。',
                  style: _bodyStyle,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('七、协议更新', style: _titleStyle),
                const SizedBox(height: 8),
                Text(
                  '本协议可能会不定期更新。更新后的协议将在应用内发布，继续使用本应用即视为接受更新后的协议。',
                  style: _bodyStyle,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Center(child: Text('波点音乐 · 隐私协议', style: TextStyle(
            fontSize: 12, color: AppColors.textHint))),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  static final _titleStyle = TextStyle(
    fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
  static final _bodyStyle = TextStyle(
    fontSize: 13, color: AppColors.textSecondary, height: 1.7);

  Widget _buildSection(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text('$label：', style: TextStyle(fontSize: 13, color: AppColors.textHint)),
          Text(value, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppNeumorphic.soft,
      ),
      child: child,
    );
  }

  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: TextStyle(fontSize: 13, color: AppColors.primary)),
          Expanded(child: Text(text, style: _bodyStyle)),
        ],
      ),
    );
  }
}
