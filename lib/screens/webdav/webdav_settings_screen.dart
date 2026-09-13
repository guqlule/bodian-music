import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/webdav_provider.dart';
import '../../services/webdav/webdav_service.dart';

/// 常见 NAS/WebDAV 预设
class _NasPreset {
  final String name;
  final int port;
  final bool useHttps;
  final String defaultPath;
  const _NasPreset(this.name, {this.port = 5005, this.useHttps = false, this.defaultPath = '/music'});
}

const _presets = [
  _NasPreset('自定义', port: 5005),
  _NasPreset('群晖 Synology', port: 5006, useHttps: true, defaultPath: '/music'),
  _NasPreset('威联通 QNAP', port: 5005, defaultPath: '/WebDAV/music'),
  _NasPreset('Nextcloud', port: 443, useHttps: true, defaultPath: '/remote.php/dav/files/admin'),
  _NasPreset('ownCloud', port: 443, useHttps: true, defaultPath: '/remote.php/webdav'),
  _NasPreset('Alist WebDAV', port: 5244, defaultPath: '/dav'),
  _NasPreset('Rclone', port: 8080, defaultPath: '/'),
  _NasPreset('Windows IIS', port: 80, defaultPath: '/webdav'),
];

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
  int _selectedPreset = 0;
  bool _testResult = false;
  String? _testError;
  bool _tested = false;

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

  void _applyPreset(int index) {
    final preset = _presets[index];
    setState(() {
      _selectedPreset = index;
      _portCtrl.text = preset.port.toString();
      _useHttps = preset.useHttps;
      _pathCtrl.text = preset.defaultPath;
      _tested = false;
    });
  }

  Future<void> _testConnection() async {
    final config = _buildConfig();
    if (config.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入服务器地址')),
      );
      return;
    }

    setState(() { _tested = false; _testError = null; });

    final result = await ref.read(webdavConfigProvider.notifier).testConnectionDetailed(config);
    if (!mounted) return;

    setState(() {
      _tested = true;
      _testResult = result.ok;
      _testError = result.ok
          ? '连接成功！发现 ${result.fileCount ?? 0} 首音频文件'
          : result.error;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.ok ? '连接成功！发现 ${result.fileCount ?? 0} 首音频文件' : '连接失败: ${result.error}'),
        backgroundColor: result.ok ? AppColors.primaryDark : Colors.red,
        duration: Duration(seconds: result.ok ? 2 : 4),
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
        const SnackBar(content: Text('已保存并连接'), backgroundColor: AppColors.primaryDark),
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
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 连接状态
              _buildStatusCard(state),
              const SizedBox(height: 20),

              // NAS 预设
              Text('服务器类型', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_presets.length, (i) {
                  final p = _presets[i];
                  final selected = _selectedPreset == i;
                  return ChoiceChip(
                    label: Text(p.name, style: TextStyle(fontSize: 12, color: selected ? Colors.white : AppColors.textPrimary)),
                    selected: selected,
                    selectedColor: AppColors.primaryDark,
                    backgroundColor: AppColors.surface,
                    onSelected: (_) => _applyPreset(i),
                  );
                }),
              ),
              const SizedBox(height: 20),

              // 服务器地址 + 端口
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildTextField(_hostCtrl, '服务器地址', '如 192.168.1.100 或 nas.example.com'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: _buildTextField(_portCtrl, '端口', '5005', keyboardType: TextInputType.number),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // HTTPS
              SwitchListTile(
                title: Text('使用 HTTPS', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                subtitle: Text('公网访问建议开启', style: TextStyle(color: AppColors.textHint, fontSize: 11)),
                value: _useHttps,
                onChanged: (v) => setState(() { _useHttps = v; _tested = false; }),
                activeColor: AppColors.primaryDark,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              const SizedBox(height: 8),

              // 用户名密码
              Row(
                children: [
                  Expanded(child: _buildTextField(_userCtrl, '用户名', '可选')),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTextField(_passCtrl, '密码', '可选', obscure: true)),
                ],
              ),
              const SizedBox(height: 16),

              // 远程路径
              _buildTextField(_pathCtrl, '远程路径', '/music'),
              const SizedBox(height: 8),
              Text(
                '指 WebDAV 服务器上音乐文件所在的目录路径',
                style: TextStyle(color: AppColors.textHint, fontSize: 11),
              ),
              const SizedBox(height: 24),

              // 测试结果
              if (_tested)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: (_testResult ? AppColors.primaryDark : Colors.red).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _testResult ? Icons.check_circle : Icons.error_outline,
                        color: _testResult ? AppColors.primaryDark : Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _testResult ? '连接成功！${_testError ?? ''}' : (_testError ?? '连接失败'),
                          style: TextStyle(
                            color: _testResult ? AppColors.primaryDark : Colors.red,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // 按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: state.isLoading ? null : _testConnection,
                      icon: state.isLoading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.wifi_find_rounded, size: 18),
                      label: const Text('测试连接'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: BorderSide(color: AppColors.divider),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: state.isLoading ? null : _saveAndConnect,
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: const Text('保存并连接'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryDark,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),

              // 清空缓存
              if (state.isConnected) ...[
                const SizedBox(height: 20),
                TextButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('清空音乐库缓存'),
                        content: const Text('将删除已扫描的歌曲列表（不影响服务器文件）'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清空', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await ref.read(webdavConfigProvider.notifier).clearLibrary();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已清空')),
                        );
                      }
                    }
                  },
                  icon: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red.withValues(alpha: 0.7)),
                  label: Text('清空音乐库缓存', style: TextStyle(color: Colors.red.withValues(alpha: 0.7), fontSize: 13)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(WebdavConfigState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: state.isConnected ? AppColors.primaryDark.withValues(alpha: 0.08) : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: state.isConnected ? AppColors.primaryDark.withValues(alpha: 0.3) : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (state.isConnected ? AppColors.primaryDark : AppColors.textHint).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              state.isConnected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
              color: state.isConnected ? AppColors.primaryDark : AppColors.textHint,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.isConnected ? '已连接' : '未连接',
                  style: TextStyle(
                    color: state.isConnected ? AppColors.primaryDark : AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (state.config?.host == null)
                  Text('请配置 WebDAV 服务器', style: TextStyle(color: AppColors.textHint, fontSize: 12))
                else
                  Text(
                    '${state.config!.host}:${state.config!.port}',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (state.isConnected)
            TextButton(
              onPressed: () => ref.read(webdavConfigProvider.notifier).disconnect(),
              child: const Text('断开'),
            ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, String hint, {
    TextInputType? keyboardType,
    bool obscure = false,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      obscureText: obscure,
      onChanged: (_) => setState(() => _tested = false),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: AppColors.textHint, fontSize: 13),
        hintStyle: TextStyle(color: AppColors.textHint.withValues(alpha: 0.5), fontSize: 12),
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.primaryDark, width: 1.5),
        ),
      ),
    );
  }
}
