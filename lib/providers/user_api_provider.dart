import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api/user_api_service.dart';

final userApiServiceProvider = Provider<UserApiService>((ref) {
  final service = UserApiService();
  ref.onDispose(() => service.dispose());
  return service;
});

class UserApiState {
  final UserApiStateType type;
  final List<UserApiScript> scripts;
  final UserApiScript? currentScript;
  final String? error;

  UserApiState({
    this.type = UserApiStateType.idle,
    this.scripts = const [],
    this.currentScript,
    this.error,
  });

  UserApiState copyWith({
    UserApiStateType? type,
    List<UserApiScript>? scripts,
    UserApiScript? currentScript,
    String? error,
    bool clearCurrentScript = false,
  }) {
    return UserApiState(
      type: type ?? this.type,
      scripts: scripts ?? this.scripts,
      currentScript: clearCurrentScript ? null : (currentScript ?? this.currentScript),
      error: error,
    );
  }
}

enum UserApiStateType {
  idle,
  loading,
  loaded,
  active,
  error,
}

class UserApiNotifier extends StateNotifier<UserApiState> {
  final UserApiService _service;

  UserApiNotifier(this._service) : super(UserApiState()) {
    _init();
  }

  void _init() {
    _service.stateStream.listen((serviceState) {
      state = state.copyWith(
        type: _mapStateType(serviceState),
      );
    });

    _service.eventStream.listen((event) {
      switch (event.type) {
        case UserApiEventType.scriptImported:
          _refreshScripts();
          break;
        case UserApiEventType.scriptActivated:
          // 激活指令已下发（JS 可能仍在初始化），UI 先显示"初始化中"
          state = state.copyWith(
            currentScript: event.data,
            error: null,
          );
          break;
        case UserApiEventType.scriptDeactivated:
          state = state.copyWith(clearCurrentScript: true);
          break;
        case UserApiEventType.scriptRemoved:
          _refreshScripts();
          if (state.currentScript?.id == event.data) {
            state = state.copyWith(clearCurrentScript: true);
          }
          break;
        case UserApiEventType.requestSent:
          break;
        case UserApiEventType.scriptError:
          final data = event.data as Map?;
          final errScript = data?['script'] as UserApiScript?;
          final message = data?['message']?.toString();
          // 仅当前激活脚本的错误才展示，过期初始化的错误直接丢弃
          if (errScript == null || errScript.id != state.currentScript?.id) break;
          state = state.copyWith(
            type: UserApiStateType.error,
            error: message,
          );
          break;
      }
    });

    _loadPersistedScripts();
  }

  Future<void> _loadPersistedScripts() async {
    await _service.init();
    _refreshScripts();
    // 注意：脚本激活由 main.dart 的 _activatePersistedScript() 负责，
    // 不在此处重复调用 activateScript()，避免竞态条件导致 _sources 被清空
    // 懒加载补偿：provider 可能晚于启动期激活完成才创建（如直接进入自定义源页），
    // 从 service 同步当前激活脚本，避免错过启动期广播事件导致状态丢失
    final current = _service.currentScript;
    if (current != null && state.currentScript == null) {
      state = state.copyWith(
        currentScript: current,
        type: _service.lastActivationError != null
            ? UserApiStateType.error
            : (_service.isActive ? UserApiStateType.active : UserApiStateType.loading),
        error: _service.lastActivationError,
      );
    }
  }

  UserApiStateType _mapStateType(UserApiServiceState serviceState) {
    switch (serviceState) {
      case UserApiServiceState.idle:
        return UserApiStateType.idle;
      case UserApiServiceState.loading:
        return UserApiStateType.loading;
      case UserApiServiceState.loaded:
        return UserApiStateType.loaded;
      case UserApiServiceState.active:
        return UserApiStateType.active;
      case UserApiServiceState.error:
        return UserApiStateType.error;
    }
  }

  void _refreshScripts() {
    state = state.copyWith(scripts: _service.getAllScripts());
  }

  Future<void> importScript(String scriptContent) async {
    try {
      state = state.copyWith(type: UserApiStateType.loading);
      await _service.importScript(scriptContent);
      _refreshScripts();
    } catch (e) {
      state = state.copyWith(
        type: UserApiStateType.error,
        error: e.toString(),
      );
    }
  }

  Future<void> activateScript(String scriptId) async {
    try {
      await _service.activateScript(scriptId);
    } catch (e) {
      state = state.copyWith(
        type: UserApiStateType.error,
        error: e.toString(),
      );
    }
  }

  Future<void> deactivateScript() async {
    try {
      await _service.deactivateScript();
    } catch (e) {
      state = state.copyWith(
        type: UserApiStateType.error,
        error: e.toString(),
      );
    }
  }

  Future<void> removeScript(String scriptId) async {
    try {
      await _service.removeScript(scriptId);
      _refreshScripts();
    } catch (e) {
      state = state.copyWith(
        type: UserApiStateType.error,
        error: e.toString(),
      );
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final userApiProvider = StateNotifierProvider<UserApiNotifier, UserApiState>((ref) {
  final service = ref.watch(userApiServiceProvider);
  return UserApiNotifier(service);
});
