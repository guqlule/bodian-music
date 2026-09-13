import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../core/storage/storage_service.dart';
import '../models/music_model.dart';
import '../models/playlist_model.dart';
import '../services/player/player_service.dart';
import '../core/utils/logger.dart';

// Player Service Provider
final playerServiceProvider = Provider<PlayerService>((ref) {
  return PlayerService();
});

// Current Music Provider
final currentMusicProvider = StreamProvider<MusicInfo?>((ref) {
  final playerService = ref.watch(playerServiceProvider);
  // 过滤相同值的连续重复发射（一次播放可能发射多次）
  return playerService.currentMusicStream.distinct((a, b) => a?.id == b?.id && a?.songUrl == b?.songUrl && a?.imgUrl == b?.imgUrl);
});

// Is Playing Provider
final playQualityProvider = StreamProvider<String>((ref) {
  final playerService = ref.watch(playerServiceProvider);
  return playerService.qualityStream;
});

final isPlayingProvider = StreamProvider<bool>((ref) {
  final playerService = ref.watch(playerServiceProvider);
  return playerService.isPlayingStream;
});

// Position Provider
final positionProvider = StreamProvider<Duration>((ref) {
  final playerService = ref.watch(playerServiceProvider);
  return playerService.positionStream;
});

// Duration Provider
final durationProvider = StreamProvider<Duration?>((ref) {
  final playerService = ref.watch(playerServiceProvider);
  return playerService.durationStream;
});

// Current Playlist Provider
final currentPlaylistProvider = StreamProvider<List<MusicInfo>>((ref) {
  final playerService = ref.watch(playerServiceProvider);
  return playerService.playlistStream.distinct((a, b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  });
});

// Current Index Provider
final currentIndexProvider = StreamProvider<int>((ref) {
  final playerService = ref.watch(playerServiceProvider);
  return playerService.currentIndexStream;
});

// Play Mode Provider
final playModeProvider = StreamProvider<PlayMode>((ref) {
  final playerService = ref.watch(playerServiceProvider);
  return playerService.playModeStream;
});

// Play History Provider
final playHistoryProvider = StreamProvider<List<MusicInfo>>((ref) {
  final playerService = ref.watch(playerServiceProvider);
  return playerService.playHistoryStream;
});

// Played List Provider (for random mode)
final playedListProvider = StreamProvider<List<MusicInfo>>((ref) {
  final playerService = ref.watch(playerServiceProvider);
  return playerService.playedListStream;
});

// Temp Playlist Provider
final tempPlaylistProvider = StreamProvider<List<MusicInfo>>((ref) {
  final playerService = ref.watch(playerServiceProvider);
  return playerService.tempPlaylistStream;
});

// Status Text Provider
final statusTextProvider = StreamProvider<String>((ref) {
  final playerService = ref.watch(playerServiceProvider);
  return playerService.statusTextStream;
});

// Is Loading Provider
final isLoadingProvider = StreamProvider<bool>((ref) {
  final playerService = ref.watch(playerServiceProvider);
  return playerService.isLoadingStream;
});

// Sleep Timer Active Provider
final sleepTimerActiveProvider = StreamProvider<bool>((ref) {
  final playerService = ref.watch(playerServiceProvider);
  return playerService.isSleepTimerActiveStream;
});

// Sleep Timer Remaining Provider
final sleepTimerRemainingProvider = StreamProvider<Duration?>((ref) {
  final playerService = ref.watch(playerServiceProvider);
  return playerService.sleepTimerRemainingStream;
});

// Lyric Provider
final lyricProvider = StreamProvider<Map<String, String?>?>((ref) {
  final playerService = ref.watch(playerServiceProvider);
  return playerService.lyricStream;
});

// Playlist State Notifier（Hive 持久化）
class PlaylistNotifier extends StateNotifier<List<PlaylistInfo>> {
  PlaylistNotifier() : super([]) {
    _load();
  }

  bool _loaded = false;

