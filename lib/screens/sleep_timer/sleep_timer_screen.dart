import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';

class SleepTimerScreen extends ConsumerStatefulWidget {
  const SleepTimerScreen({super.key});

  @override
  ConsumerState<SleepTimerScreen> createState() => _SleepTimerScreenState();
}

class _SleepTimerScreenState extends ConsumerState<SleepTimerScreen> {
  final List<Map<String, dynamic>> _presetDurations = [
    {'label': '15分钟', 'duration': const Duration(minutes: 15)},
    {'label': '30分钟', 'duration': const Duration(minutes: 30)},
    {'label': '45分钟', 'duration': const Duration(minutes: 45)},
    {'label': '1小时', 'duration': const Duration(hours: 1)},
    {'label': '1.5小时', 'duration': const Duration(hours: 1, minutes: 30)},
    {'label': '2小时', 'duration': const Duration(hours: 2)},
  ];

  @override
  Widget build(BuildContext context) {
    final isActive = ref.watch(sleepTimerActiveProvider).valueOrNull ?? false;
    final remaining = ref.watch(sleepTimerRemainingProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('定时退出'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isActive && remaining != null) ...[
            _buildActiveTimerCard(remaining),
            const SizedBox(height: 24),
          ],
          Text('选择定时时间', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.bold,
            color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          ..._presetDurations.map((preset) => _buildPresetTile(preset)),
          Divider(height: 32, color: AppColors.divider),
          _buildCustomTimerTile(),
          if (isActive) ...[
            const SizedBox(height: 24),
            _buildCancelButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveTimerCard(Duration remaining) {
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    final seconds = remaining.inSeconds.remainder(60);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.primarySoftColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppNeumorphic.soft,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(Icons.timer, size: 48, color: AppColors.primary),
          const SizedBox(height: 16),
          Text('剩余时间', style: TextStyle(
            color: AppColors.primary, fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
            style: TextStyle(
              fontSize: 36, fontWeight: FontWeight.bold,
              color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetTile(Map<String, dynamic> preset) {
    return ListTile(
      leading: Icon(Icons.access_time, color: AppColors.textSecondary),
      title: Text(preset['label'], style: TextStyle(color: AppColors.textPrimary)),
      trailing: Icon(Icons.chevron_right, color: AppColors.textHint),
      onTap: () {
        ref.read(playerServiceProvider).startSleepTimer(preset['duration']);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已设置${preset['label']}后退出')),
        );
      },
    );
  }

  Widget _buildCustomTimerTile() {
    return ListTile(
      leading: Icon(Icons.timer_off, color: AppColors.textSecondary),
      title: Text('自定义时间', style: TextStyle(color: AppColors.textPrimary)),
      trailing: Icon(Icons.chevron_right, color: AppColors.textHint),
      onTap: _showCustomTimePicker,
    );
  }

  void _showCustomTimePicker() async {
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 1, minute: 0),
      helpText: '选择定时时间',
    );

    if (time != null && mounted) {
      final duration = Duration(hours: time.hour, minutes: time.minute);
      if (duration.inMinutes > 0) {
        ref.read(playerServiceProvider).startSleepTimer(duration);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已设置${time.hour}小时${time.minute}分钟后退出')),
        );
      }
    }
  }

  Widget _buildCancelButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          ref.read(playerServiceProvider).cancelSleepTimer();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已取消定时退出')),
          );
        },
        icon: const Icon(Icons.cancel),
        label: const Text('取消定时'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.error,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}
