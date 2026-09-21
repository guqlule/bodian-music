import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/playlist_model.dart';
import '../../providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../services/api/songlist_service.dart';

class MyListScreen extends ConsumerStatefulWidget {
  const MyListScreen({super.key});

  @override
  ConsumerState<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends ConsumerState<MyListScreen> {
  final SonglistService _songlistService = SonglistService();
  List<SonglistInfo> _qqRecommendations = [];
  bool _isLoadingRecommend = false;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _loadQQRecommendations();
  }

  /// 加载 QQ 音乐推荐歌单（随机页码，每次内容都不同）
  Future<void> _loadQQRecommendations() async {
    if (_isLoadingRecommend) return;
    setState(() => _isLoadingRecommend = true);
    try {
      // 先随机页码再请求：热门榜约 130 个歌单 / 20 每页 ≈ 6 页
      final page = _random.nextInt(6);
      final lists = await _songlistService.getQQRecommendSonglists(page: page, pageSize: 20);
      if (!mounted) return;
      setState(() {
        if (lists.isNotEmpty) {
          _qqRecommendations = lists;
        }
        _isLoadingRecommend = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingRecommend = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(playlistProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('我的歌单'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // 导入歌单
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: _showImportDialog,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primarySoftColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.download_rounded, color: AppColors.primary, size: 20),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: _showCreatePlaylistDialog,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          await _loadQQRecommendations();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 默认列表卡片
            _buildSectionCard(
              title: '默认列表',
              children: [
                _buildDefaultList('我喜欢', 'love', Icons.favorite_rounded,
                    subtitle: null),
                _buildDefaultList('最近播放', 'recent', Icons.history_rounded,
                    subtitle: null),
              ],
            ),

          if (playlists.isNotEmpty) ...[
            ...() {
              final favPlaylists = playlists.where((p) => p.id.startsWith('fav_')).toList();
              final customPlaylists = playlists.where((p) => !p.id.startsWith('fav_')).toList();
              return [
                if (favPlaylists.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    title: '收藏歌单',
                    children: favPlaylists.map((playlist) => _buildUserPlaylist(playlist)).toList(),
                  ),
                ],
                if (customPlaylists.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    title: '自定义列表',
                    children: customPlaylists.map((playlist) => _buildUserPlaylist(playlist)).toList(),
                  ),
                ],
              ];
            }(),
          ],

          if (playlists.isEmpty) ...[
            const SizedBox(height: 40),
            Center(
              child: Column(
                children: [
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoftColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: AppNeumorphic.soft,
                    ),
                    child: Icon(Icons.queue_music_rounded, size: 32, color: AppColors.primary),
                  ),
                  const SizedBox(height: 16),
                  Text('点击右上角 + 创建新列表，或从下方推荐中导入', style: TextStyle(
                    color: AppColors.textHint, fontSize: 13)),
                ],
              ),
            ),
          ],

          // QQ 音乐推荐歌单（随机）
          const SizedBox(height: 20),
          _buildQQRecommendSection(),
        ],
        ),
      ),
    );
  }

  // QQ 音乐推荐歌单横向滚动区
  Widget _buildQQRecommendSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.explore_rounded, color: AppColors.primary, size: 18),
            const SizedBox(width: 6),
            Text('在线歌单推荐', style: TextStyle(
              color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
            const Spacer(),
            GestureDetector(
              onTap: _loadQQRecommendations,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: AppNeumorphic.flat,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, color: AppColors.primary, size: 14),
                    SizedBox(width: 4),
                    Text('换一批', style: TextStyle(color: AppColors.primary, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isLoadingRecommend)
          SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
          )
        else if (_qqRecommendations.isEmpty)
          Container(
            height: 120,
            alignment: Alignment.center,
            child: Text('推荐加载失败，点击"换一批"重试',
                style: TextStyle(color: AppColors.textHint, fontSize: 12)),
          )
        else
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _qqRecommendations.length,
              itemBuilder: (context, index) {
                final list = _qqRecommendations[index];
                return GestureDetector(
                  onTap: () => context.push('/songlist-detail/${list.id}',
                      extra: {'name': list.name, 'source': 'tx'}),
                  child: Container(
                    width: 140,
                    margin: const EdgeInsets.only(right: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          children: [
                            Container(
                              width: 140, height: 140,
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: AppNeumorphic.soft,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: list.imgUrl.isNotEmpty
                                    ? Image.network(list.imgUrl, cacheWidth: 240, fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Center(
                                          child: Icon(Icons.queue_music_rounded,
                                              color: AppColors.primary, size: 32)))
                                    : Center(
                                        child: Icon(Icons.queue_music_rounded,
                                            color: AppColors.primary, size: 32)),
                              ),
                            ),
                            // 收藏角标（一键导入为本地歌单）
                            Positioned(
                              right: 6, bottom: 6,
                              child: GestureDetector(
                                onTap: () => _quickImport(list),
                                child: Container(
                                  width: 30, height: 30,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.add_rounded,
                                      color: Colors.white, size: 18),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(list.name,
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppColors.textPrimary, fontSize: 12, height: 1.3)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  /// 快速导入推荐歌单（只存歌单元信息，歌曲在打开详情时拉取）
  Future<void> _quickImport(SonglistInfo list) async {
    final exists = ref.read(playlistProvider).any((p) => p.id == 'import_tx_${list.id}');
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('「${list.name}」已在列表中')));
      return;
    }
    final playlist = PlaylistInfo(
      id: 'import_tx_${list.id}',
      name: list.name,
      createTime: DateTime.now(),
      updateTime: DateTime.now(),
      coverUrl: list.imgUrl.isNotEmpty ? list.imgUrl : null,
    );
    ref.read(playlistProvider.notifier).addPlaylist(playlist);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已收藏歌单「${list.name}」')));
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

  Widget _buildDefaultList(String name, String id, IconData icon, {String? subtitle}) {
    return ListTile(
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.textSecondary, size: 18),
      ),
      title: Text(name, style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(
          color: AppColors.textHint, fontSize: 11)) : null,
      trailing: Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 20),
      onTap: () => _openDefaultList(id, name),
    );
  }

  Widget _buildUserPlaylist(PlaylistInfo playlist) {
    return ListTile(
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: AppColors.primarySoftColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.queue_music_rounded, color: AppColors.primary, size: 18),
      ),
      title: Text(playlist.name, style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
      subtitle: Text('${playlist.songCount} 首歌曲', style: TextStyle(
        color: AppColors.textHint, fontSize: 11)),
      trailing: PopupMenuButton(
        icon: Icon(Icons.more_vert_rounded, color: AppColors.textHint, size: 20),
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'play', child: Text('播放全部')),
          const PopupMenuItem(value: 'edit', child: Text('编辑')),
          const PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
        onSelected: (value) => _handlePlaylistAction(value, playlist),
      ),
      onTap: () => _openPlaylist(playlist.id, playlist.name),
    );
  }

  void _handlePlaylistAction(String action, PlaylistInfo playlist) {
    switch (action) {
      case 'play': _playAllSongs(playlist); break;
      case 'edit': _showEditPlaylistDialog(playlist); break;
      case 'delete': _showDeletePlaylistDialog(playlist); break;
    }
  }

  void _playAllSongs(PlaylistInfo playlist) async {
    if (playlist.songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('列表为空')));
      return;
    }
    await ref.read(playerServiceProvider).setPlaylist(playlist.songs);
  }

  void _openPlaylist(String id, String name) {
    context.push('/playlist-detail/$id', extra: {'name': name});
  }

  void _openDefaultList(String id, String name) {
    switch (id) {
      case 'love':
        context.push('/favorites');
        break;
      case 'recent':
        context.push('/recent');
        break;
    }
  }

  // ==================== 导入歌单（分享链接） ====================

  void _showImportDialog() {
    final controller = TextEditingController();
    bool importing = false;
    String? message;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('导入歌单',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '粘贴 小Q/小W 歌单分享链接',
                style: TextStyle(color: AppColors.textHint, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                minLines: 1,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'https://c6.y.qq.com/base/fcgi-bin/u?__=xxx',
                  hintStyle: TextStyle(color: AppColors.textHint, fontSize: 11),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              if (importing) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('正在导入...',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              ],
              if (message != null) ...[
                const SizedBox(height: 12),
                Text(message!,
                    style: TextStyle(
                        color: message!.contains('成功')
                            ? AppColors.success
                            : AppColors.error,
                        fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: importing ? null : () => Navigator.pop(context),
              child: Text('取消', style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: importing
                  ? null
                  : () async {
                      final input = controller.text.trim();
                      if (input.isEmpty) return;
                      setDialogState(() { importing = true; message = null; });

                      try {
                        final result = await _importPlaylist(input);
                        setDialogState(() {
                          importing = false;
                          message = result;
                        });
                        if (result.contains('成功') && mounted) setState(() {});
                      } catch (e) {
                        setDialogState(() { importing = false; message = '导入失败: $e'; });
                      }
                    },
              child: Text('导入', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      ),
    ).then((_) => controller.dispose());
  }

  Future<String> _importPlaylist(String input) async {
    final songlistService = SonglistService();

    // 1. 解析链接
    var parsed = SonglistService.parseShareLink(input);
    if (parsed == null) {
      return '无法识别链接，请粘贴完整的歌单分享链接';
    }

    String source = parsed.source;
    String id = parsed.id;

    // 2. 短链需要跟随重定向
    if (source == 'redirect') {
      final resolvedId = await SonglistService.resolveRedirectId(parsed.id);
      if (resolvedId == null) {
        return '链接解析失败，请检查链接是否完整';
      }
      id = resolvedId;
      source = input.contains('163.com') || input.contains('163cn.tv') ? 'wy' : 'tx';
    }

    // 3. 拉取歌单
    final detail = source == 'wy'
        ? await songlistService.getWYPlaylistDetail(id)
        : await songlistService.getQQPlaylistDetail(id);

    if (detail == null || detail.songs.isEmpty) {
      return '歌单获取失败（可能不是公开歌单）';
    }

    // 4. 存为本地自定义歌单
    final playlist = PlaylistInfo(
      id: 'import_${source}_$id',
      name: detail.name.isNotEmpty ? detail.name : '导入的歌单',
      createTime: DateTime.now(),
      updateTime: DateTime.now(),
      songs: detail.songs,
      coverUrl: detail.imgUrl.isNotEmpty ? detail.imgUrl : null,
    );
    ref.read(playlistProvider.notifier).addPlaylist(playlist);

    return '导入成功「${playlist.name}」共 ${detail.songs.length} 首';
  }

  void _showCreatePlaylistDialog() {    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('创建新列表', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: '输入列表名称',
            hintStyle: TextStyle(color: AppColors.textHint),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                _createPlaylist(name);
                Navigator.pop(context);
              }
            },
            child: Text('创建', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  void _createPlaylist(String name) {
    final playlist = PlaylistInfo(
      id: 'userlist_${DateTime.now().millisecondsSinceEpoch}',
      name: name, createTime: DateTime.now(), updateTime: DateTime.now(),
    );
    ref.read(playlistProvider.notifier).addPlaylist(playlist);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已创建 "$name"')));
  }

  void _showEditPlaylistDialog(PlaylistInfo playlist) {
    final controller = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('编辑列表名称', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: '输入列表名称',
            hintStyle: TextStyle(color: AppColors.textHint),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('取消', style: TextStyle(color: AppColors.textSecondary))),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                playlist.name = name;
                playlist.updateTime = DateTime.now();
                ref.read(playlistProvider.notifier).updatePlaylist(playlist);
                Navigator.pop(context);
              }
            },
            child: Text('保存', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  void _showDeletePlaylistDialog(PlaylistInfo playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('删除列表', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Text('确定要删除 "${playlist.name}" 吗？',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('取消', style: TextStyle(color: AppColors.textSecondary))),
          TextButton(
            onPressed: () {
              ref.read(playlistProvider.notifier).removePlaylist(playlist.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已删除 "${playlist.name}"')));
            },
            child: Text('删除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