  Future<void> _load() async {
    try {
      final storage = StorageService();
      final ids = storage.getAllPlaylistIds();
      final lists = <PlaylistInfo>[];
      for (final id in ids) {
        final raw = storage.getPlaylist(id);
        if (raw == null) continue;
        try {
          final json = {
            'id': id,
            'songs': raw,
            // name/createTime 等存 settings 以补全
            ...?storage.getPlaylistMeta(id),
          };
          lists.add(PlaylistInfo.fromJson(Map<String, dynamic>.from(json)));
        } catch (_) {}
      }
      // 兼容旧数据：从 settings 里的单键列表加载
      if (lists.isEmpty) {
        final legacy = storage.getSetting('user_playlists');
        if (legacy is List) {
          for (final item in legacy) {
            if (item is Map) {
              try {
                lists.add(PlaylistInfo.fromJson(Map<String, dynamic>.from(item)));
              } catch (_) {}
            }
          }
        }
      }
      state = lists;
      _loaded = true;
    } catch (e) {
      logDebug('[Playlist] 加载失败: $e');
      _loaded = true;
    }
  }

  /// 增量保存单个歌单（变更哪个写哪个，不全量重写）
  Future<void> _saveOne(StorageService storage, PlaylistInfo p) async {
    await storage.savePlaylist(p.id, p.songs.map((s) => s.toJson()).toList());
    await storage.savePlaylistMeta(p.id, {
      'name': p.name,
      'createTime': p.createTime.toIso8601String(),
      'updateTime': p.updateTime.toIso8601String(),
      'coverUrl': p.coverUrl,
      'description': p.description,
    });
  }

  void addPlaylist(PlaylistInfo playlist) {
    state = [...state, playlist];
    _loadedIfSaveOne(playlist);
  }

  Future<void> _loadedIfSaveOne(PlaylistInfo playlist) async {
    if (!_loaded) return;
    try {
      await _saveOne(StorageService(), playlist);
    } catch (e) {
      logDebug('[Playlist] 保存失败: $e');
    }
  }

  void removePlaylist(String id) {
    state = state.where((p) => p.id != id).toList();
    if (_loaded) {
      StorageService().deletePlaylist(id);
      StorageService().deletePlaylistMeta(id);
    }
  }

  void updatePlaylist(PlaylistInfo updatedPlaylist) {
    state = state.map((p) => p.id == updatedPlaylist.id ? updatedPlaylist : p).toList();
    _loadedIfSaveOne(updatedPlaylist);
  }

  PlaylistInfo? getPlaylist(String id) {
    try {
      return state.firstWhere((p) => p.id == id);
    } catch (e) {
      return null;
    }
  }

  void addToPlaylist(String playlistId, MusicInfo song) {
    final playlist = getPlaylist(playlistId);
    if (playlist != null) {
      playlist.addSong(song);
      updatePlaylist(playlist);
    }
  }

  void removeFromPlaylist(String playlistId, String songId) {
    final playlist = getPlaylist(playlistId);
    if (playlist != null) {
      playlist.removeSong(songId);
      updatePlaylist(playlist);
    }
  }

  void clearPlaylist(String playlistId) {
    final playlist = getPlaylist(playlistId);
    if (playlist != null) {
      playlist.songs.clear();
      playlist.updateTime = DateTime.now();
      updatePlaylist(playlist);
    }
  }

  void reorderSongInPlaylist(String playlistId, int oldIndex, int newIndex) {
    final playlist = getPlaylist(playlistId);
    if (playlist != null && oldIndex >= 0 && oldIndex < playlist.songs.length && newIndex >= 0 && newIndex < playlist.songs.length) {
      final song = playlist.songs.removeAt(oldIndex);
      playlist.songs.insert(newIndex, song);
      playlist.updateTime = DateTime.now();
      updatePlaylist(playlist);
    }
  }
}

final playlistProvider = StateNotifierProvider<PlaylistNotifier, List<PlaylistInfo>>((ref) {
  return PlaylistNotifier();
});

// Favorites State（Hive 持久化）
class FavoritesNotifier extends StateNotifier<List<MusicInfo>> {
  FavoritesNotifier() : super([]) {
    _load();
  }

  bool _loaded = false;
  static const String _key = 'favorites';

