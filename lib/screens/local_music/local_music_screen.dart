import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/music_model.dart';
import '../../providers/app_providers.dart';
import '../../services/local/local_music_service.dart';
import '../../services/platform/file_picker_service.dart';
import '../../core/theme/app_theme.dart';

enum _SortMode { name, singer, addTime, fileName }

class LocalMusicScreen extends ConsumerStatefulWidget {
  const LocalMusicScreen({super.key});
  @override
  ConsumerState<LocalMusicScreen> createState() => _LocalMusicScreenState();
}

class _LocalMusicScreenState extends ConsumerState<LocalMusicScreen> {
  final LocalMusicService _localService = LocalMusicService();
  bool _initialized = false;
  String _searchQuery = '';
  _SortMode _sortMode = _SortMode.addTime;
  bool _sortAsc = false;
  final TextEditingController _searchCtrl = TextEditingController();
  bool _multiSelectMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _localService.loadLibrary();
      if (mounted) setState(() => _initialized = true);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<MusicInfo> get _filteredSongs {
    var songs = List<MusicInfo>.from(_localService.localSongs);
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
        case _SortMode.fileName:
          cmp = (a.songUrl ?? '').compareTo(b.songUrl ?? '');
      }
      return _sortAsc ? cmp : -cmp;
    });
    return songs;
  }

  Future<void> _importFolder() async {
    final path = await FilePickerService.pickDirectory();
    if (path == null || path.isEmpty) return;
    if (!mounted) return;
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator(color: AppColors.primary)));
    try {
      final added = await _localService.importFolder(path);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(added > 0 ? '已导入 $added 首本地歌曲' : '未发现新歌曲')));
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  Future<void> _refresh() async {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator(color: AppColors.primary)));
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

  void _showFolderManager() {
    final folders = _localService.folders;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 36, height: 4,
              decoration: BoxDecoration(color: AppColors.textHint, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text('文件夹管理', style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () { Navigator.pop(ctx); _importFolder(); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add_rounded, color: Colors.white, size: 14),
                        const SizedBox(width: 3),
                        Text('添加', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: folders.isEmpty
                  ? Center(child: Text('暂无文件夹', style: TextStyle(color: AppColors.textHint)))
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: folders.length,
                      itemBuilder: (ctx, i) {
                        final folder = folders[i];
                        final shortPath = folder.split(Platform.pathSeparator).last;
                        final songCount = _localService.localSongs
                            .where((s) => s.songUrl?.startsWith(folder) ?? false).length;
                        return ListTile(
                          leading: Icon(Icons.folder_rounded, color: AppColors.primary, size: 20),
                          title: Text(shortPath, style: TextStyle(
                            fontSize: 14, color: AppColors.textPrimary),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('$songCount 首歌曲', style: TextStyle(
                            fontSize: 12, color: AppColors.textHint)),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 18),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: AppColors.card,
                                  title: Text('移除文件夹', style: TextStyle(color: AppColors.textPrimary)),
                                  content: Text('将移除 "$shortPath" 及其 $songCount 首歌曲（不会删除文件）',
                                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false),
                                      child: Text('取消', style: TextStyle(color: AppColors.textSecondary))),
                                    TextButton(onPressed: () => Navigator.pop(ctx, true),
                                      child: Text('移除', style: TextStyle(color: AppColors.error))),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await _localService.removeFolder(folder);
                                if (mounted) setState(() {});
                              }
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _batchAction(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  String _formatDuration(int ms) {
    if (ms <= 0) return '';
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m}:${s.toString().padLeft(2, '0')}';
  }

  int get _totalDuration => _filteredSongs.fold(0, (sum, s) => sum + s.duration);

  void _playAll() {
    final songs = _filteredSongs;
    if (songs.isEmpty) return;
    ref.read(playerServiceProvider).setPlaylist(songs, startIndex: 0);
  }

  void _shufflePlay() {
    final songs = _filteredSongs;
    if (songs.isEmpty) return;
    final shuffled = List<MusicInfo>.from(songs)..shuffle();
    ref.read(playerServiceProvider).setPlaylist(shuffled, startIndex: 0);
  }

  void _playSong(int index) {
    final songs = _filteredSongs;
    ref.read(playerServiceProvider).setPlaylist(songs, startIndex: index);
  }

  void _showSortDialog() {
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
              child: Text('排序方式', style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
            _buildSortTile('按歌手', Icons.person_outline_rounded, _SortMode.singer),
            _buildSortTile('按歌名', Icons.title_rounded, _SortMode.name),
            _buildSortTile('按文件名', Icons.description_outlined, _SortMode.fileName),
            _buildSortTile('按添加时间', Icons.access_time_rounded, _SortMode.addTime),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_sortAsc ? '升序' : '降序',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                  ),
                  Switch(
                    value: _sortAsc,
                    onChanged: (v) { setState(() => _sortAsc = v); Navigator.pop(ctx); },
                    activeThumbColor: AppColors.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildSortTile(String label, IconData icon, _SortMode mode) {
    final selected = _sortMode == mode;
    return ListTile(
      leading: Icon(icon, color: selected ? AppColors.primary : AppColors.textSecondary, size: 20),
      title: Text(label, style: TextStyle(
        color: selected ? AppColors.primary : AppColors.textPrimary,
        fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      trailing: selected ? Icon(Icons.check_rounded, color: AppColors.primary, size: 18) : null,
      onTap: () { setState(() => _sortMode = mode); Navigator.pop(context); },
    );
  }

  void _toggleMultiSelect(String songId) {
    setState(() {
      if (_selectedIds.contains(songId)) {
        _selectedIds.remove(songId);
        if (_selectedIds.isEmpty) _multiSelectMode = false;
      } else {
        _selectedIds.add(songId);
      }
    });
  }

  void _enterMultiSelect(String songId) {
    setState(() {
      _multiSelectMode = true;
      _selectedIds.add(songId);
    });
  }

  void _exitMultiSelect() {
    setState(() {
      _multiSelectMode = false;
      _selectedIds.clear();
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == _filteredSongs.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(_filteredSongs.map((s) => s.id));
      }
    });
  }

  List<MusicInfo> get _selectedSongs =>
      _filteredSongs.where((s) => _selectedIds.contains(s.id)).toList();

  void _batchPlayAll() {
    final songs = _selectedSongs;
    if (songs.isEmpty) return;
    _exitMultiSelect();
    ref.read(playerServiceProvider).setPlaylist(songs, startIndex: 0);
  }

  void _batchAddToFavorites() {
    final songs = _selectedSongs;
    final favorites = ref.read(favoritesProvider.notifier);
    for (final song in songs) {
      favorites.toggleFavorite(song);
    }
    _exitMultiSelect();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已将 ${songs.length} 首歌曲添加到收藏')));
  }

  void _batchAddToPlaylist() {
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
              child: Text('添加 ${_selectedSongs.length} 首到歌单', style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
            ...playlists.map((p) => ListTile(
              leading: Icon(Icons.queue_music_rounded, color: AppColors.primary, size: 20),
              title: Text(p.name, style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                for (final song in _selectedSongs) {
                  ref.read(playlistProvider.notifier).addToPlaylist(p.id, song);
                }
                _exitMultiSelect();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已将 ${_selectedSongs.length} 首添加到 ${p.name}')));
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _batchRemove() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('移除 ${_selectedSongs.length} 首歌曲', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('从列表中移除（不会删除文件）', style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: TextStyle(color: AppColors.textSecondary))),
          TextButton(onPressed: () async {
            Navigator.pop(ctx);
            for (final song in _selectedSongs) {
              await _localService.removeSong(song.id);
            }
            _exitMultiSelect();
            if (mounted) setState(() {});
          }, child: Text('移除', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
  }

  void _showSongActions(MusicInfo song) {
    final isFavorited = ref.read(favoritesProvider).any((f) => f.id == song.id);
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
                  Text(song.name, style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text('${song.singer} · ${_getFileType(song.songUrl)}${song.duration > 0 ? ' · ${_formatDuration(song.duration)}' : ''}',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                isFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isFavorited ? AppColors.error : AppColors.primary, size: 20),
              title: Text(isFavorited ? '取消收藏' : '添加到收藏',
                style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(favoritesProvider.notifier).toggleFavorite(song);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(isFavorited ? '已取消收藏' : '已添加到收藏')));
              },
            ),
            ListTile(
              leading: Icon(Icons.playlist_add_rounded, color: AppColors.primary, size: 20),
              title: Text('添加到歌单', style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _showAddToPlaylist(song);
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
              leading: Icon(Icons.queue_music_rounded, color: AppColors.primary, size: 20),
              title: Text('添加到播放队列', style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(playerServiceProvider).addToPlaylist(song);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已添加到播放队列')));
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
              title: Text('从列表移除', style: TextStyle(fontSize: 14, color: AppColors.error)),
              onTap: () async {
                Navigator.pop(ctx);
                await _localService.removeSong(song.id);
                if (mounted) setState(() {});
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
              leading: Icon(Icons.queue_music_rounded, color: AppColors.primary, size: 20),
              title: Text(p.name, style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(playlistProvider.notifier).addToPlaylist(p.id, song);
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
            _detailRow('歌手', song.singer),
            _detailRow('专辑', song.album),
            _detailRow('格式', _getFileType(song.songUrl)),
            _detailRow('文件大小', _getFileSize(song.songUrl)),
            if (song.duration > 0) _detailRow('时长', _formatDuration(song.duration)),
            _detailRow('路径', song.songUrl ?? '未知'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: Text('关闭', style: TextStyle(color: AppColors.primary))),
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

  String _getFileType(String? path) {
    if (path == null) return '未知';
    final ext = path.split('.').last.toLowerCase();
    return ext.toUpperCase();
  }

  String _getFileSize(String? path) {
    if (path == null) return '未知';
    try {
      final size = File(path).lengthSync();
      if (size < 1024) return '$size B';
      if (size < 1048576) return '${(size / 1024).toStringAsFixed(1)} KB';
      if (size < 1073741824) return '${(size / 1048576).toStringAsFixed(1)} MB';
      return '${(size / 1073741824).toStringAsFixed(1)} GB';
    } catch (_) {
      return '未知';
    }
  }

  @override
  Widget build(BuildContext context) {
    final songs = _filteredSongs;
    final totalSongs = _localService.localSongs.length;
    final scanning = _localService.isScanning;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: _multiSelectMode
            ? Text('已选 ${_selectedIds.length} 首')
            : Text('本地音乐${totalSongs > 0 ? ' ($totalSongs)' : ''}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: _multiSelectMode ? _exitMultiSelect : () => Navigator.pop(context),
        ),
        actions: [
          if (_multiSelectMode) ...[
            IconButton(
              icon: Icon(
                _selectedIds.length == _filteredSongs.length
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
                color: AppColors.primary),
              tooltip: _selectedIds.length == _filteredSongs.length ? '取消全选' : '全选',
              onPressed: _selectAll,
            ),
          ] else ...[
            if (totalSongs > 0)
              IconButton(
                icon: Icon(Icons.play_circle_fill_rounded, color: AppColors.primary),
                tooltip: '播放全部',
                onPressed: _playAll,
              ),
            if (totalSongs > 0)
              IconButton(
                icon: Icon(Icons.shuffle_rounded, color: AppColors.primary),
                tooltip: '随机播放',
                onPressed: _shufflePlay,
              ),
            IconButton(
              icon: Icon(Icons.sort_rounded, color: AppColors.textSecondary),
              tooltip: '排序',
              onPressed: _showSortDialog,
            ),
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
              tooltip: '重新扫描',
              onPressed: _refresh,
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
      body: !_initialized || scanning
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  if (scanning && _localService.scanProgress != null) ...[
                    const SizedBox(height: 16),
                    Text(_localService.scanProgress!,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ],
              ),
            )
          : totalSongs == 0
              ? _buildEmpty()
              : Column(
                  children: [
                    // 搜索栏
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (v) => setState(() => _searchQuery = v),
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: '搜索本地歌曲...',
                          hintStyle: TextStyle(color: AppColors.textHint, fontSize: 13),
                          prefixIcon: Icon(Icons.search_rounded, color: AppColors.textHint, size: 20),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.close_rounded, color: AppColors.textHint, size: 18),
                                  onPressed: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); },
                                )
                              : null,
                          filled: true,
                          fillColor: AppColors.card,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    // 文件夹信息
                    GestureDetector(
                      onTap: _showFolderManager,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Row(
                          children: [
                            Icon(Icons.folder_rounded, color: AppColors.textHint, size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${_localService.folders.length} 个文件夹 · ${songs.length} 首${_searchQuery.isNotEmpty ? "（筛选结果）" : ""}'
                                '${_totalDuration > 0 ? " · ${_formatDuration(_totalDuration)}" : ""}',
                                style: TextStyle(color: AppColors.textHint, fontSize: 11),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 16),
                          ],
                        ),
                      ),
                    ),
                    // 歌曲列表
                    Expanded(
                      child: songs.isEmpty
                          ? Center(child: Text('无匹配结果',
                              style: TextStyle(color: AppColors.textHint, fontSize: 14)))
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: songs.length,
                              itemBuilder: (context, index) => _buildSongItem(songs[index], index),
                            ),
                    ),
                    // 批量操作栏
                    if (_multiSelectMode)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          boxShadow: [
                            BoxShadow(color: Colors.black26, blurRadius: 8, offset: const Offset(0, -2)),
                          ],
                        ),
                        child: SafeArea(
                          top: false,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _batchAction(Icons.play_circle_fill_rounded, '播放', _batchPlayAll),
                              _batchAction(Icons.favorite_rounded, '收藏', _batchAddToFavorites),
                              _batchAction(Icons.playlist_add_rounded, '歌单', _batchAddToPlaylist),
                              _batchAction(Icons.delete_outline_rounded, '移除', _batchRemove),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
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
              color: AppColors.primarySoftColor,
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
                boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 8, offset: const Offset(0, 2))],
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

  Widget _buildSongItem(MusicInfo song, int index) {
    final currentMusic = ref.watch(currentMusicProvider).valueOrNull;
    final isPlaying = currentMusic?.id == song.id;
    final isSelected = _selectedIds.contains(song.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primary.withValues(alpha: 0.15)
            : isPlaying ? AppColors.primarySoftColor : AppColors.card,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppNeumorphic.flat,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        leading: _multiSelectMode
            ? GestureDetector(
                onTap: () => _toggleMultiSelect(song.id),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.primarySoftColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: isSelected
                      ? Icon(Icons.check_rounded, color: Colors.white, size: 20)
                      : Icon(Icons.music_note_rounded, color: AppColors.primary, size: 20),
                ),
              )
            : Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: isPlaying ? AppColors.primary : AppColors.primarySoftColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: isPlaying
                    ? Icon(Icons.equalizer_rounded, color: Colors.white, size: 20)
                    : Icon(Icons.music_note_rounded, color: AppColors.primary, size: 20),
              ),
        title: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isPlaying ? AppColors.primary : AppColors.textPrimary,
            fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(
          '${song.singer} · ${_getFileType(song.songUrl)}${song.duration > 0 ? ' · ${_formatDuration(song.duration)}' : ''}',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        trailing: _multiSelectMode
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.more_vert_rounded, color: AppColors.textHint, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _showSongActions(song),
                  ),
                ],
              ),
        onTap: _multiSelectMode
            ? () => _toggleMultiSelect(song.id)
            : () => _playSong(index),
        onLongPress: _multiSelectMode ? null : () => _enterMultiSelect(song.id),
      ),
    );
  }
}
