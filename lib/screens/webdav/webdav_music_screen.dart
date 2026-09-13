import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../models/music_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/webdav_provider.dart';
import '../../services/webdav/webdav_music_service.dart';

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
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _musicService.loadLibrary();
      if (mounted) setState(() => _initialized = true);
    });
  }

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

    showDialog(context: context, barrierDismissible: false,
      builder: (_) => Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 16),
          Text('扫描中...', style: TextStyle(color: Colors.white)),
        ],
      )),
    );

    try {
      final count = await ref.read(webdavConfigProvider.notifier).scanRemote();
      if (!mounted) return;
      Navigator.pop(context);
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描完成，共 $count 首歌曲')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描失败: $e'), backgroundColor: Colors.red),
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
          ] else ...[
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: _scanRemote,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: '搜索 WebDAV 歌曲...',
                hintStyle: TextStyle(color: AppColors.textHint),
                prefixIcon: Icon(Icons.search_rounded, color: AppColors.textHint, size: 20),
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
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('${songs.length} 首歌曲', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const Spacer(),
                  if (!state.isConnected)
                    Text('未连接', style: TextStyle(color: Colors.red.withValues(alpha: 0.7), fontSize: 12)),
                ],
              ),
            ),

          // 歌曲列表
          Expanded(
            child: songs.isEmpty
                ? _buildEmpty()
                : _buildSongList(songs),
          ),
        ],
      ),
      floatingActionButton: songs.isNotEmpty
          ? FloatingActionButton(
              onPressed: _playAll,
              backgroundColor: AppColors.primaryDark,
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildEmpty() {
    final state = ref.watch(webdavConfigProvider);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 64, color: AppColors.textHint.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            state.isConnected ? '扫描远程目录以发现音乐' : '请先连接 WebDAV 服务器',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: state.isConnected ? _scanRemote : () => context.push('/webdav-settings'),
            icon: Icon(state.isConnected ? Icons.refresh_rounded : Icons.settings_rounded, size: 18),
            label: Text(state.isConnected ? '开始扫描' : '去设置'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryDark,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
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
            setState(() {
              _multiSelectMode = true;
              _selectedIds.add(song.id);
            });
          },
          onTap: _multiSelectMode ? () => _toggleSelect(song.id) : () => _playSong(song),
          leading: _multiSelectMode
              ? Icon(
                  isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isSelected ? AppColors.primaryDark : AppColors.textHint,
                )
              : isPlaying
                  ? Icon(Icons.equalizer_rounded, color: AppColors.primaryDark, size: 20)
                  : Text('${index + 1}', style: TextStyle(color: AppColors.textHint, fontSize: 13)),
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
            '${song.singer}${song.album.isNotEmpty ? ' · ${song.album}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          trailing: Text(
            'WebDAV',
            style: TextStyle(color: AppColors.textHint.withValues(alpha: 0.5), fontSize: 10),
          ),
        );
      },
    );
  }
}
