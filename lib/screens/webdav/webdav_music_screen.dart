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
    final songsAsync = ref.read(webdavSongsProvider);
    var songs = List<MusicInfo>.from(songsAsync.valueOrNull ?? _musicService.songs);
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
              icon: const Icon(Icons.shuffle_rounded, size: 20),
              onPressed: songs.isNotEmpty
                  ? () {
                      final shuffled = List<MusicInfo>.from(songs)..shuffle();
                      ref.read(playerServiceProvider).setPlaylist(shuffled);
                      ref.read(playerServiceProvider).playMusic(shuffled.first);
                    }
                  : null,
              tooltip: '随机播放',
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
          trailing: _multiSelectMode
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_rounded, size: 14, color: AppColors.textHint.withValues(alpha: 0.4)),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(Icons.more_vert_rounded, color: AppColors.textHint, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _showSongActions(song),
                    ),
                  ],
                ),
        );
      },
    );
  }

  void _showSongActions(MusicInfo song) {
    final isFav = ref.read(favoritesProvider.notifier).isFavorite(song.id);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 36, height: 4,
              decoration: BoxDecoration(color: AppColors.textHint, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text([song.singer, song.album].where((s) => s.isNotEmpty).join(' · '),
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isFav ? AppColors.error : AppColors.primaryDark, size: 20),
              title: Text(isFav ? '取消喜欢' : '我喜欢',
                  style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
              onTap: () {
                ref.read(favoritesProvider.notifier).toggleFavorite(song);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(isFav ? '已取消喜欢' : '已添加到我喜欢')));
              },
            ),
            ListTile(
              leading: Icon(Icons.playlist_add_rounded, color: AppColors.primaryDark, size: 20),
              title: Text('添加到歌单', style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _showAddToPlaylist(song);
              },
            ),
            ListTile(
              leading: Icon(Icons.queue_music_rounded, color: AppColors.primaryDark, size: 20),
              title: Text('添加到播放队列', style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(playerServiceProvider).addToPlaylist(song);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已添加到播放队列')));
              },
            ),
            ListTile(
              leading: Icon(Icons.info_outline_rounded, color: AppColors.textSecondary, size: 20),
              title: Text('歌曲详情', style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _showSongDetail(song);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
              title: Text('从列表移除', style: TextStyle(fontSize: 14, color: AppColors.error)),
              onTap: () async {
                Navigator.pop(ctx);
                await ref.read(webdavConfigProvider.notifier).removeSong(song.id);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showAddToPlaylist(MusicInfo song) {
    final playlists = ref.read(playlistProvider);
    if (playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先创建歌单')));
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('选择歌单', style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
            ...playlists.map((p) => ListTile(
              leading: Icon(Icons.queue_music_rounded, color: AppColors.primaryDark, size: 20),
              title: Text(p.name, style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
              onTap: () {
                ref.read(playlistProvider.notifier).addToPlaylist(p.id, song);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已添加到 ${p.name}')));
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showSongDetail(MusicInfo song) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('歌曲详情', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('歌名', song.name),
            if (song.singer.isNotEmpty) _detailRow('歌手', song.singer),
            if (song.album.isNotEmpty) _detailRow('专辑', song.album),
            _detailRow('远程路径', song.songUrl ?? '未知'),
            if (song.duration > 0)
              _detailRow('时长', _fmtDuration(song.duration)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('关闭', style: TextStyle(color: AppColors.primaryDark))),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.textHint)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  String _fmtDuration(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m}:${s.toString().padLeft(2, '0')}';
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
