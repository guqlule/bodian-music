import 'package:hive_flutter/hive_flutter.dart';

class StorageService {
  static const String _settingsBox = 'settings';
  static const String _playlistBox = 'playlists';
  static const String _cacheBox = 'cache';
  static const String _searchHistoryBox = 'search_history';
  static const String _userApiBox = 'user_api';

  late Box _settings;
  late Box _playlists;
  late Box _cache;
  late Box _searchHistory;
  late Box _userApi;

  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  Future<void> init({String? hivePath}) async {
    // 测试环境可传入本地路径，绕过 path_provider 插件
    if (hivePath != null) {
      Hive.init(hivePath);
    } else {
      await Hive.initFlutter();
    }
    _settings = await Hive.openBox(_settingsBox);
    _playlists = await Hive.openBox(_playlistBox);
    _cache = await Hive.openBox(_cacheBox);
    _searchHistory = await Hive.openBox(_searchHistoryBox);
    _userApi = await Hive.openBox(_userApiBox);
  }

  // Settings
  dynamic getSetting(String key, {dynamic defaultValue}) {
    return _settings.get(key, defaultValue: defaultValue);
  }

  Future<void> setSetting(String key, dynamic value) async {
    await _settings.put(key, value);
  }

  Future<void> removeSetting(String key) async {
    await _settings.delete(key);
  }

  // Playlists
  List<dynamic>? getPlaylist(String id) {
    return _playlists.get(id) as List<dynamic>?;
  }

  Future<void> savePlaylist(String id, List<Map<String, dynamic>> songs) async {
    await _playlists.put(id, songs);
  }

  Future<void> deletePlaylist(String id) async {
    await _playlists.delete(id);
  }

  List<String> getAllPlaylistIds() {
    return _playlists.keys.cast<String>().toList();
  }

  // 歌单元数据（name/createTime 等存在 settings box，键前缀 playlist_meta_）
  Map<String, dynamic>? getPlaylistMeta(String id) {
    final v = _settings.get('playlist_meta_$id');
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  Future<void> savePlaylistMeta(String id, Map<String, dynamic> meta) async {
    await _settings.put('playlist_meta_$id', meta);
  }

  Future<void> deletePlaylistMeta(String id) async {
    await _settings.delete('playlist_meta_$id');
  }

  // Cache
  dynamic getCache(String key) {
    return _cache.get(key);
  }

  Future<void> setCache(String key, dynamic value) async {
    await _cache.put(key, value);
  }

  Future<void> removeCache(String key) async {
    await _cache.delete(key);
  }

  Future<void> clearCache() async {
    await _cache.clear();
  }

  // Search History
  List<String> getSearchHistory() {
    return _searchHistory.get('history', defaultValue: <String>[])?.cast<String>() ?? [];
  }

  Future<void> addSearchHistory(String keyword) async {
    final history = getSearchHistory();
    history.remove(keyword);
    history.insert(0, keyword);
    if (history.length > 20) {
      history.removeLast();
    }
    await _searchHistory.put('history', history);
  }

  Future<void> clearSearchHistory() async {
    await _searchHistory.put('history', <String>[]);
  }

  // User API scripts
  List<dynamic>? getUserApiScripts() {
    return _userApi.get('scripts', defaultValue: <dynamic>[])?.cast<dynamic>() ?? [];
  }

  Future<void> saveUserApiScripts(List<Map<String, dynamic>> scripts) async {
    await _userApi.put('scripts', scripts);
  }

  String? getUserApiActiveScriptId() {
    return _userApi.get('activeScriptId') as String?;
  }

  Future<void> setUserApiActiveScriptId(String? id) async {
    if (id == null) {
      await _userApi.delete('activeScriptId');
    } else {
      await _userApi.put('activeScriptId', id);
    }
  }

  Future<void> close() async {
    await Hive.close();
  }
}
