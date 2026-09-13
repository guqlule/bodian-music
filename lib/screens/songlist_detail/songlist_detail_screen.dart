import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/music_model.dart';
import '../../models/playlist_model.dart';
import '../../providers/app_providers.dart';
import '../../services/api/songlist_service.dart';
import '../../core/theme/app_theme.dart';

class SonglistDetailScreen extends ConsumerStatefulWidget {
  final String songlistId;
  final String songlistName;
  final String source; // kw / tx

  const SonglistDetailScreen({
    super.key,
    required this.songlistId,
    required this.songlistName,
    this.source = 'kw',
  });

  @override
  ConsumerState<SonglistDetailScreen> createState() => _SonglistDetailScreenState();
}

class _SonglistDetailScreenState extends ConsumerState<SonglistDetailScreen> {
  final SonglistService _songlistService = SonglistService();
  List<MusicInfo> _songs = [];
  String _title = '';
  String _imgUrl = '';
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = widget.songlistName;
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() { _isLoading = true; _error = null; });

    try {
      final result = await _songlistService.getSonglistDetail(
        songlistId: widget.songlistId,
        source: widget.source,
      );

      if (result != null && mounted) {
        setState(() {
          _songs = result.songs;
          _title = result.name.isNotEmpty ? result.name : _title;
          _imgUrl = result.imgUrl.isNotEmpty ? result.imgUrl : _imgUrl;
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() { _isLoading = false; _error = '歌单加载失败'; });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  String get _favSonglistId => 'fav_${widget.source}_${widget.songlistId}';

  bool get _isSonglistFavorited =>
      ref.read(playlistProvider.notifier).getPlaylist(_favSonglistId) != null;

  void _toggleFavoriteSonglist() {
    final notifier = ref.read(playlistProvider.notifier);
    if (_isSonglistFavorited) {
      notifier.removePlaylist(_favSonglistId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已取消收藏歌单')));
    } else {
      final now = DateTime.now();
      final playlist = PlaylistInfo(
        id: _favSonglistId,
        name: _title.isNotEmpty ? _title : widget.songlistName,
        createTime: now,
        updateTime: now,
        songs: _songs,
        coverUrl: _imgUrl.isNotEmpty ? _imgUrl : null,
        description: '收藏的歌单',
      );
      notifier.addPlaylist(playlist);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已收藏歌单')));
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: AppColors.background,
            leading: IconButton(
              icon: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: AppNeumorphic.flat,
                ),
                child: Icon(Icons.arrow_back_ios_rounded, color: AppColors.textPrimary, size: 18),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              _songs.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: _toggleFavoriteSonglist,
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: _isSonglistFavorited ? AppColors.error : AppColors.card,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: AppNeumorphic.flat,
                          ),
                          child: Icon(
                            _isSonglistFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: _isSonglistFavorited ? Colors.white : AppColors.textSecondary,
                            size: 20,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
              _songs.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: GestureDetector(
                        onTap: () => ref.read(playerServiceProvider).setPlaylist(_songs),
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(_title.isNotEmpty ? _title : '歌单',
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 16)),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _imgUrl.isNotEmpty
                      ? Image.network(_imgUrl, cacheWidth: 600, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildCover())
                      : _buildCover(),
                  // 渐变遮罩
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, AppColors.background],
                        stops: [0.5, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading)
            SliverToBoxAdapter(
              child: SizedBox(height: 300, child: Center(
                child: CircularProgressIndicator(color: AppColors.primary))),
            )
          else if (_error != null)
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Container(
                        width: 64, height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: AppNeumorphic.soft,
                        ),
                        child: Icon(Icons.error_outline_rounded, size: 32, color: AppColors.error),
                      ),
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: _loadDetail,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: AppNeumorphic.soft,
                          ),
                          child: Text('重试', style: TextStyle(color: AppColors.primary, fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text('${_songs.length} 首歌曲', style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildSongItem(_songs[index], index),
                childCount: _songs.length,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSongItem(MusicInfo song, int index) {
    final isFav = ref.watch(favoritesProvider.notifier).isFavorite(song.id);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppNeumorphic.flat,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppColors.primarySoftColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text('${index + 1}', style: TextStyle(
              color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ),
        title: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
        subtitle: Text(song.singer, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        trailing: PopupMenuButton(
          icon: Icon(
            isFav ? Icons.favorite_rounded : Icons.more_vert_rounded,
            color: isFav ? AppColors.error : AppColors.textHint,
            size: 18,
          ),
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'play', child: Text('播放')),
            const PopupMenuItem(value: 'next', child: Text('下一首播放')),
            PopupMenuItem(
              value: 'favorite',
              child: Row(
                children: [
                  Icon(isFav ? Icons.favorite_border_rounded : Icons.favorite_rounded,
                      size: 18, color: AppColors.error),
                  const SizedBox(width: 8),
                  Text(isFav ? '取消喜欢' : '收藏'),
                ],
              ),
            ),
          ],
          onSelected: (value) async {
            if (value == 'play') {
              await ref.read(playerServiceProvider).setPlaylist(_songs, startIndex: index);
            } else if (value == 'next') {
              await ref.read(playerServiceProvider).addToTempPlaylist([song], isTop: true);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已添加到下一首')));
              }
            } else if (value == 'favorite') {
              ref.read(favoritesProvider.notifier).toggleFavorite(song);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(isFav ? '已取消喜欢' : '已添加到我喜欢')));
              }
            }
          },
        ),
        onTap: () async {
          await ref.read(playerServiceProvider).setPlaylist(_songs, startIndex: index);
        },
      ),
    );
  }

  Widget _buildCover() {
    return Container(
      color: AppColors.primarySoftColor,
      child: Center(
        child: Icon(Icons.queue_music_rounded, size: 64, color: AppColors.primary),
      ),
    );
  }
}
