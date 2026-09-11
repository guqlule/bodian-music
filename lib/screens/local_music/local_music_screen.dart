import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/music_model.dart';
import '../../providers/app_providers.dart';
import '../../services/local/local_music_service.dart';
import '../../services/platform/file_picker_service.dart';
import '../../services/player/player_service.dart';
import '../../core/theme/app_theme.dart';

/// 本地音乐页：导入文件夹 → 自动扫描歌曲+歌词 → 列表播放
class LocalMusicScreen extends ConsumerStatefulWidget {
  const LocalMusicScreen({super.key});

  @override
  ConsumerState<LocalMusicScreen> createState() => _LocalMusicScreenState();
}

class _LocalMusicScreenState extends ConsumerState<LocalMusicScreen> {
  final LocalMusicService _localService = LocalMusicService();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _localService.loadLibrary();
      if (mounted) setState(() => _initialized = true);
    });
  }

  Future<void> _importFolder() async {
    final path = await FilePickerService.pickDirectory();
    if (path == null || path.isEmpty) return;
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );

    try {
      final added = await _localService.importFolder(path);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(added > 0 ? '已导入 $added 首本地歌曲' : '未发现新歌曲'),
      ));
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('导入失败: $e'),
      ));
    }
  }

  Future<void> _refresh() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );
    try {
      await _localService.refresh();
      await _localService.loadLibrary();
      if (!mounted) return;
      Navigator.pop(context);
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('刷新失败: $e')));
    }
  }

  void _playAll() {
    final songs = _localService.localSongs;
    if (songs.isEmpty) return;
    ref.read(playerServiceProvider).setPlaylist(List<MusicInfo>.from(songs), startIndex: 0);
  }

  void _playSong(int index) {
    final songs = _localService.localSongs;
    ref.read(playerServiceProvider).setPlaylist(List<MusicInfo>.from(songs), startIndex: index);
  }

  @override
  Widget build(BuildContext context) {
    final songs = _localService.localSongs;
    final scanning = _localService.isScanning;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('本地音乐${songs.isNotEmpty ? ' (${songs.length})' : ''}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (songs.isNotEmpty)
            IconButton(
              icon: Icon(Icons.play_circle_fill_rounded, color: AppColors.primary),
              tooltip: '播放全部',
              onPressed: _playAll,
            ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
            tooltip: '重新扫描',
            onPressed: _refresh,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: !_initialized || scanning
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : songs.isEmpty
              ? _buildEmpty()
              : _buildList(songs),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppNeumorphic.soft,
            ),
            child: Icon(Icons.library_music_rounded, size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          Text('还没有本地歌曲', style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text('导入文件夹，自动扫描歌曲与歌词',
            style: TextStyle(color: AppColors.textHint, fontSize: 12)),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _importFolder,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('导入文件夹', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<MusicInfo> songs) {
    return Column(
      children: [
        // 文件夹信息 + 导入按钮
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Icon(Icons.folder_rounded, color: AppColors.textHint, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _localService.folders.isEmpty
                      ? '未登记文件夹'
                      : '${_localService.folders.length} 个文件夹',
                  style: TextStyle(color: AppColors.textHint, fontSize: 11),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: _importFolder,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, color: AppColors.primary, size: 14),
                      SizedBox(width: 4),
                      Text('导入', style: TextStyle(color: AppColors.primary, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: songs.length,
            itemBuilder: (context, index) => _buildSongItem(songs[index], index),
          ),
        ),
      ],
    );
  }

  Widget _buildSongItem(MusicInfo song, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppNeumorphic.flat,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.music_note_rounded, color: AppColors.primary, size: 22),
        ),
        title: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(song.singer, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: AppColors.textHint, size: 18),
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'delete', child: Text('从列表移除')),
          ],
          onSelected: (value) async {
            if (value == 'delete') {
              // 只从列表移除，不删文件
              await _localService.removeSong(song.id);
              if (mounted) setState(() {});
            }
          },
        ),
        onTap: () => _playSong(index),
      ),
    );
  }
}
