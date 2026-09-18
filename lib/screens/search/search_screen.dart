import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/music_model.dart';
import '../../services/api/songlist_service.dart';
import '../../services/api/music_search_service.dart';
import '../../services/api/hot_search_service.dart';
import '../../services/api/search_suggest_service.dart';
import '../../providers/music_providers.dart';
import '../../providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/storage/storage_service.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final HotSearchService _hotSearchService = HotSearchService();
  final SearchSuggestService _suggestService = SearchSuggestService();
  List<String> _searchHistory = [];
  List<String> _hotSearches = ['周杰伦', '林俊杰', '陈奕迅', '邓紫棋', '薛之谦'];
  bool _hotSearchLoading = false;
  bool _searchPlaylistMode = false; // false=歌曲 true=歌单
  List<SonglistInfo> _playlistResults = [];
  bool _isSearchingPlaylists = false;
  String? _playlistSearchError;
  final SonglistService _songlistService = SonglistService();
  // 输入联想（对齐原版 TipList：500ms 防抖）
  Timer? _suggestDebounce;
  List<String> _suggestResults = [];
  bool _showSuggest = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadHistory();
    _loadHotSearch();
    _searchController.addListener(_onSearchTextChanged);
  }

  /// 加载当前音源的真实热搜词（失败回退静态热词）
  Future<void> _loadHotSearch() async {
    final source = ref.read(musicSearchProvider).source;
    setState(() => _hotSearchLoading = true);
    try {
      final list = await _hotSearchService.getHotSearch(source);
      if (!mounted) return;
      setState(() {
        _hotSearches = list.isNotEmpty ? list : _hotSearches;
        _hotSearchLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _hotSearchLoading = false);
    }
  }

  /// 输入联想（500ms 防抖，对齐原版）
  void _onSearchTextChanged() {
    final text = _searchController.text.trim();
    _suggestDebounce?.cancel();
    if (text.isEmpty) {
      if (mounted) setState(() { _suggestResults = []; _showSuggest = false; });
      ref.read(musicSearchProvider.notifier).clear();
      return;
    }
    // 输入内容就是当前已搜索的关键词（如点联想词/热搜词后程序化回填）：
    // 不弹联想，避免覆盖搜索结果
    if (text == ref.read(musicSearchProvider).query) {
      if (mounted) setState(() { _suggestResults = []; _showSuggest = false; });
      return;
    }
    _suggestDebounce = Timer(const Duration(milliseconds: 500), () async {
      final source = ref.read(musicSearchProvider).source;
      final results = await _suggestService.getSuggestions(source, text);
      if (!mounted) return;
      // 防抖期间用户可能已提交搜索或清空输入，响应回来后需再校验
      if (_searchController.text.trim() != text) return;
      if (_searchController.text.trim() == ref.read(musicSearchProvider).query) return;
      setState(() {
        _suggestResults = results;
        _showSuggest = results.isNotEmpty;
      });
    });
  }

  void _hideSuggest() {
    _suggestDebounce?.cancel();
    if (mounted) setState(() { _suggestResults = []; _showSuggest = false; });
  }

  /// 歌单搜索源（tx/kw/wy/all，独立于歌曲源）
  String _playlistSource = 'tx';

  /// 搜索歌单（统一入口，按源分发）
  Future<void> _searchPlaylists(String keyword) async {
    if (keyword.isEmpty) return;
    setState(() { _isSearchingPlaylists = true; _playlistSearchError = null; });
    try {
      final lists = await _songlistService.searchSonglists(
        keyword, source: _playlistSource, page: 1, pageSize: 30);
      if (!mounted) return;
      setState(() {
        _playlistResults = lists;
        _isSearchingPlaylists = false;
      });
    } catch (e) {
      // 网络失败要区分于"无结果"（误导用户以为没有歌单）
      if (mounted) {
        setState(() {
          _playlistResults = [];
          _isSearchingPlaylists = false;
          _playlistSearchError = '歌单搜索失败，请检查网络';
        });
      }
    }
  }

  void _loadHistory() {
    setState(() {
      _searchHistory = StorageService().getSearchHistory();
    });
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _searchController.removeListener(_onSearchTextChanged);
    _searchController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(musicSearchProvider.notifier).loadMore();
    }
  }

  void _performSearch() {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    _saveSearchHistory(query);
    _focusNode.unfocus();
    _hideSuggest();
    if (_searchPlaylistMode) {
      _searchPlaylists(query);
    } else {
      ref.read(musicSearchProvider.notifier).search(query);
    }
  }

  void _saveSearchHistory(String keyword) {
    StorageService().addSearchHistory(keyword);
    setState(() {
      _searchHistory = StorageService().getSearchHistory();
    });
  }

  void _clearHistory() {
    StorageService().clearSearchHistory();
    setState(() {
      _searchHistory = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(musicSearchProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Container(
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppNeumorphic.inset,
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _focusNode,
            decoration: InputDecoration(
              hintText: '搜索歌曲、歌手、专辑',
              border: InputBorder.none,
              hintStyle: TextStyle(color: AppColors.textHint, fontSize: 14),
              prefixIcon: Icon(Icons.search_rounded, color: AppColors.textHint, size: 20),
              suffixIcon: IconButton(
                icon: Icon(Icons.clear_rounded, color: AppColors.textHint, size: 18),
                onPressed: () {
                  _searchController.clear();
                  ref.read(musicSearchProvider.notifier).clear();
                  _focusNode.requestFocus();
                },
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onChanged: (text) {
              if (text.isEmpty) {
                ref.read(musicSearchProvider.notifier).clear();
              }
            },
            onSubmitted: (_) => _performSearch(),
            textInputAction: TextInputAction.search,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: _performSearch,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('搜索', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 歌曲/歌单 切换 Tab
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildSearchTab('歌曲', !_searchPlaylistMode),
                const SizedBox(width: 8),
                _buildSearchTab('歌单', _searchPlaylistMode),
              ],
            ),
          ),
          // 音源选择：歌曲模式选歌曲源；歌单模式选歌单源（tx/kw/wy/all）
          if (_searchPlaylistMode) _buildPlaylistSourceSelector() else _buildSourceSelector(),
          Expanded(
            child: _searchPlaylistMode
                ? _buildPlaylistResults()
                : (_showSuggest ? _buildSuggestList() : _buildContent(searchState)),
          ),
        ],
      ),
    );
  }

  /// 歌单源选择器（QQ/酷我/网易/全部）
  Widget _buildPlaylistSourceSelector() {
    const options = [
      ('tx', '源三'), ('kw', '源一'), ('wy', '源四'), ('all', '聚合'),
    ];
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: options.map((opt) {
          final isSelected = _playlistSource == opt.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
            child: GestureDetector(
              onTap: () {
                if (_playlistSource == opt.$1) return;
                _playlistSource = opt.$1;
                if (_searchController.text.trim().isNotEmpty) {
                  _searchPlaylists(_searchController.text.trim());
                } else {
                  setState(() {});
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected ? [] : AppNeumorphic.flat,
                ),
                child: Center(
                  child: Text(opt.$2, style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                    fontSize: 12, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSearchTab(String label, bool selected) {
    return GestureDetector(
      onTap: () => setState(() => _searchPlaylistMode = label == '歌单'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          boxShadow: selected ? [] : AppNeumorphic.flat,
        ),
        child: Text(label, style: TextStyle(
          color: selected ? Colors.white : AppColors.textSecondary,
          fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
      ),
    );
  }

  // 歌单搜索结果
  Widget _buildPlaylistResults() {
    if (_isSearchingPlaylists) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_playlistSearchError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_playlistSearchError!,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _searchPlaylists(_searchController.text.trim()),
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
      );
    }
    if (_playlistResults.isEmpty) {
      return Center(
        child: Text('未找到相关歌单', style: TextStyle(color: AppColors.textHint, fontSize: 13)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _playlistResults.length,
      itemBuilder: (context, index) {
        final list = _playlistResults[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppNeumorphic.flat,
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: list.imgUrl.isNotEmpty
                  ? Image.network(list.imgUrl, cacheWidth: 104, width: 52, height: 52,
                      fit: BoxFit.cover, errorBuilder: (_, __, ___) => _plThumb())
                  : _plThumb(),
            ),
            title: Text(list.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
            subtitle: Text(
              '${list.author} · ${(list.playCount / 10000).toStringAsFixed(1)}万次播放',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            trailing: Icon(Icons.chevron_right_rounded,
                color: AppColors.textHint, size: 20),
            onTap: () => context.push('/songlist-detail/${list.id}',
                extra: {'name': list.name, 'source': list.source}),
          ),
        );
      },
    );
  }

  Widget _plThumb() {
    return Container(
      width: 52, height: 52,
      color: AppColors.primarySoftColor,
      child: Icon(Icons.queue_music_rounded, color: AppColors.primary, size: 22),
    );
  }

  Widget _buildSourceSelector() {
    final searchState = ref.watch(musicSearchProvider);
    // 对齐原版：五源 + 全部，命名来自 musicSdk/index.js
    final sources = MusicSearchService.availableSources
        .map((id) => {'id': id, 'name': MusicSearchService.sourceNames[id] ?? id.toUpperCase()})
        .toList();

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: sources.map((source) {
          final isSelected = searchState.source == source['id'];
          return Padding(
            padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
            child: GestureDetector(
              onTap: () {
                final id = source['id']!;
                ref.read(musicSearchProvider.notifier).setSource(id);
                // 切源刷新热搜（对齐原版 HotSearch.show(source)）
                _loadHotSearch();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected ? [] : AppNeumorphic.flat,
                ),
                child: Center(
                  child: Text(source['name']!, style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                    fontSize: 12, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 输入联想列表（对齐原版 TipList：点击联想词直接搜索）
  Widget _buildSuggestList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _suggestResults.length,
      itemBuilder: (context, index) {
        final keyword = _suggestResults[index];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            _searchController.text = keyword;
            _performSearch();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: AppColors.textHint, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(keyword, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ),
                Icon(Icons.north_west_rounded, color: AppColors.textHint, size: 14),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(SearchState searchState) {
    if (searchState.query.isEmpty) return _buildSearchSuggestions();
    if (searchState.isLoading && searchState.results.isEmpty) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (searchState.error != null && searchState.results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
            Text(searchState.error!, style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => ref.read(musicSearchProvider.notifier).search(searchState.query),
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
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: searchState.results.length + (searchState.isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == searchState.results.length) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
            ),
          );
        }
        return _buildMusicItem(searchState.results[index]);
      },
    );
  }

  Widget _buildSearchSuggestions() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_searchHistory.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('搜索历史', style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                GestureDetector(
                  onTap: _clearHistory,
                  child: Text('清空', style: TextStyle(color: AppColors.textHint, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _searchHistory.map((keyword) {
                return GestureDetector(
                  onTap: () {
                    _searchController.text = keyword;
                    _performSearch();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppNeumorphic.flat,
                    ),
                    child: Text(keyword, style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 28),
          ],
          if (_hotSearches.isNotEmpty) ...[
            Text('热门搜索', style: TextStyle(
              color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            if (_hotSearchLoading)
              Center(child: Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
              ))
            else
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _hotSearches.asMap().entries.map((entry) {
                final index = entry.key;
                final keyword = entry.value;
                final isTop3 = index < 3;
                return GestureDetector(
                  onTap: () {
                    _searchController.text = keyword;
                    _performSearch();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isTop3 ? AppColors.primarySoftColor : AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: isTop3 ? [] : AppNeumorphic.flat,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isTop3) ...[
                          Container(
                            width: 16, height: 16,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Center(
                              child: Text('${index + 1}', style: const TextStyle(
                                color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(keyword, style: TextStyle(
                          color: isTop3 ? AppColors.primary : AppColors.textSecondary,
                          fontSize: 12)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMusicItem(MusicInfo music) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppNeumorphic.flat,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: AppColors.primarySoftColor,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: music.imgUrl != null
                ? Image.network(music.imgUrl!, cacheWidth: 200, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildDefaultThumbnail())
                : _buildDefaultThumbnail(),
          ),
        ),
        title: Text(music.name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text('${music.singer} - ${music.album}', maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        trailing: PopupMenuButton(
          icon: Icon(Icons.more_vert_rounded, color: AppColors.textHint, size: 20),
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'play', child: Text('播放')),
            const PopupMenuItem(value: 'next', child: Text('下一首播放')),
            const PopupMenuItem(value: 'add_to_playlist', child: Text('添加到播放列表')),
          ],
          onSelected: (value) => _handleMenuAction(value, music),
        ),
        onTap: () => _playMusic(music),
      ),
    );
  }

  Widget _buildDefaultThumbnail() {
    return Container(
      width: 48, height: 48,
      decoration: BoxDecoration(
        color: AppColors.primarySoftColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.music_note_rounded, color: AppColors.primary, size: 22),
    );
  }

  void _handleMenuAction(String action, MusicInfo music) {
    switch (action) {
      case 'play': _playMusic(music); break;
      case 'next':
        ref.read(playerServiceProvider).addToTempPlaylist([music], isTop: true);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已添加到下一首播放')));
        break;
      case 'add_to_playlist': _showAddToPlaylistDialog(music); break;
    }
  }

  void _playMusic(MusicInfo music) {
    final playerService = ref.read(playerServiceProvider);
    // 先取 messenger（必须在 pop 前取，pop 后 context 失效）
    final messenger = ScaffoldMessenger.maybeOf(context);
    playerService.playMusic(music).then((_) {
      if (!mounted) return;
      // 关闭搜索页回到首页（首页有全屏歌词 + 频谱）
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    }).catchError((e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('播放失败: $e')),
      );
    });
  }

  void _showAddToPlaylistDialog(MusicInfo music) {
    final isFav = ref.read(favoritesProvider.notifier).isFavorite(music.id);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('添加到播放列表',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: AppColors.error,
              ),
              title: Text(isFav ? '取消喜欢' : '我喜欢',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              onTap: () {
                ref.read(favoritesProvider.notifier).toggleFavorite(music);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(isFav ? '已取消喜欢' : '已添加到我喜欢'),
                ));
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.queue_rounded, color: AppColors.primary),
              title: Text('下一首播放',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              onTap: () {
                ref.read(playerServiceProvider).addToTempPlaylist([music], isTop: true);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已添加到下一首播放')));
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}
