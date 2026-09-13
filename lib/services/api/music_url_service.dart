import '../../models/music_model.dart';
import 'user_api_service.dart';

class MusicUrlService {
  static final MusicUrlService _instance = MusicUrlService._internal();
  factory MusicUrlService() => _instance;
  MusicUrlService._internal();

  final UserApiService _userApiService = UserApiService();

  /// 最近一次成功取 URL 的实际音质（128k/320k/flac/flac24bit）
  String? lastUsedQuality;

  bool get isUserApiActive => _userApiService.isActive;
  UserApiScript? get currentScript => _userApiService.currentScript;

  /// 当前激活的自定义源脚本是否支持该音源
  bool supportsSource(String source) {
    if (!_userApiService.isActive) return false;
    return _userApiService.sources.containsKey(source);
  }

  /// 获取播放地址 - 通过用户自定义源API
  Future<String?> getMusicUrl({
    required MusicInfo music,
    String quality = '320k',
  }) async {
    final source = music.source ?? 'kw';

    if (!_userApiService.isActive) {
      _userApiService.debugLog('未激活用户 API 源，无法获取播放地址', type: DebugLogType.warn);
      return null;
    }

    if (!_userApiService.sources.containsKey(source)) {
      _userApiService.debugLog('用户 API 源不支持音源: $source', type: DebugLogType.warn);
      return null;
    }

    // 脚本 init 声明的 actions 里没有 musicUrl 的不调用（对齐原版按 actions 注册）
    final scriptActions = _userApiService.sources[source]?.actions ?? const [];
    if (scriptActions.isNotEmpty && !scriptActions.contains('musicUrl')) {
      _userApiService.debugLog('脚本未声明支持 musicUrl ($source)，跳过', type: DebugLogType.warn);
      return null;
    }

    // 音质选择：与换源/预取同一标准（pickQuality）
    final actualQuality = pickQuality(source, music, quality);

    final apiId = _userApiService.currentScript?.id;
    if (apiId == null) {
      _userApiService.debugLog('用户 API 脚本为空', type: DebugLogType.warn);
      return null;
    }

    _userApiService.debugLog('请求用户 API 获取播放地址 (source=$source, quality=$actualQuality)');
    var url = await _userApiService.getMusicUrl(
      apiId: apiId,
      music: music,
      quality: actualQuality,
    );

    // 兜底：仅当"无结果"（脚本没报错，可能只是该音质不可用）时用 128k 再试一次。
    // 脚本已明确报错（转链失败等）时跳过 —— 128k 同样会失败，白等只会拖慢换源
    if ((url == null || url.isEmpty) && actualQuality != '128k' && _userApiService.lastScriptError == null) {
      _userApiService.debugLog('$actualQuality 获取失败（无结果），尝试 128k 兜底', type: DebugLogType.warn);
      url = await _userApiService.getMusicUrl(
        apiId: apiId,
        music: music,
        quality: '128k',
      );
      if (url != null && url.isNotEmpty) {
        lastUsedQuality = '128k';
      }
    }

    if (url != null && url.isNotEmpty) {
      _userApiService.debugLog('用户 API 获取 URL 成功: $url');
      lastUsedQuality = actualQuality;
      return url;
    }

    // 检查是否有脚本错误（如 IP 封禁），直接抛出让上层展示
    final lastErr = _userApiService.lastScriptError;
    _userApiService.debugLog('用户 API 获取 URL 失败 (lastError=$lastErr)', type: DebugLogType.error);
    if (lastErr != null) {
      // 单歌失败（转链失败等）标记为可换源重试；全局错误（封禁/限流）不重试
      throw MusicUrlException(lastErr, retryable: !MusicUrlException.isFatal(lastErr));
    }

    return null;
  }

  /// 并行取 URL：用独立临时 JS 运行时，不与主运行时争抢 JS 锁。
  /// 供换源竞速使用（多个候选同时发起，谁先成功用谁）
  /// 音质预选（对齐原版 getPlayQuality）：
  /// 用户偏好 → 在「歌曲实际拥有(types) ∩ 脚本声明(qualitys)」中从高到低取第一个
  String pickQuality(String source, MusicInfo music, String preferred) {
    const order = ['flac24bit', 'flac', '320k', '192k', '128k'];
    final declared = _userApiService.sources[source]?.qualitys ?? const [];
    final musicTypes = music.types?.map((t) => t.type).toSet() ?? const <String>{};

    final reqIdx = order.indexOf(preferred);
    if (reqIdx < 0) return '128k';
    for (var i = reqIdx; i < order.length; i++) {
      final q = order[i];
      // 歌曲自带音质信息时必须命中（有信息而不命中，请求大概率失败）
      if (musicTypes.isNotEmpty && !musicTypes.contains(q)) continue;
      if (declared.isNotEmpty && !declared.contains(q)) continue;
      return q;
    }
    // 兜底：忽略歌曲信息按脚本声明选
    for (var i = reqIdx; i < order.length; i++) {
      if (declared.contains(order[i])) return order[i];
    }
    return '128k';
  }

  Future<String?> getMusicUrlParallel({
    required MusicInfo music,
    String quality = '320k',
  }) async {
    final source = music.source ?? 'kw';

    if (!_userApiService.isActive) return null;
    if (!_userApiService.sources.containsKey(source)) return null;

    final scriptActions = _userApiService.sources[source]?.actions ?? const [];
    if (scriptActions.isNotEmpty && !scriptActions.contains('musicUrl')) {
      return null;
    }

    final apiId = _userApiService.currentScript?.id;
    if (apiId == null) return null;

    // 音质预选：换源/预取与主路径同一标准
    final actualQuality = pickQuality(source, music, quality);

    return _userApiService.getMusicUrlParallel(
      apiId: apiId,
      music: music,
      quality: actualQuality,
    );
  }

  /// 获取歌词 - 通过用户自定义源API
  /// 脚本 init 时声明的 actions 里没有 'lyric' 的直接跳过
  /// （对齐原版：原版按 sources[].actions 注册 getLyric，未声明就不会调用，
  ///  避免对只支持 musicUrl 的脚本发 'lyric' 请求刷 "action not support" 错误）
  Future<Map<String, String?>?> getLyric({
    required MusicInfo music,
  }) async {
    if (!_userApiService.isActive) {
      return null;
    }

    final source = music.source ?? 'kw';
    final scriptActions = _userApiService.sources[source]?.actions;
    if (scriptActions == null || !scriptActions.contains('lyric')) {
      return null;
    }

    final apiId = _userApiService.currentScript?.id;
    if (apiId == null) {
      return null;
    }

    return await _userApiService.getLyric(
      apiId: apiId,
      music: music,
    );
  }
}

/// 播放地址获取异常（含脚本错误信息，如 IP 封禁）
class MusicUrlException implements Exception {
  final String message;
  /// 是否值得换源重试：单歌转链失败（如服务端 Object trans failure）可跨源恢复；
  /// 全局错误（IP 封禁/签名失败/限流）跨源同样会失败，直接终止
  final bool retryable;
  MusicUrlException(this.message, {this.retryable = false});
  @override
  String toString() => message;

  /// 全局性错误关键词（跨源重试无意义）
  static const _fatalKeywords = ['block ip', 'too many requests', '签名', '鉴权', 'forbidden', 'limit'];
  static bool isFatal(String msg) {
    final lower = msg.toLowerCase();
    return _fatalKeywords.any((k) => lower.contains(k));
  }
}