  Future<void> _load() async {
    try {
      final box = await Hive.openBox('player');
      final json = box.get(_key, defaultValue: []);
      final list = <MusicInfo>[];
      if (json is List) {
        for (final item in json) {
          try {
            if (item is Map) {
              list.add(MusicInfo.fromJson(Map<String, dynamic>.from(item)));
            }
          } catch (_) {}
        }
      }
      state = list;
    } catch (e) {
      logDebug('[Favorites] 加载失败: $e');
    }
    _loaded = true;
  }

  Future<void> _save() async {
    if (!_loaded) return;
    try {
      final box = await Hive.openBox('player');
      await box.put(_key, state.map((m) => m.toJson()).toList());
      await box.flush();
    } catch (e) {
      logDebug('[Favorites] 保存失败: $e');
    }
  }

  void addFavorite(MusicInfo music) {
    if (!state.any((m) => m.id == music.id)) {
      state = [...state, music];
      _save();
    }
  }

  void removeFavorite(String musicId) {
    state = state.where((m) => m.id != musicId).toList();
    _save();
  }

  bool isFavorite(String musicId) {
    return state.any((m) => m.id == musicId);
  }

  void toggleFavorite(MusicInfo music) {
    if (isFavorite(music.id)) {
      removeFavorite(music.id);
    } else {
      addFavorite(music);
    }
  }

  void clearFavorites() {
    state = [];
    _save();
  }
}

final favoritesProvider = StateNotifierProvider<FavoritesNotifier, List<MusicInfo>>((ref) {
  return FavoritesNotifier();
});

// Recent Played State（Hive 持久化）
class RecentPlayedNotifier extends StateNotifier<List<MusicInfo>> {
  RecentPlayedNotifier() : super([]) {
    _load();
  }

  bool _loaded = false;
  static const String _key = 'recent_played';

  Future<void> _load() async {
    try {
      final box = await Hive.openBox('player');
      final json = box.get(_key, defaultValue: []);
      final list = <MusicInfo>[];
      if (json is List) {
        for (final item in json) {
          try {
            if (item is Map) {
              list.add(MusicInfo.fromJson(Map<String, dynamic>.from(item)));
            }
          } catch (_) {}
        }
      }
      state = list;
    } catch (e) {
      logDebug('[Recent] 加载失败: $e');
    }
    _loaded = true;
  }

  Future<void> _save() async {
    if (!_loaded) return;
    try {
      final box = await Hive.openBox('player');
      await box.put(_key, state.map((m) => m.toJson()).toList());
      await box.flush();
    } catch (e) {
      logDebug('[Recent] 保存失败: $e');
    }
  }

  void addRecent(MusicInfo music) {
    // 不可变更新：不就地修改 state 列表
    final newList = [music, ...state.where((m) => m.id != music.id)];
    state = newList.length > 50 ? newList.sublist(0, 50) : newList;
    _save();
  }

  void clearRecent() {
    state = [];
    _save();
  }

  void removeFromRecent(String musicId) {
    state = state.where((m) => m.id != musicId).toList();
    _save();
  }
}

final recentPlayedProvider = StateNotifierProvider<RecentPlayedNotifier, List<MusicInfo>>((ref) {
  return RecentPlayedNotifier();
});

// Dislike List State
class DislikeListNotifier extends StateNotifier<Set<String>> {
  DislikeListNotifier() : super({});

  void addDislike(String rule) {
    state = {...state, rule};
  }

  void removeDislike(String rule) {
    state = state.where((r) => r != rule).toList().toSet();
  }

  bool isDisliked(String name, String singer) {
    final lowerName = name.toLowerCase();
    final lowerSinger = singer.toLowerCase();
    
    return state.any((rule) {
      if (rule.contains('@')) {
        final parts = rule.split('@');
        return lowerName == parts[0].toLowerCase() && 
               lowerSinger == parts[1].toLowerCase();
      } else {
        return lowerName == rule.toLowerCase() || 
               lowerSinger == rule.toLowerCase();
      }
    });
  }

  List<MusicInfo> filterMusicList(List<MusicInfo> songs) {
    return songs.where((song) => !isDisliked(song.name, song.singer)).toList();
  }

  void clearDislikes() {
    state = {};
  }
}

final dislikeListProvider = StateNotifierProvider<DislikeListNotifier, Set<String>>((ref) {
  return DislikeListNotifier();
});
