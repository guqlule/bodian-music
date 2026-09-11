import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/music_model.dart';
import '../../providers/app_providers.dart';
import '../../services/api/board_service.dart';
import '../../core/theme/app_theme.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  String _currentSource = 'kw';
  bool _isLoading = false;
  String? _error;
  List<MusicInfo> _songs = [];

  final BoardService _boardService = BoardService();

  List<BoardInfo> get _boards => _boardService.boards(_currentSource);
  BoardInfo get _currentBoard {
    final safeIndex = _tabIndex.clamp(0, _boards.length - 1);
    return _boards[safeIndex];
  }
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final board = _currentBoard;
      final songs = await _boardService.getBoardSongs(_currentSource, board.id);
      if (!mounted) return;
      setState(() {
        _songs = songs;
        _isLoading = false;
        if (songs.isEmpty) _error = '榜单获取失败，请稍后重试';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('排行榜'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // 音源选择
          _buildSourceSelector(),
          // 榜单 Tab
          _buildBoardTabs(),
          // 歌曲列表
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildSourceSelector() {
    final sources = [
      {'id': 'kw', 'name': '源一'}, {'id': 'wy', 'name': '源四'}, {'id': 'tx', 'name': '源三'},
    ];
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: sources.map((source) {
          final isSelected = _currentSource == source['id'];
          return Padding(
            padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _currentSource = source['id']!;
                  _tabIndex = 0;
                });
                _loadLeaderboard();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected ? [] : AppNeumorphic.flat,
                ),
                child: Center(child: Text(source['name']!, style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                  fontSize: 12, fontWeight: FontWeight.w500))),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBoardTabs() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (int i = 0; i < _boards.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () {
                  setState(() => _tabIndex = i);
                  _loadLeaderboard();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: i == _tabIndex
                        ? AppColors.primarySoft
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: i == _tabIndex ? AppColors.primary : AppColors.border,
                      width: i == _tabIndex ? 1.2 : 0.8,
                    ),
                  ),
                  child: Text(
                    _boards[i].name,
                    style: TextStyle(
                      color: i == _tabIndex ? AppColors.primaryDark : AppColors.textSecondary,
                      fontSize: 11.5,
                      fontWeight: i == _tabIndex ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 64, height: 64, decoration: BoxDecoration(
            color: AppColors.surface, borderRadius: BorderRadius.circular(20), boxShadow: AppNeumorphic.soft),
            child: Icon(Icons.error_outline_rounded, size: 32, color: AppColors.error)),
          const SizedBox(height: 16), Text(_error!, style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          GestureDetector(onTap: _loadLeaderboard, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), boxShadow: AppNeumorphic.soft),
            child: Text('重试', style: TextStyle(color: AppColors.primary, fontSize: 13)))),
        ]),
      );
    }
    if (_songs.isEmpty) {
      return Center(child: Text('暂无数据', style: TextStyle(color: AppColors.textHint)));
    }

    return RefreshIndicator(
      onRefresh: _loadLeaderboard,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _songs.length,
        itemBuilder: (context, index) => _buildMusicItem(_songs[index], index),
      ),
    );
  }

  Widget _buildMusicItem(MusicInfo song, int index) {
    final isTop3 = index < 3;
    final rankColors = [const Color(0xFFE8B34B), const Color(0xFFB8BFC8), const Color(0xFFC89B6C)];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.card, borderRadius: BorderRadius.circular(16), boxShadow: AppNeumorphic.flat),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: isTop3 ? rankColors[index] : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: Text('${index + 1}', style: TextStyle(
            fontSize: 14, fontWeight: isTop3 ? FontWeight.bold : FontWeight.normal,
            color: isTop3 ? Colors.white : AppColors.textSecondary))),
        ),
        title: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
        subtitle: Text(song.singer, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        trailing: PopupMenuButton(
          icon: Icon(Icons.more_vert_rounded, color: AppColors.textHint, size: 20),
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'play', child: Text('播放')),
            const PopupMenuItem(value: 'next', child: Text('下一首播放')),
          ],
          onSelected: (value) {
            if (value == 'play') _playMusic(song);
            if (value == 'next') _playNext(song);
          },
        ),
        onTap: () => _playMusic(song),
      ),
    );
  }

  void _playMusic(MusicInfo song) async {
    final playerService = ref.read(playerServiceProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('正在加载: ${song.name}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.primary.withValues(alpha: 0.9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
    // 播放整张榜单作为队列，从当前歌曲开始
    await playerService.setPlaylist(_songs, startIndex: _songs.indexOf(song));
  }

  void _playNext(MusicInfo song) async {
    final playerService = ref.read(playerServiceProvider);
    await playerService.addToTempPlaylist([song], isTop: true);
  }
}
