import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/user_api_provider.dart' as provider;
import '../../models/music_model.dart';
import '../../services/api/user_api_service.dart' as service;
import '../../services/platform/file_picker_service.dart';
import '../../core/theme/app_theme.dart';

class UserApiScreen extends ConsumerStatefulWidget {
  const UserApiScreen({super.key});

  @override
  ConsumerState<UserApiScreen> createState() => _UserApiScreenState();
}

class _UserApiScreenState extends ConsumerState<UserApiScreen> {
  @override
  Widget build(BuildContext context) {
    final apiState = ref.watch(provider.userApiProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('自定义源'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: _showDebugLogDialog,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.bug_report_outlined, color: AppColors.textSecondary, size: 18),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: _showImportOptions,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(apiState),
      floatingActionButton: apiState.currentScript != null
          ? Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(color: AppColors.error.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.stop_rounded, color: Colors.white),
                onPressed: _deactivateScript,
              ),
            )
          : null,
    );
  }

  void _showDebugLogDialog() {
    final logText = ref.read(provider.userApiServiceProvider).debugLogText;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.primarySoftColor, borderRadius: BorderRadius.circular(10)),
                      child: Icon(Icons.bug_report_rounded, color: AppColors.primary, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text('调试日志', style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary))),
                    IconButton(
                      icon: Icon(Icons.refresh_rounded, color: AppColors.textSecondary, size: 20),
                      onPressed: () { Navigator.pop(context); _showDebugLogDialog(); },
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded, color: AppColors.textHint, size: 20),
                      onPressed: () {
                        ref.read(provider.userApiServiceProvider).debugLogs.clear();
                        Navigator.pop(context);
                        _showDebugLogDialog();
                      },
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.divider),
              Expanded(
                child: logText.isEmpty
                    ? Center(child: Text('暂无调试日志', style: TextStyle(color: AppColors.textHint)))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(logText, style: TextStyle(
                          fontSize: 11, fontFamily: 'monospace', color: AppColors.textSecondary, height: 1.5)),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity, height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                    child: Center(child: Text('关闭', style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13))),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(provider.UserApiState state) {
    if (state.scripts.isEmpty) return _buildEmptyState();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (state.currentScript != null) ...[
          _buildActiveScriptCard(state.currentScript!, state),
          const SizedBox(height: 16),
        ],
        Text('已导入的脚本 (${state.scripts.length})', style: TextStyle(
          color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ...state.scripts.map((script) => _buildScriptCard(script)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.primarySoftColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppNeumorphic.soft,
            ),
            child: Icon(Icons.code_rounded, size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          Text('暂无自定义源脚本', style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text('导入脚本以扩展音乐源功能', style: TextStyle(color: AppColors.textHint, fontSize: 12)),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _showImportOptions,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: const Text('导入脚本', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveScriptCard(service.UserApiScript script, provider.UserApiState state) {
    final failed = state.type == provider.UserApiStateType.error;
    final statusColor = failed ? AppColors.error : AppColors.primary;
    final statusText = failed ? '激活失败' : (service.UserApiService().isActive ? '当前激活' : '正在初始化…');
    final statusIcon = failed
        ? Icons.error_outline_rounded
        : (service.UserApiService().isActive ? Icons.check_circle_rounded : Icons.hourglass_top_rounded);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: failed ? AppColors.error.withValues(alpha: 0.08) : AppColors.primarySoftColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 20),
              const SizedBox(width: 8),
              Text(statusText, style: TextStyle(
                color: statusColor, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          Text(script.name, style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          if (script.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(script.description, style: TextStyle(
              color: AppColors.textSecondary, fontSize: 13)),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              _buildInfoChip('v${script.version}'),
              const SizedBox(width: 8),
              if (script.author.isNotEmpty) _buildInfoChip(script.author),
            ],
          ),
          if (failed && state.error != null) ...[
            const SizedBox(height: 8),
            Text(state.error!, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.error, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  Widget _buildScriptCard(service.UserApiScript script) {
    final isActive = ref.read(provider.userApiProvider).currentScript?.id == script.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppNeumorphic.flat,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.code_rounded,
            color: isActive ? Colors.white : AppColors.textSecondary, size: 20),
        ),
        title: Text(script.name, style: TextStyle(
          color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (script.description.isNotEmpty)
              Text(script.description, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 4),
            Row(children: [
              _buildInfoChip('v${script.version}'),
              const SizedBox(width: 8),
              if (script.author.isNotEmpty) _buildInfoChip(script.author),
            ]),
          ],
        ),
        isThreeLine: true,
        trailing: PopupMenuButton(
          icon: Icon(Icons.more_vert_rounded, color: AppColors.textHint, size: 20),
          itemBuilder: (context) => [
            if (!isActive) const PopupMenuItem(value: 'activate', child: Text('激活')),
            if (isActive) const PopupMenuItem(value: 'deactivate', child: Text('停用')),
            const PopupMenuItem(value: 'test', child: Text('测试')),
            const PopupMenuItem(value: 'info', child: Text('详情')),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
          onSelected: (value) => _handleMenuAction(value, script),
        ),
        onTap: () => _showScriptDetail(script),
      ),
    );
  }

  Widget _buildInfoChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: AppColors.textHint)),
    );
  }

  void _showImportOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: Container(width: 36, height: 36, decoration: BoxDecoration(
                color: AppColors.primarySoftColor, borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.folder_open_rounded, color: AppColors.primary, size: 18)),
              title: Text('从文件选择', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              subtitle: Text('选择.js文件导入', style: TextStyle(color: AppColors.textHint, fontSize: 11)),
              onTap: () { Navigator.pop(context); _importFromFile(); },
            ),
            ListTile(
              leading: Container(width: 36, height: 36, decoration: BoxDecoration(
                color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.paste_rounded, color: AppColors.textSecondary, size: 18)),
              title: Text('粘贴脚本内容', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              subtitle: Text('手动粘贴JS代码', style: TextStyle(color: AppColors.textHint, fontSize: 11)),
              onTap: () { Navigator.pop(context); _importFromClipboard(); },
            ),
            ListTile(
              leading: Container(width: 36, height: 36, decoration: BoxDecoration(
                color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.code_rounded, color: AppColors.textSecondary, size: 18)),
              title: Text('示例脚本', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              subtitle: Text('加载内置示例脚本', style: TextStyle(color: AppColors.textHint, fontSize: 11)),
              onTap: () { Navigator.pop(context); _importFromExample(); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _importFromFile() async {
    try {
      final content = await FilePickerService.pickFile(extension: 'js');
      if (content != null && content.isNotEmpty) {
        await ref.read(provider.userApiProvider.notifier).importScript(content);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('脚本导入成功')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  void _importFromClipboard() async {
    try {
      final content = await _showImportDialog();
      if (content != null && content.isNotEmpty) {
        await ref.read(provider.userApiProvider.notifier).importScript(content);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('脚本导入成功')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  void _importFromExample() async {
    try {
      final scripts = await _getExampleScripts();
      final choice = await _showScriptChoiceDialog(scripts);
      if (choice != null && choice.isNotEmpty) {
        await ref.read(provider.userApiProvider.notifier).importScript(choice);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('示例脚本导入成功')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  Future<String?> _showImportDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入脚本'),
        content: SizedBox(
          width: double.maxFinite, height: 300,
          child: TextField(
            controller: controller, maxLines: null, expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              hintText: '请粘贴脚本内容...',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('取消', style: TextStyle(color: AppColors.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text('导入', style: TextStyle(color: AppColors.primary))),
        ],
      ),
    );
    // 对话框关闭后释放 controller（防泄漏）
    Future.delayed(const Duration(milliseconds: 100), () {
      try {
        controller.dispose();
      } catch (_) {}
    });
    return result;
  }

  Future<List<MapEntry<String, String>>> _getExampleScripts() async {
    return [
      MapEntry('示例脚本 - kw源', '''/**
 * @name KW示例脚本
 * @description 酷我音乐源示例
 * @version 1.0.0
 * @author Example
 */

lx.on('request', async({ source, action, info }) => {
  if (action === 'musicUrl') {
    return { type: '128k', url: 'https://example.com/music.mp3' };
  }
  throw new Error('不支持的操作');
});

lx.send('inited', {
  sources: {
    kw: {
      type: 'music',
      actions: ['musicUrl'],
      qualitys: ['128k', '320k', 'flac']
    }
  }
});'''),
      MapEntry('示例脚本 - kg源', '''/**
 * @name KG示例脚本
 * @description 酷狗音乐源示例
 * @version 1.0.0
 * @author Example
 */

lx.on('request', async({ source, action, info }) => {
  if (action === 'musicUrl') {
    return { type: '128k', url: 'https://example.com/kg-music.mp3' };
  }
  throw new Error('不支持的操作');
});

lx.send('inited', {
  sources: {
    kg: {
      type: 'music',
      actions: ['musicUrl'],
      qualitys: ['128k', '320k', 'flac']
    }
  }
});'''),
      MapEntry('AGNES AI 音源', '''/**
 * @name AGNES AI 音源
 * @description 基于 apihub.agnes-ai.com 的音乐源
 * @version 1.0.0
 * @author lx-music
 * @homepage https://agnes-ai.com
 */

const API_KEY = 'sk-jDsMN4dYY9rx2JwYGZ4PTHg61n05NZoQQXwdSLbOlBHhMg1R';
const BASE_URL = 'https://apihub.agnes-ai.com/v1';

async function request(url, options = {}) {
  const headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + API_KEY,
    ...options.headers,
  };
  const resp = await fetch(url, { ...options, headers });
  if (!resp.ok) throw new Error('HTTP ' + resp.status);
  return resp.json();
}

lx.on('request', async({ source, action, info }) => {
  if (action === 'musicSearch') {
    const { keyword, page = 1, limit = 30 } = info;
    const data = await request(BASE_URL + '/search', {
      method: 'POST',
      body: JSON.stringify({ keyword, source, page, limit }),
    });
    return { list: data.data?.list || data.list || [], total: data.data?.total || data.total || 0 };
  }

  if (action === 'musicUrl') {
    const { musicInfo, type } = info;
    const data = await request(BASE_URL + '/url', {
      method: 'POST',
      body: JSON.stringify({ id: musicInfo.songId || musicInfo.id, source: musicInfo.source, quality: type }),
    });
    return { type: type, url: data.data?.url || data.url || '' };
  }

  if (action === 'lyric') {
    const { musicInfo } = info;
    const data = await request(BASE_URL + '/lyric', {
      method: 'POST',
      body: JSON.stringify({ id: musicInfo.songId || musicInfo.id, source: musicInfo.source }),
    });
    return { lyric: data.data?.lyric || data.lyric || '', tlyric: data.data?.tlyric || data.tlyric || '' };
  }

  throw new Error('不支持的操作: ' + action);
});

lx.send('inited', {
  sources: {
    agnes: {
      type: 'music',
      actions: ['musicSearch', 'musicUrl', 'lyric'],
      qualitys: ['128k', '320k', 'flac']
    }
  }
});'''),
    ];
  }

  Future<String?> _showScriptChoiceDialog(List<MapEntry<String, String>> scripts) async {
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择示例脚本'),
        children: scripts.map((script) => SimpleDialogOption(
          onPressed: () => Navigator.pop(context, script.value),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(script.key, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text(script.value.substring(0, 100) + '...', style: TextStyle(
                color: AppColors.textHint, fontSize: 11)),
            ],
          ),
        )).toList(),
      ),
    );
  }

  void _handleMenuAction(String action, service.UserApiScript script) {
    switch (action) {
      case 'activate': ref.read(provider.userApiProvider.notifier).activateScript(script.id); break;
      case 'deactivate': ref.read(provider.userApiProvider.notifier).deactivateScript(); break;
      case 'test': _testScript(script); break;
      case 'info': _showScriptDetail(script); break;
      case 'delete': _showDeleteConfirmDialog(script); break;
    }
  }

  void _deactivateScript() => ref.read(provider.userApiProvider.notifier).deactivateScript();

  void _testScript(service.UserApiScript script) {
    showDialog(context: context, builder: (context) => _TestScriptDialog(script: script));
  }

  void _showScriptDetail(service.UserApiScript script) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7, minChildSize: 0.5, maxChildSize: 0.9, expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
                  color: AppColors.divider, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                Text(script.name, style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 16),
                _buildDetailRow('版本', script.version),
                _buildDetailRow('作者', script.author),
                _buildDetailRow('描述', script.description),
                _buildDetailRow('主页', script.homepage),
                _buildDetailRow('导入时间', script.importedAt.toString()),
                const SizedBox(height: 16),
                if (script.sources.isNotEmpty) ...[
                  Text('支持的音源', style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  ...script.sources.entries.map((entry) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.key.toUpperCase(), style: TextStyle(
                        color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
                      subtitle: Text('操作: ${entry.value.actions.join(", ")}\n音质: ${entry.value.qualitys.join(", ")}',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ),
                  )),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          ref.read(provider.userApiProvider.notifier).activateScript(script.id);
                        },
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primary, borderRadius: BorderRadius.circular(14)),
                          child: const Center(child: Text('激活', style: TextStyle(
                            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () { Navigator.pop(context); _showDeleteConfirmDialog(script); },
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
                          child: Center(child: Text('删除', style: TextStyle(
                            color: AppColors.error, fontSize: 14, fontWeight: FontWeight.w500))),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 70, child: Text('$label:', style: TextStyle(
            fontWeight: FontWeight.w600, color: AppColors.textSecondary, fontSize: 13))),
          Expanded(child: Text(value, style: TextStyle(
            color: AppColors.textPrimary, fontSize: 13))),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(service.UserApiScript script) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除脚本'),
        content: Text('确定要删除 "${script.name}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('取消', style: TextStyle(color: AppColors.textSecondary))),
          TextButton(
            onPressed: () {
              ref.read(provider.userApiProvider.notifier).removeScript(script.id);
              Navigator.pop(context);
            },
            child: Text('删除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _TestScriptDialog extends ConsumerStatefulWidget {
  final service.UserApiScript script;
  const _TestScriptDialog({required this.script});

  @override
  ConsumerState<_TestScriptDialog> createState() => _TestScriptDialogState();
}

class _TestScriptDialogState extends ConsumerState<_TestScriptDialog> {
  final _songNameController = TextEditingController(text: '晴天');
  final _artistController = TextEditingController(text: '周杰伦');
  String _selectedSource = 'kw';
  String _selectedQuality = '320k';
  bool _isTesting = false;
  String? _result;
  bool? _success;

  @override
  void dispose() {
    _songNameController.dispose();
    _artistController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('测试: ${widget.script.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: _songNameController,
              decoration: const InputDecoration(labelText: '歌曲名称', hintText: '请输入歌曲名称')),
            const SizedBox(height: 12),
            TextField(controller: _artistController,
              decoration: const InputDecoration(labelText: '歌手名称', hintText: '请输入歌手名称')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedSource,
              decoration: const InputDecoration(labelText: '音源'),
              items: const [
                DropdownMenuItem(value: 'kw', child: Text('源一')),
                DropdownMenuItem(value: 'kg', child: Text('源二')),
                DropdownMenuItem(value: 'tx', child: Text('源三')),
                DropdownMenuItem(value: 'wy', child: Text('源四')),
                DropdownMenuItem(value: 'mg', child: Text('源五')),
              ],
              onChanged: (value) { if (value != null) setState(() => _selectedSource = value); },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedQuality,
              decoration: const InputDecoration(labelText: '音质'),
              items: const [
                DropdownMenuItem(value: '128k', child: Text('128k')),
                DropdownMenuItem(value: '320k', child: Text('320k')),
                DropdownMenuItem(value: 'flac', child: Text('FLAC')),
                DropdownMenuItem(value: 'flac24bit', child: Text('FLAC 24bit')),
              ],
              onChanged: (value) { if (value != null) setState(() => _selectedQuality = value); },
            ),
            const SizedBox(height: 16),
            if (_isTesting) Center(child: CircularProgressIndicator(color: AppColors.primary))
            else if (_result != null) Container(
              width: double.infinity, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _success == true ? AppColors.success.withValues(alpha: 0.1) : AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _success == true ? AppColors.success : AppColors.error),
              ),
              child: Text(_result!, style: TextStyle(fontSize: 12, color: AppColors.textPrimary), maxLines: 5, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _isTesting ? null : () => Navigator.pop(context),
          child: Text('取消', style: TextStyle(color: AppColors.textSecondary))),
        TextButton(onPressed: _isTesting ? null : _runTest,
          child: Text('测试', style: TextStyle(color: AppColors.primary))),
      ],
    );
  }

  void _runTest() async {
    final songName = _songNameController.text.trim();
    if (songName.isEmpty) { setState(() { _result = '请输入歌曲名称'; _success = false; }); return; }

    setState(() { _isTesting = true; _result = null; _success = null; });

    try {
      final testMusic = MusicInfo(
        id: 'test_${DateTime.now().millisecondsSinceEpoch}', name: songName,
        singer: _artistController.text.trim(), album: '', duration: 0,
        source: _selectedSource, songId: '', songmid: '', strMediaMid: '',
        copyrightId: '', hash: '',
      );
      final serviceProvider = ref.read(provider.userApiServiceProvider);
      await serviceProvider.activateScript(widget.script.id);
      await Future.delayed(const Duration(seconds: 2));
      final url = await serviceProvider.getMusicUrl(apiId: widget.script.id, music: testMusic, quality: _selectedQuality);

      setState(() {
        _result = url != null && url.isNotEmpty ? '获取到URL:\n$url' : '未获取到播放URL\n点击"查看日志"见详细调试信息';
        _success = url != null && url.isNotEmpty;
      });
    } catch (e) {
      setState(() { _result = '测试出错:\n$e'; _success = false; });
    } finally {
      setState(() => _isTesting = false);
    }
  }
}
