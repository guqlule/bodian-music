import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/webdav_provider.dart';
import '../../services/webdav/webdav_service.dart';

class WebdavSettingsScreen extends ConsumerStatefulWidget {
  const WebdavSettingsScreen({super.key});
  @override
  ConsumerState<WebdavSettingsScreen> createState() => _WebdavSettingsScreenState();
}

class _WebdavSettingsScreenState extends ConsumerState<WebdavSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _hostCtrl;
  late TextEditingController _portCtrl;
  late TextEditingController _userCtrl;
  late TextEditingController _passCtrl;
  late TextEditingController _pathCtrl;
  bool _useHttps = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(webdavConfigProvider).config;
    _hostCtrl = TextEditingController(text: config?.host ?? '');
    _portCtrl = TextEditingController(text: (config?.port ?? 5005).toString());
    _userCtrl = TextEditingController(text: config?.username ?? '');
    _passCtrl = TextEditingController(text: config?.password ?? '');
    _pathCtrl = TextEditingController(text: config?.remotePath ?? '/music');
    _useHttps = config?.useHttps ?? false;
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _pathCtrl.dispose();
    super.dispose();
  }

  WebdavConfig _buildConfig() {
    return WebdavConfig(
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 5005,
      username: _userCtrl.text.trim(),
      password: _passCtrl.text,
      remotePath: _pathCtrl.text.trim(),
      useHttps: _useHttps,
    );
  }

  Future<void> _testConnection() async {
    final config = _buildConfig();
    if (config.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入服务器地址')),
      );
      return;
    }
    final ok = await ref.read(webdavConfigProvider.notifier).testConnection(config);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '连接成功！' : '连接失败，请检查配置'),
        backgroundColor: ok ? AppColors.primaryDark : Colors.red,
      ),
    );
  }

  Future<void> _saveAndConnect() async {
    if (!_formKey.currentState!.validate()) return;
    final config = _buildConfig();
    await ref.read(webdavConfigProvider.notifier).saveAndConnect(config);
    if (!mounted) return;
    final state = ref.read(webdavConfigProvider);
    if (state.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已连接'), backgroundColor: AppColors.primaryDark),
      );
    } else if (state.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('连接失败: ${state.error}'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(webdavConfigProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('WebDAV 设置'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
      ),
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 状态卡片
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: state.isConnected ? AppColors.primaryDark.withValues(alpha: 0.1) : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      state.isConnected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                      color: state.isConnected ? AppColors.primaryDark : AppColors.textHint,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      state.isConnected ? '已连接' : '未连接',
                      style: TextStyle(
                        color: state.isConnected ? AppColors.primaryDark : AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (state.isConnected)
                      TextButton(
                        onPressed: () => ref.read(webdavConfigProvider.notifier).disconnect(),
                        child: const Text('断开'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 服务器地址
              TextFormField(
                controller: _hostCtrl,
                decoration: _inputDecoration('服务器地址', '如 192.168.1.100'),
                validator: (v) => (v == null || v.trim().isEmpty) ? '请输入服务器地址' : null,
              ),
              const SizedBox(height: 16),

              // 端口
              TextFormField(
                controller: _portCtrl,
                decoration: _inputDecoration('端口', '5005'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),

              // HTTPS
              SwitchListTile(
                title: Text('使用 HTTPS', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                value: _useHttps,
                onChanged: (v) => setState(() => _useHttps = v),
                activeColor: AppColors.primaryDark,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),

              // 用户名
              TextFormField(
                controller: _userCtrl,
                decoration: _inputDecoration('用户名', '可选'),
              ),
              const SizedBox(height: 16),

              // 密码
              TextFormField(
                controller: _passCtrl,
                decoration: _inputDecoration('密码', '可选'),
                obscureText: true,
              ),
              const SizedBox(height: 16),

              // 远程路径
              TextFormField(
                controller: _pathCtrl,
                decoration: _inputDecoration('远程路径', '/music'),
              ),
              const SizedBox(height: 32),

              // 按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: state.isLoading ? null : _testConnection,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: BorderSide(color: AppColors.divider),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: state.isLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('测试连接'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: state.isLoading ? null : _saveAndConnect,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryDark,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('保存并连接'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: AppColors.textHint, fontSize: 14),
      hintStyle: TextStyle(color: AppColors.textHint.withValues(alpha: 0.5), fontSize: 13),
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.primaryDark, width: 1.5),
      ),
    );
  }
}
