import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/music_model.dart';
import '../../models/playlist_model.dart';
import '../../providers/music_providers.dart';
import '../../providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/logger.dart';
import '../../services/player/player_service.dart' show PlayMode;
import '../../services/api/songlist_service.dart';
import '../../services/api/music_search_service.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final String playlistId;
  final String playlistName;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    required this.playlistName,
  });

  @override
  ConsumerState<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  bool _importing = false;
  String? _importError;
  final SonglistService _songlistService = SonglistService();
  TextEditingController? _sheetSearchController;

  @override
  void initState() {
    super.initState();
    // 导入的歌单（import_tx_* / import_wy_*）首次打开自动拉取完整歌曲列表；
    // 网易歌单若只有 ≤10 首（旧接口时代导入的截断数据），自动重新拉取补全
    final id = widget.playlistId;
    if (id.startsWith('import_tx_')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoImportSongs());
    } else if (id.startsWith('import_wy_')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoImportSongs(
            source: 'wy',
            id: id.replaceFirst('import_wy_', ''),
            refreshIfIncomplete: true,
          ));
    }
  }

  @override
  void dispose() {
    _sheetSearchController?.dispose();
    super.dispose();
  }

  Future<void> _autoImportSongs({String source = 'tx', String? id, bool refreshIfIncomplete = false}) async {
    final playlist = ref.read(playlistProvider.notifier).getPlaylist(widget.playlistId);
    if (playlist == null || _importing) return;
    // refreshIfIncomplete：已有歌曲但数量可疑（≤10 首，旧接口截断）时也刷新
    if (playlist.songs.isNotEmpty && !(refreshIfIncomplete && playlist.songs.length <= 10)) return;
    final hasSongs = playlist.songs.isNotEmpty;
    setState(() { _importing = true; _importError = null; });

    final targetId = id ?? widget.playlistId.replaceFirst('import_tx_', '');
    final detail = source == 'wy'
        ? await _songlistService.getWYPlaylistDetail(targetId)
        : await _songlistService.getQQPlaylistDetail(targetId);
    if (!mounted) return;

    if (detail != null && detail.songs.isNotEmpty) {
      var songs = detail.songs;
      // TX 导入歌单：搜索其他音源替换（kw/kg/wy 可播放）
      if (source == 'tx' && songs.isNotEmpty) {
        songs = await _replaceWithOtherSource(songs);
      }
      final updated = ref.read(playlistProvider.notifier).getPlaylist(widget.playlistId);
      if (updated != null) {
        updated.songs
          ..clear()
          ..addAll(songs);
        updated.updateTime = DateTime.now();
        ref.read(playlistProvider.notifier).updatePlaylist(updated);
      }
      setState(() => _importing = false);
    } else {
      setState(() {
        _importing = false;
        // 已有歌曲时刷新失败不报错（保留现有内容），只对空歌单提示
        _importError = hasSongs ? null : '歌曲拉取失败，请检查网络后重试';
      });
    }
  }

  Future<List<MusicInfo>> _replaceWithOtherSource(List<MusicInfo> txSongs) async {
    final searchService = MusicSearchService();
    const sources = ['kw', 'kg', 'wy'];

    final futures = txSongs.map((txSong) async {
      try {
        final keyword = '${txSong.name} ${txSong.singer}'.trim();
        if (keyword.isEmpty) return txSong;

        final results = await Future.wait(
          sources.map((src) async {
            try {
              final result = await searchService.search(
                keyword: keyword,
                source: src,
                page: 1,
                pageSize: 3,
              );
              return result.list;
            } catch (_) {
              return <MusicInfo>[];
            }
          }),
        );

        for (final list in results) {
          for (final candidate in list) {
            if (_isSongMatch(txSong, candidate)) {
              logDebug('[TX导入换源] ${txSong.name} -> ${candidate.name} (${candidate.source})');
              return candidate;
            }
          }
        }
        for (final list in results) {
          if (list.isNotEmpty) {
            logDebug('[TX导入换源] ${txSong.name} -> ${list.first.name} (${list.first.source}) [模糊]');
            return list.first;
          }
        }
      } catch (e) {
        logDebug('[TX导入换源] 搜索失败: ${txSong.name} - $e');
      }
      return txSong;
    });

    return Future.wait(futures);
  }

  bool _isSongMatch(MusicInfo a, MusicInfo b) {
    final nameA = a.name.toLowerCase().replaceAll(RegExp(r'[\s\-_（）()【】\[\]]'), '');
    final nameB = b.name.toLowerCase().replaceAll(RegExp(r'[\s\-_（）()【】\[\]]'), '');
    if (nameA.isEmpty || nameB.isEmpty) return false;
    final nameOk = nameA == nameB || nameA.contains(nameB) || nameB.contains(nameA);
    if (!nameOk) return false;

    final singerA = a.singer.split(RegExp(r'[、/,]')).first.toLowerCase().trim();
    final singerB = b.singer.split(RegExp(r'[、/,]')).first.toLowerCase().trim();
    if (singerA.isEmpty || singerB.isEmpty) return true;
    return singerA == singerB || singerA.contains(singerB) || singerB.contains(singerA);
  }

  @override
  Widget build(BuildContext context) {
    final playlist = ref.watch(playlistProvider.notifier).getPlaylist(widget.playlistId);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlistName),
        actions: [
          if (playlist != null && playlist.songs.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.shuffle_rounded),
              onPressed: _shuffle,
              tooltip: '随机播放',
            ),
            IconButton(
              icon: const Icon(Icons.play_circle_filled),
              onPressed: _playAll,
              tooltip: '播放全部',
            ),
            PopupMenuButton(
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'sort', child: Text('排序')),
                const PopupMenuItem(value: 'clear', child: Text('清空列表')),
              ],
              onSelected: _handleMenuAction,
            ),
          ],
        ],
      ),
      body: _importing
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 16),
                  Text('正在获取歌单歌曲...',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            )
          : _importError != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_importError!,
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () {
                          setState(() => _importError = null);
                          _autoImportSongs();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: AppNeumorphic.soft,
                          ),
                          child: Text('重试',
                              style: TextStyle(
                                  color: AppColors.primary, fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                )
              : _buildBody(playlist),
      floatingActionButton: _importing
          ? null
          : FloatingActionButton(
              onPressed: _showAddSongsDialog,
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _buildBody(PlaylistInfo? playlist) {
    if (playlist == null || playlist.songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.queue_music, size: 64, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text('列表为空',
                style: TextStyle(fontSize: 18, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Text('点击右下角按钮添加歌曲',
                style: TextStyle(color: AppColors.textHint)),
          ],
        ),
      );
    }

    final totalDuration = playlist.songs.fold<int>(0, (sum, s) => sum + s.duration);
    final totalMin = totalDuration ~/ 60000;

    return Column(
      children: [
        // 歌单头部信息
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              // 封面
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primarySoftColor,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: AppNeumorphic.flat,
                ),
                child: playlist.coverUrl != null && playlist.coverUrl!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(playlist.coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(Icons.queue_music_rounded,
                            color: AppColors.primary, size: 28)),
                      )
                    : Icon(Icons.queue_music_rounded, color: AppColors.primary, size: 28),
              ),
              const SizedBox(width: 12),
              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(playlist.name,
                      style: TextStyle(color: AppColors.textPrimary,
                        fontSize: 15, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(
                      '${playlist.songs.length} 首歌曲${totalMin > 0 ? " · ${totalMin}分钟" : ""}',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              // 播放全部
              GestureDetector(
                onTap: _playAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 4),
                    Text('播放', style: TextStyle(color: Colors.white,
                      fontSize: 13, fontWeight: FontWeight.w500)),
                  ]),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.divider),
        // 歌曲列表
        Expanded(
          child: ReorderableListView.builder(
            itemCount: playlist.songs.length,
            onReorder: (oldIndex, newIndex) {
              _reorderSong(playlist, oldIndex, newIndex);
            },
            itemBuilder: (context, index) {
              final song = playlist.songs[index];
              return _buildSongItem(song, index, playlist);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSongItem(MusicInfo song, int index, PlaylistInfo playlist) {
    final isPlaying = ref.watch(currentMusicProvider).when(
      data: (current) => current?.id == song.id,
      loading: () => false,
      error: (_, __) => false,
    );

    return Dismissible(
      key: Key(song.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: AppColors.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await _showDeleteConfirmDialog(song);
      },
      onDismissed: (direction) {
        _removeSong(song);
      },
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isPlaying ? AppColors.primary : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: song.imgUrl != null
                  ? Image.network(
                      song.imgUrl!,
                      cacheWidth: 80,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildDefaultThumbnail();
                      },
                    )
                  : _buildDefaultThumbnail(),
            ),
          ],
        ),
        title: Text(
          song.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isPlaying ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          '${song.singer} - ${song.album}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPlaying)
              Icon(Icons.equalizer, color: AppColors.primary),
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showSongOptions(song),
            ),
          ],
        ),
        onTap: () => _playSong(song),
      ),
    );
  }

  Widget _buildDefaultThumbnail() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.primarySoftColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        Icons.music_note,
        color: AppColors.primary,
        size: 20,
      ),
    );
  }

  void _playAll() async {
    final playlist = ref.read(playlistProvider.notifier).getPlaylist(widget.playlistId);
    if (playlist == null || playlist.songs.isEmpty) return;

    final playerService = ref.read(playerServiceProvider);
    await playerService.setPlaylist(playlist.songs);
  }

  void _shuffle() async {
    final playlist = ref.read(playlistProvider.notifier).getPlaylist(widget.playlistId);
    if (playlist == null || playlist.songs.isEmpty) return;

    final playerService = ref.read(playerServiceProvider);
    await playerService.setPlayMode(PlayMode.random);
    await playerService.setPlaylist(playlist.songs);
    await playerService.playMusic(playlist.songs.first);
  }

  void _playSong(MusicInfo song) async {
    final playlist = ref.read(playlistProvider.notifier).getPlaylist(widget.playlistId);
    if (playlist == null) return;

    final playerService = ref.read(playerServiceProvider);
    final index = playlist.songs.indexWhere((s) => s.id == song.id);
    if (index != -1) {
      await playerService.setPlaylist(playlist.songs, startIndex: index);
    }
  }

  void _reorderSong(PlaylistInfo playlist, int oldIndex, int newIndex) {
    playlist.reorderSong(oldIndex, newIndex);
    ref.read(playlistProvider.notifier).updatePlaylist(playlist);
  }

  void _removeSong(MusicInfo song) {
    final playlist = ref.read(playlistProvider.notifier).getPlaylist(widget.playlistId);
    if (playlist == null) return;

    playlist.removeSong(song.id);
    ref.read(playlistProvider.notifier).updatePlaylist(playlist);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已从列表移除 "${song.name}"'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            playlist.addSong(song);
            ref.read(playlistProvider.notifier).updatePlaylist(playlist);
          },
        ),
      ),
    );
  }

  Future<bool> _showDeleteConfirmDialog(MusicInfo song) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认删除'),
            content: Text('确定要从列表移除 "${song.name}" 吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showSongOptions(MusicInfo song) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('播放'),
              onTap: () {
                Navigator.pop(context);
                _playSong(song);
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_outlined),
              title: const Text('添加到播放队列'),
              onTap: () {
                Navigator.pop(context);
                ref.read(playerServiceProvider).addToQueue(song);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已添加到播放队列')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('从列表移除'),
              onTap: () {
                Navigator.pop(context);
                _removeSong(song);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'sort':
        _showSortDialog();
        break;
      case 'clear':
        _showClearPlaylistDialog();
        break;
    }
  }

  void _showSortDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('排序方式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.schedule_rounded, color: AppColors.primary),
              title: const Text('按添加时间'),
              onTap: () {
                Navigator.pop(context);
                _sortPlaylist((a, b) =>
                    (a.addTime ?? DateTime(1970)).compareTo(b.addTime ?? DateTime(1970)));
              },
            ),
            ListTile(
              leading: Icon(Icons.text_fields_rounded, color: AppColors.primary),
              title: const Text('按歌曲名称'),
              onTap: () {
                Navigator.pop(context);
                _sortPlaylist((a, b) => a.name.compareTo(b.name));
              },
            ),
            ListTile(
              leading: Icon(Icons.person_rounded, color: AppColors.primary),
              title: const Text('按歌手名称'),
              onTap: () {
                Navigator.pop(context);
                _sortPlaylist((a, b) => a.singer.compareTo(b.singer));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _sortPlaylist(int Function(MusicInfo a, MusicInfo b) compare) {
    final playlist = ref.read(playlistProvider.notifier).getPlaylist(widget.playlistId);
    if (playlist == null) return;
    playlist.songs.sort(compare);
    playlist.updateTime = DateTime.now();
    ref.read(playlistProvider.notifier).updatePlaylist(playlist);
  }

  void _showClearPlaylistDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空列表'),
        content: const Text('确定要清空列表中的所有歌曲吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final playlist =
                  ref.read(playlistProvider.notifier).getPlaylist(widget.playlistId);
              if (playlist != null) {
                playlist.songs.clear();
                playlist.updateTime = DateTime.now();
                ref.read(playlistProvider.notifier).updatePlaylist(playlist);
              }
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  void _showAddSongsDialog() {
    // controller 放在 State 字段（不随搜索状态重建，否则输入被重置）
    _sheetSearchController ??= TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Consumer(
        builder: (context, sheetRef, _) {
          final searchState = sheetRef.watch(musicSearchProvider);
          final notifier = sheetRef.read(musicSearchProvider.notifier);
          final controller = _sheetSearchController!;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.75,
              child: Column(
                children: [
                  // 搜索栏
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (kw) => notifier.search(kw),
                      decoration: InputDecoration(
                        hintText: '搜索歌曲添加到列表',
                        hintStyle: TextStyle(
                            color: AppColors.textHint, fontSize: 13),
                        prefixIcon: Icon(Icons.search_rounded,
                            color: AppColors.textSecondary, size: 20),
                        filled: true,
                        fillColor: AppColors.card,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  // 结果列表
                  Expanded(
                    child: searchState.isLoading
                        ? Center(
                            child: CircularProgressIndicator(
                                color: AppColors.primary))
                        : searchState.results.isEmpty
                            ? Center(
                                child: Text(
                                  searchState.query.isEmpty
                                      ? '输入关键词搜索歌曲'
                                      : searchState.error ?? '未找到相关歌曲',
                                  style: TextStyle(
                                      color: AppColors.textHint, fontSize: 13),
                                ),
                              )
                            : ListView.builder(
                                itemCount: searchState.results.length,
                                itemBuilder: (context, i) {
                                  final song = searchState.results[i];
                                  final added = ref
                                      .read(playlistProvider.notifier)
                                      .getPlaylist(widget.playlistId)
                                      ?.songs
                                      .any((s) => s.id == song.id) ??
                                      false;
                                  return ListTile(
                                    dense: true,
                                    leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: song.imgUrl != null
                                          ? Image.network(song.imgUrl!,
                                              cacheWidth: 88,
                                              width: 44,
                                              height: 44,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  _defaultThumb())
                                          : _defaultThumb(),
                                    ),
                                    title: Text(song.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 13.5)),
                                    subtitle: Text(song.singer,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 11.5)),
                                    trailing: added
                                        ? Icon(Icons.check_circle_rounded,
                                            color: AppColors.success, size: 20)
                                        : Icon(
                                            Icons.add_circle_outline_rounded,
                                            color: AppColors.primary,
                                            size: 22),
                                    onTap: () {
                                      if (added) return;
                                      ref
                                          .read(playlistProvider.notifier)
                                          .addToPlaylist(
                                              widget.playlistId, song);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content:
                                                  Text('已添加「${song.name}」')));
                                    },
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _defaultThumb() {
    return Container(
      width: 44, height: 44,
      color: AppColors.primarySoftColor,
      child: Icon(Icons.music_note_rounded, color: AppColors.primary, size: 20),
    );
  }
}
