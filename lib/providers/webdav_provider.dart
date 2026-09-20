import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/music_model.dart';
import '../services/webdav/webdav_service.dart';
import '../services/webdav/webdav_music_service.dart';

/// WebDAV 配置状态
class WebdavConfigState {
  final WebdavConfig? config;
  final bool isConnected;
  final bool isLoading;
  final String? error;

  const WebdavConfigState({
    this.config,
    this.isConnected = false,
    this.isLoading = false,
    this.error,
  });

  WebdavConfigState copyWith({
    WebdavConfig? config,
    bool? isConnected,
    bool? isLoading,
    String? error,
  }) {
    return WebdavConfigState(
      config: config ?? this.config,
      isConnected: isConnected ?? this.isConnected,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// WebDAV 配置 Notifier
class WebdavConfigNotifier extends StateNotifier<WebdavConfigState> {
  final WebdavService _webdavService;
  final WebdavMusicService _musicService;

  WebdavConfigNotifier(this._webdavService, this._musicService)
      : super(const WebdavConfigState()) {
    _init();
  }

  Future<void> _init() async {
    await _musicService.loadLibrary();
    final config = _webdavService.config;
    if (config != null) {
      state = state.copyWith(
        config: config,
        isConnected: _webdavService.isConnected,
      );
    }
  }

  /// 详细测试连接
  Future<({bool ok, String? error, int? fileCount})> testConnectionDetailed(WebdavConfig config) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _webdavService.testConnectionDetailed(config);
      state = state.copyWith(isLoading: false);
      return result;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return (ok: false, error: e.toString(), fileCount: null);
    }
  }

  /// 简单测试连接
  Future<bool> testConnection(WebdavConfig config) async {
    final result = await testConnectionDetailed(config);
    return result.ok;
  }

  /// 保存并连接
  Future<void> saveAndConnect(WebdavConfig config) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _webdavService.connect(config);
      await _musicService.saveConfig(config);
      state = state.copyWith(
        config: config,
        isConnected: true,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 断开
  void disconnect() {
    _webdavService.disconnect();
    state = state.copyWith(isConnected: false);
  }

  /// 扫描远程目录
  Future<int> scanRemote() async {
    return await _musicService.scanRemote();
  }

  /// 清空音乐库
  Future<void> clearLibrary() async {
    await _musicService.clearLibrary();
  }

  /// 删除一首歌
  Future<void> removeSong(String id) async {
    await _musicService.removeSong(id);
  }
}

/// WebDAV 配置 Provider
final webdavConfigProvider =
    StateNotifierProvider<WebdavConfigNotifier, WebdavConfigState>((ref) {
  return WebdavConfigNotifier(WebdavService(), WebdavMusicService());
});

/// WebDAV 歌曲列表 Provider（响应式，每次库变更自动推送）
final webdavSongsProvider = StreamProvider<List<MusicInfo>>((ref) {
  final controller = StreamController<List<MusicInfo>>();
  final sub = WebdavMusicService().songsStream.listen(controller.add);
  // 立即发出当前列表（首次订阅时）
  controller.add(WebdavMusicService().songs);
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  return controller.stream;
});
