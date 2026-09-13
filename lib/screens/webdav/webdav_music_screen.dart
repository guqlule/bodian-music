import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../models/music_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/webdav_provider.dart';
import '../../services/webdav/webdav_music_service.dart';
import '../../services/webdav/webdav_service.dart';

enum _SortMode { name, singer, addTime }

class WebdavMusicScreen extends ConsumerStatefulWidget {
  const WebdavMusicScreen({super.key});
  @override
  ConsumerState<WebdavMusicScreen> createState() => _WebdavMusicScreenState();
}

class _WebdavMusicScreenState extends ConsumerState<WebdavMusicScreen> {
  final WebdavMusicService _musicService = WebdavMusicService();
  String _searchQuery = '';
  _SortMode _sortMode = _SortMode.addTime;
  bool _sortAsc = false;
  final TextEditingController _searchCtrl = TextEditingController();
  bool _multiSelectMode = false;
  final Set<String> _selectedIds = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<MusicInfo> get _filteredSongs {
    var songs = List<MusicInfo>.from(_musicService.songs);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      songs = songs.where((s) =>
        s.name.toLowerCase().contains(q) ||
        s.singer.toLowerCase().contains(q) ||
        s.album.toLowerCase().contains(q)
      ).toList();
    }
    songs.sort((a, b) {
      int cmp;
      switch (_sortMode) {
        case _SortMode.name:
          cmp = a.name.compareTo(b.name);
        case _SortMode.singer:
          cmp = a.singer.compareTo(b.singer);
        case _SortMode.addTime:
          cmp = (a.addTime ?? DateTime(0)).compareTo(b.addTime ?? DateTime(0));
      }
      return _sortAsc ? cmp : -cmp;
    });
    return songs;
  }

  Future<void> _scanRemote() async {
    final state = ref.read(webdavConfigProvider);
    if (!state.isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中连接 WebDAV 服务器')),
      );
      return;
    }

    // 显示扫描进度
    if (!mounted) return;
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => _ScanProgressDialog(),
    );

    try {
      final count = await ref.read(webdavConfigProvider.notifier).scanRemote();
      if (!mounted) return;
      Navigator.pop(context); // 关闭进度弹窗
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描完成，共 $count 首歌曲'), backgroundColor: AppColors.primaryDark),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      final msg = e is WebdavException ? e.message : '扫描失败: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red, duration: const Duration(seconds: 4)),
      );
    }
  }

  void _playAll() {
    final songs = _filteredSongs;
    if (songs.isEmpty) return;
    ref.read(playerServiceProvider).setPlaylist(songs);
    ref.read(playerServiceProvider).playMusic(songs.first);
  }

  void _playSong(MusicInfo song) {
    ref.read(playerServiceProvider).setPlaylist(_filteredSongs);
    ref.read(playerServiceProvider).playMusic(song);
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) _multiSelectMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final songs = _filteredSongs;
    final state = ref.watch(webdavConfigProvider);

    return Scaffold(
      appBar: AppBar(
        title: _multiSelectMode
            ? Text('已选 ${_selectedIds.length} 首', style: TextStyle(color: AppColors.textPrimary))
            : Text('WebDAV 音乐库', style: TextStyle(color: AppColors.textPrimary)),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        actions: [
          if (_multiSelectMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all_rounded, size: 20),
              onPressed: () {
                setState(() {
                  if (_selectedIds.length == songs.length) {
                    _selectedIds.clear();
                  } else {
                    _selectedIds.addAll(songs.map((s) => s.id));
                  }
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.play_circle_filled_rounded, size: 20),
              onPressed: _selectedIds.isEmpty ? null : () {
                final selected = songs.where((s) => _selectedIds.contains(s.id)).toList();
                ref.read(playerServiceProvider).setPlaylist(selected);
                ref.read(playerServiceProvider).playMusic(selected.first);
                setState(() { _multiSelectMode = false; _selectedIds.clear(); });
              },
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () => setState(() { _multiSelectMode = false; _selectedIds.clear(); }),
            ),
          ] else ...[
            if (songs.isNotEmpty)
              PopupMenuButton<_SortMode>(
                icon: const Icon(Icons.sort_rounded, size: 20),
                onSelected: (m) => setState(() {
                  if (_sortMode == m) {
                    _sortAsc = !_sortAsc;
                  } else {
                    _sortMode = m;
                    _sortAsc = false;
                  }
                }),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: _SortMode.name, child: Text('按歌名')),
                  const PopupMenuItem(value: _SortMode.singer, child: Text('按歌手')),
                  const PopupMenuItem(value: _SortMode.addTime, child: Text('按添加时间')),
                ],
              ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: state.isConnected ? _scanRemote : null,
              tooltip: '扫描',
            ),
            IconButton(
              icon: const Icon(Icons.settings_rounded, size: 20),
              onPressed: () => context.push('/webdav-settings'),
            ),
          ],
        ],
      ),
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // 搜索栏
          if (songs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v),
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: '搜索歌曲...',
                  hintStyle: TextStyle(color: AppColors.textHint),
                  prefixIcon: Icon(Icons.search_rounded, color: AppColors.textHint, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); },
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

          // 信息栏
          if (songs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    _searchQuery.isEmpty
                        ? '${songs.length} 首歌曲'
                        : '搜索结果 ${songs.length} 首',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const Spacer(),
                  if (state.isConnected)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primaryDark.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('已连接', style: TextStyle(color: AppColors.primaryDark, fontSize: 10)),
                    ),
                ],
              ),
            ),

          // 歌曲列表
          Expanded(
            child: songs.isEmpty
                ? _buildEmpty(state)
                : _buildSongList(songs),
          ),
        ],
      ),
      floatingActionButton: songs.isNotEmpty
          ? FloatingActionButton(
              onPressed: _playAll,
              backgroundColor: AppColors.primaryDark,
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
            )
          : null,
    );
  }

  Widget _buildEmpty(WebdavConfigState state) {
    if (state.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primaryDark),
            const SizedBox(height: 16),
            Text('连接中...', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    if (!state.isConnected) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.textHint.withValues(alpha: 0.5)),
              ),
              const SizedBox(height: 20),
              Text('连接 WebDAV 服务器', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                '支持群晖、威联通、Nextcloud、Alist 等\n任何支持 WebDAV 协议的服务器',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => context.push('/webdav-settings'),
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text('配置服务器'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 已连接但没有歌曲
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primaryDark.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.cloud_queue_rounded, size: 40, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 20),
            Text('音乐库为空', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              '点击下方按钮扫描远程目录',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _scanRemote,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('开始扫描'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSongList(List<MusicInfo> songs) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        final isPlaying = ref.watch(currentMusicProvider).valueOrNull?.id == song.id;
        final isSelected = _selectedIds.contains(song.id);

        return ListTile(
          onLongPress: () {
            if (!_multiSelectMode) {
              setState(() {
                _multiSelectMode = true;
                _selectedIds.add(song.id);
              });
            }
          },
          onTap: _multiSelectMode ? () => _toggleSelect(song.id) : () => _playSong(song),
          leading: _multiSelectMode
              ? Icon(
                  isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: isSelected ? AppColors.primaryDark : AppColors.textHint,
                  size: 22,
                )
              : isPlaying
                  ? Icon(Icons.equalizer_rounded, color: AppColors.primaryDark, size: 20)
                  : SizedBox(
                      width: 24,
                      child: Text('${index + 1}', textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textHint, fontSize: 13)),
                    ),
          title: Text(
            song.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isPlaying ? AppColors.primaryDark : AppColors.textPrimary,
              fontSize: 14,
              fontWeight: isPlaying ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            [if (song.singer.isNotEmpty) song.singer, if (song.album.isNotEmpty) song.album].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          trailing: Icon(Icons.cloud_rounded, size: 14, color: AppColors.textHint.withValues(alpha: 0.4)),
        );
      },
    );
  }
}

/// 扫描进度弹窗
class _ScanProgressDialog extends StatefulWidget {
  @override
  State<_ScanProgressDialog> createState() => _ScanProgressDialogState();
}

class _ScanProgressDialogState extends State<_ScanProgressDialog> {
  @override
  void initState() {
    super.initState();
    _checkProgress();
  }

  void _checkProgress() async {
    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = WebdavMusicService();
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 48),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primaryDark),
            const SizedBox(height: 20),
            Text('扫描中...', style: TextStyle(
              color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (service.scanProgress != null)
              Text(
                service.scanProgress!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            const SizedBox(height: 8),
            Text(
              '已发现 ${service.totalFound} 首歌曲',
              style: TextStyle(color: AppColors.primaryDark, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
