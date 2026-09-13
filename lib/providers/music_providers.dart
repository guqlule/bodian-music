import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/music_model.dart';
import '../services/api/api_service.dart';
import '../services/api/music_search_service.dart';
import '../services/api/music_url_service.dart';
import '../services/lyric/lyric_parser.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

final musicSearchServiceProvider = Provider<MusicSearchService>((ref) {
  return MusicSearchService();
});

final musicUrlServiceProvider = Provider<MusicUrlService>((ref) {
  return MusicUrlService();
});

class SearchState {
  final String query;
  final String source;
  final List<MusicInfo> results;
  final bool isLoading;
  final String? error;
  final int page;
  final bool hasMore;

  SearchState({
    this.query = '',
    this.source = 'kw', // 对齐原版默认源 kw（酷我）
    this.results = const [],
    this.isLoading = false,
    this.error,
    this.page = 1,
    this.hasMore = true,
  });

  SearchState copyWith({
    String? query,
    String? source,
    List<MusicInfo>? results,
    bool? isLoading,
    String? error,
    int? page,
    bool? hasMore,
  }) {
    return SearchState(
      query: query ?? this.query,
      source: source ?? this.source,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

class SearchNotifier extends StateNotifier<SearchState> {
  final MusicSearchService _searchService;

  SearchNotifier(this._searchService) : super(SearchState());

  Future<void> search(String keyword) async {
    if (keyword.isEmpty) return;

    state = state.copyWith(
      query: keyword,
      isLoading: true,
      error: null,
      page: 1,
    );

    try {
      final searchResult = await _searchService.search(
        keyword: keyword,
        source: state.source,
        page: 1,
      );

      state = state.copyWith(
        results: searchResult.list,
        isLoading: false,
        hasMore: searchResult.hasMore,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;

    state = state.copyWith(isLoading: true);

    try {
      final searchResult = await _searchService.search(
        keyword: state.query,
        source: state.source,
        page: state.page + 1,
      );

      state = state.copyWith(
        results: [...state.results, ...searchResult.list],
        isLoading: false,
        page: state.page + 1,
        hasMore: searchResult.hasMore,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void setSource(String source) {
    state = state.copyWith(source: source);
    if (state.query.isNotEmpty) {
      search(state.query);
    }
  }

  void clear() {
    state = SearchState();
  }
}

final musicSearchProvider = StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  final searchService = ref.watch(musicSearchServiceProvider);
  return SearchNotifier(searchService);
});

class MusicDetailState {
  final MusicInfo? music;
  final String? lyric;
  final String? translation;
  final String? songUrl;
  final bool isLoading;
  final String? error;

  MusicDetailState({
    this.music,
    this.lyric,
    this.translation,
    this.songUrl,
    this.isLoading = false,
    this.error,
  });

  MusicDetailState copyWith({
    MusicInfo? music,
    String? lyric,
    String? translation,
    String? songUrl,
    bool? isLoading,
    String? error,
  }) {
    return MusicDetailState(
      music: music ?? this.music,
      lyric: lyric ?? this.lyric,
      translation: translation ?? this.translation,
      songUrl: songUrl ?? this.songUrl,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class MusicDetailNotifier extends StateNotifier<MusicDetailState> {
  final MusicUrlService _urlService;

  MusicDetailNotifier(this._urlService) : super(MusicDetailState());

  Future<void> loadMusicDetail(MusicInfo music) async {
    state = state.copyWith(
      music: music,
      isLoading: true,
      error: null,
    );

    try {
      final songUrl = await _urlService.getMusicUrl(music: music);
      
      state = state.copyWith(
        songUrl: songUrl,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void clear() {
    state = MusicDetailState();
  }
}

final musicDetailProvider = StateNotifierProvider<MusicDetailNotifier, MusicDetailState>((ref) {
  final urlService = ref.watch(musicUrlServiceProvider);
  return MusicDetailNotifier(urlService);
});

final lyricProvider = Provider.family<List<LyricLine>, String?>((ref, lyricText) {
  if (lyricText == null || lyricText.isEmpty) {
    return [];
  }
  return LyricParser.parse(lyricText);
});

final mergedLyricProvider = Provider.family<List<LyricLine>, Map<String, String?>>((ref, lyricData) {
  final original = ref.watch(lyricProvider(lyricData['lyric']));
  final translation = lyricData['tlyric'];
  
  if (translation == null || translation.isEmpty) {
    return original;
  }
  
  return LyricParser.mergeWithTranslation(original, translation);
});
