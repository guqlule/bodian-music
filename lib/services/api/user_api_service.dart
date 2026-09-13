import 'dart:async';
import 'dart:convert';
import '../../core/utils/logger.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_js/flutter_js.dart';
import '../../core/storage/storage_service.dart';

class UserApiService {
  static final UserApiService _instance = UserApiService._internal();
  factory UserApiService() => _instance;

  /// 最后一次脚本错误信息（供上层展示给用户）
  String? lastScriptError;

  /// 最后一次激活/初始化失败的原因（与运行期 lastScriptError 分开，用于启动恢复时对齐 UI）
  String? lastActivationError;
  UserApiService._internal();

  final Map<String, UserApiScript> _scripts = {};
  UserApiScript? _currentScript;
  bool _isInitialized = false;
  JavascriptRuntime? _jsRuntime;
  Map<String, UserApiSource> _sources = {};
  bool _scriptInitialized = false;
  String? _updateUrl;

  // JS 运行时互斥锁：getMusicUrl/getLyric 共用 __lx_result__ 等全局槽，
  // 并发调用会互相污染结果，必须串行化
  Completer<void> _jsLockCompleter = Completer<void>()..complete();

  // 锁优先级：切歌取 URL 是高优（用户正在等），歌词/预取是低优（可被打断重跑）。
  // 高优请求发起时置抢占标记，低优任务在每个网络请求返回后检查标记，
  // 若被抢占则立即抛出让出锁 —— 用户切歌无需等歌词/预取的耗时请求
  int _lockEpoch = 0;
  bool _preemptRequested = false;

  /// 在 JS 锁内串行执行 [action]。
  /// [priority] true=高优（切歌），可抢占低优任务
  /// [timeout] 锁等待+执行总超时：超时快速失败让上层换源
  Future<T> _withJsLock<T>(Future<T> Function() action, {required bool priority, Duration timeout = const Duration(seconds: 10)}) {
    final prev = _jsLockCompleter;
    final completer = Completer<void>();
    _jsLockCompleter = completer;
    if (priority) {
      // 高优发起：标记抢占，让当前持锁的低优任务尽快让路
      _preemptRequested = true;
    }
    final myEpoch = ++_lockEpoch;

    Future<T> runWithTimeout() async {
      // 排队等待旧任务完成（上限 timeout）
      final waitStart = DateTime.now();
      while (!prev.isCompleted) {
        if (DateTime.now().difference(waitStart) > timeout) {
          _log('JS 锁等待超时，抛出异常', type: DebugLogType.warn);
          // 不再跳过锁继续执行，而是直接抛出异常让上层换源/重试，
          // 避免两个任务并发访问同一 JS 引擎导致状态污染卡死
          throw TimeoutException('JS lock wait timeout');
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (priority) _preemptRequested = false; // 高优开始执行，撤销抢占
      return action().timeout(timeout, onTimeout: () {
        _log('JS 任务执行超时', type: DebugLogType.warn);
        throw TimeoutException('JS task timeout');
      });
    }

    final resultFuture = runWithTimeout();
    resultFuture.whenComplete(() => completer.complete());
    return resultFuture;
  }

  /// 低优任务检查点：在高优等待时抛出让出锁（由网络请求间隙调用）
  void _checkPreempted() {
    if (_preemptRequested) {
      throw TimeoutException('preempted by user request');
    }
  }

  final _stateController = StreamController<UserApiServiceState>.broadcast();
  final _eventController = StreamController<UserApiEvent>.broadcast();

  /// 调试日志收集器（弹窗显示用）
  final List<DebugLog> debugLogs = [];
  void _log(String message, {DebugLogType type = DebugLogType.info}) {
    final log = DebugLog(
      time: DateTime.now(),
      type: type,
      message: message,
    );
    debugLogs.add(log);
    if (debugLogs.length > 500) {
      debugLogs.removeRange(0, debugLogs.length - 500);
    }
    logDebug('[Script] $message');
  }

  /// 供外部服务写入调试日志
  void debugLog(String message, {DebugLogType type = DebugLogType.info}) {
    _log(message, type: type);
  }

  String get debugLogText => debugLogs.map((l) => l.toString()).join('\n');

  Stream<UserApiServiceState> get stateStream => _stateController.stream;
  Stream<UserApiEvent> get eventStream => _eventController.stream;
  UserApiScript? get currentScript => _currentScript;
  bool get isInitialized => _isInitialized;
  bool get isActive => _currentScript != null && _scriptInitialized;
  UserApiScript? get currentApi => _currentScript;
  Map<String, UserApiSource> get sources => _sources;
  String? get updateUrl => _updateUrl;

  Future<void> init() async {
    // 防重复初始化：main 启动时已调用，provider 懒加载时再次调用会
    // 重发 loaded 状态、覆盖已恢复的 active 状态
    if (_isInitialized) return;
    _isInitialized = true;
    await _loadScriptsFromStorage();
    _stateController.add(UserApiServiceState.loaded);
  }

  Future<void> _loadScriptsFromStorage() async {
    try {
      final stored = StorageService().getUserApiScripts();
      if (stored == null || stored.isEmpty) return;
      for (final item in stored) {
        if (item is! Map) continue;
        final content = item['content']?.toString();
        if (content == null || content.isEmpty) continue;
        try {
          final script = UserApiScript.fromJson(Map<String, dynamic>.from(item), content: content);
          _scripts[script.id] = script;
        } catch (e) {
          logDebug('加载脚本失败: $e');
        }
      }
      if (_scripts.isNotEmpty) {
        _log('从本地加载 ${_scripts.length} 个脚本');
      }
    } catch (e) {
      logDebug('加载脚本列表失败: $e');
    }
  }

  Future<void> _saveScriptsToStorage() async {
    try {
      final list = _scripts.values.map((s) => {
        ...s.toJson(),
        'content': s.content,
      }).toList();
      await StorageService().saveUserApiScripts(list);
    } catch (e) {
      logDebug('保存脚本失败: $e');
    }
  }

  Future<UserApiScript> importScript(String scriptContent) async {
    try {
      _stateController.add(UserApiServiceState.loading);
      final info = _parseScriptMetadata(scriptContent);
      final scriptId = _generateId();
      final script = UserApiScript(
        id: scriptId,
        name: info['name'] ?? 'Unnamed Script',
        description: info['description'] ?? '',
        author: info['author'] ?? '',
        version: info['version'] ?? '1.0.0',
        homepage: info['homepage'] ?? '',
        content: scriptContent,
        importedAt: DateTime.now(),
      );
      _scripts[scriptId] = script;
      await _saveScriptsToStorage();
      _stateController.add(UserApiServiceState.loaded);
      _eventController.add(UserApiEvent.scriptImported(script));
      return script;
    } catch (e) {
      _stateController.add(UserApiServiceState.error);
      throw Exception('Failed to import script: $e');
    }
  }

  Map<String, String> _parseScriptMetadata(String script) {
    final info = <String, String>{};
    final commentMatch = RegExp(r'^/\*[\s\S]+?\*/').firstMatch(script);
    if (commentMatch == null) {
      throw Exception('Script must start with a block comment for metadata');
    }
    final commentBlock = commentMatch.group(0)!;
    final nameMatch = RegExp(r'@name\s+(.+)').firstMatch(commentBlock);
    if (nameMatch != null) info['name'] = _truncate(nameMatch.group(1)!.trim(), 24);
    final descMatch = RegExp(r'@description\s+(.+)').firstMatch(commentBlock);
    if (descMatch != null) info['description'] = _truncate(descMatch.group(1)!.trim(), 36);
    final authorMatch = RegExp(r'@author\s+(.+)').firstMatch(commentBlock);
    if (authorMatch != null) info['author'] = _truncate(authorMatch.group(1)!.trim(), 56);
    final versionMatch = RegExp(r'@version\s+(.+)').firstMatch(commentBlock);
    if (versionMatch != null) info['version'] = _truncate(versionMatch.group(1)!.trim(), 36);
    final homepageMatch = RegExp(r'@homepage\s+(.+)').firstMatch(commentBlock);
    if (homepageMatch != null) info['homepage'] = _truncate(homepageMatch.group(1)!.trim(), 1024);
    if (!info.containsKey('name')) {
      info['name'] = 'user_api_${DateTime.now().millisecondsSinceEpoch}';
    }
    return info;
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  String _generateId() {
    final random = DateTime.now().microsecondsSinceEpoch;
    final randomStr = (random % 1000).toString().padLeft(3, '0');
    return 'user_api_${randomStr}_$random';
  }

  /// 激活脚本（参考 lx-music-mobile setApiSource 模式）：
  /// 1. 立即持久化 activeScriptId —— 即使后续 JS 初始化失败，重启后仍会自动重试
  /// 2. 立即广播 active 状态 —— UI 立刻显示"初始化中"，不被 init 成败回滚
  /// 3. JS 初始化结果异步上报（scriptActivated / scriptError 事件）
  /// 注意：JS 初始化最久可能轮询 10 秒，不能阻塞状态上报，否则启动恢复期间
  /// UI（尤其懒加载的 provider）会错过事件导致"激活状态消失"
  Future<void> activateScript(String scriptId) async {
    if (!_scripts.containsKey(scriptId)) {
      throw Exception('Script not found: $scriptId');
    }
    final script = _scripts[scriptId]!;
    _currentScript = script;
    _scriptInitialized = false;
    _sources = {};
    _updateUrl = null;
    lastActivationError = null;
    lastScriptError = null;
    // 先持久化 + 立即广播，保证冷启动恢复路径上状态不丢失
    await StorageService().setUserApiActiveScriptId(scriptId);
    _stateController.add(UserApiServiceState.loading);
    _eventController.add(UserApiEvent.scriptActivated(script));
    // 异步初始化 JS 运行时，完成后上报真实初始化结果
    unawaited(_initScriptRuntime(script));
  }

  /// JS 运行时初始化进行中的等待门（冷启动恢复 + playOnBoot 立即播放时，
  /// 播放请求需等待初始化完成，而不是直接失败）
  Completer<void>? _initCompleter;

  /// 执行脚本并等待 init 数据，结果通过事件上报（不抛异常给调用方）
  Future<void> _initScriptRuntime(UserApiScript script) async {
    final scriptId = script.id;
    // 初始化期间用户切换到其它脚本或停用，放弃本次过期初始化
    if (_currentScript?.id != scriptId) return;
    final completer = Completer<void>();
    _initCompleter = completer;
    try {
      await _initJsRuntime(script);
      if (_currentScript?.id != scriptId) return;
      if (_scriptInitialized) {
        _log('脚本激活完成: ${script.name}');
        _stateController.add(UserApiServiceState.active);
      } else {
        lastActivationError = '脚本初始化超时，未收到音源注册数据';
        _log('脚本激活失败: ${lastActivationError}', type: DebugLogType.warn);
        _stateController.add(UserApiServiceState.error);
        _eventController.add(UserApiEvent.scriptError(script, lastActivationError));
      }
    } catch (e) {
      if (_currentScript?.id != scriptId) return;
      lastActivationError = e.toString();
      _log('脚本激活异常: $e', type: DebugLogType.error);
      _stateController.add(UserApiServiceState.error);
      _eventController.add(UserApiEvent.scriptError(script, lastActivationError));
    } finally {
      if (identical(_initCompleter, completer)) _initCompleter = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// 等待当前激活脚本的 JS 初始化完成（若正在进行）
  Future<void> _waitForScriptInit() async {
    final initWait = _initCompleter;
    if (initWait != null && !initWait.isCompleted) {
      _log('等待脚本初始化完成...');
      try {
        await initWait.future.timeout(const Duration(seconds: 15));
      } on TimeoutException {
        _log('等待脚本初始化超时', type: DebugLogType.warn);
      }
    }
  }

  // ===================== JS Runtime =====================

  Future<void> _initJsRuntime(UserApiScript script) async {
    debugLogs.clear();
    _log('=== 初始化用户 API 脚本 ===');
    _jsRuntime?.dispose();
    _jsRuntime = getJavascriptRuntime();
    _setupLxApi(script);
    _log('执行脚本 (${script.name} v${script.version})...');
    final result = _jsRuntime!.evaluate(script.content);
    if (result.isError) {
      _log('脚本执行错误: ${result.stringResult}', type: DebugLogType.error);
      throw Exception('Script execution error: ${result.stringResult}');
    }
    _log('脚本执行成功');

    // 同步脚本（如 ikun/lx）在 evaluate 期间就已调用 send('inited', ...)，
    // 先立即检查，避免无谓地进入耗时轮询
    var initData = _jsRuntime!.evaluate('globalThis.__lx_init_data__');
    if (!initData.isError && initData.stringResult != 'null' && initData.stringResult.isNotEmpty) {
      _log('收到初始化数据(同步): ${initData.stringResult.substring(0, initData.stringResult.length > 200 ? 200 : initData.stringResult.length)}');
      _parseInitData(initData.stringResult);
      _checkUpdateAlert();
      _scriptInitialized = true;
      _log('脚本初始化成功，已注册音源: ${_sources.keys.join(', ')}');
      return;
    }

    _log('同步阶段未收到 init 数据，进入异步轮询...');
    // 循环轮询：处理 HTTP 请求 + 刷新 JS 微任务 + 检查 init 数据
    for (var i = 0; i < 100; i++) {
      // 一次性处理队列中所有 HTTP 请求
      await _processPendingRequests(null, 50);
      // 刷新 JS 微任务链（Promise then/catch、async/await 续行）
      for (var j = 0; j < 20; j++) {
        _jsRuntime!.executePendingJob();
      }
      // 让出事件循环，避免同步 FFI 连续阻塞 UI
      await Future.delayed(Duration.zero);
      // 先检查 updateAlert（脚本可能因 paused 主动设置后不再发 init）
      // 必须在 _checkUpdateAlert() 清除之前检查
      final alertCheck = _jsRuntime!.evaluate('globalThis.__lx_update_alert__');
      if (!alertCheck.isError && alertCheck.stringResult != 'null' && alertCheck.stringResult.isNotEmpty) {
        _checkUpdateAlert();
        // 脚本已主动声明停用/更新，不再等待 init 数据
        final msg = _updateUrl != null ? '脚本已停用，请更新: $_updateUrl' : '脚本已停用，请获取最新版本';
        _log('脚本停用检测: $msg', type: DebugLogType.warn);
        throw Exception(msg);
      }
      _checkUpdateAlert();
      initData = _jsRuntime!.evaluate('globalThis.__lx_init_data__');
      if (!initData.isError && initData.stringResult != 'null' && initData.stringResult.isNotEmpty) {
        _log('收到初始化数据(异步轮询 #${i + 1}): ${initData.stringResult.substring(0, initData.stringResult.length > 200 ? 200 : initData.stringResult.length)}');
        _parseInitData(initData.stringResult);
        _checkUpdateAlert();
        _scriptInitialized = true;
        _log('脚本初始化成功，已注册音源: ${_sources.keys.join(', ')}');
        return;
      }
      // 如果队列为空且 init 数据未到，说明脚本没有更多异步操作了
      final qLen = _jsRuntime!.evaluate('globalThis.__lx_request_queue__.length');
      if (qLen.isError || qLen.stringResult == '0') break;
    }
    // 未收到 init 数据 —— 不设置 _scriptInitialized，isActive 将返回 false
    _log('初始化完成但未收到 init 数据，音源未注册（isActive=false）', type: DebugLogType.warn);
    throw Exception('脚本初始化失败，未收到音源注册数据');
  }

  /// 读取脚本上报的 updateAlert（对齐原版 showUpdateAlert：提示有新版本）
  void _checkUpdateAlert() {
    final alert = _jsRuntime!.evaluate('globalThis.__lx_update_alert__');
    if (alert.isError || alert.stringResult == 'null' || alert.stringResult.isEmpty) return;
    _jsRuntime!.evaluate('globalThis.__lx_update_alert__ = null');
    try {
      final data = jsonDecode(alert.stringResult);
      final log = data['log']?.toString() ?? '';
      final updateUrl = data['updateUrl']?.toString();
      _log('脚本版本更新提示: $log${updateUrl != null ? ' (更新地址: $updateUrl)' : ''}', type: DebugLogType.warn);
      if (updateUrl != null && updateUrl.isNotEmpty) {
        _updateUrl = updateUrl;
      }
    } catch (e) {
      _log('updateAlert 解析失败: $e', type: DebugLogType.warn);
    }
  }

  /// 搭建 lx 桥接环境（主运行时与临时并行运行时共用）
  void _setupLxApi(UserApiScript script, [JavascriptRuntime? targetRuntime]) {
    final rawScript = script.content;
    final runtime = targetRuntime ?? _jsRuntime!;

    /// evaluate 并校验结果：桥接环境的语法错误绝不能静默吞掉
    /// （否则 lx/utils 未定义，脚本全部失败且无任何日志）
    void evalOrThrow(String code, String label) {
      final r = runtime.evaluate(code);
      if (r.isError) {
        _log('JS 环境[$label] 加载失败: ${r.stringResult}', type: DebugLogType.error);
        throw Exception('UserApi JS env [$label] error: ${r.stringResult}');
      }
    }

    evalOrThrow('''
      globalThis.__lx_handlers__ = {};
      globalThis.__lx_init_data__ = null;
      globalThis.__lx_result__ = null;
      globalThis.__lx_request_queue__ = [];
      globalThis.__lx_update_alert__ = null;
      globalThis.__lx_inited__ = false;
    ''', 'slots');

    // ===== 兼容性 Polyfill（对齐 lx-music-mobile user-api-preload.js）=====
    // flutter_js 仅提供 setTimeout（经原生通道），缺 clearTimeout / setInterval
    runtime.evaluate('''
      if (typeof globalThis.clearTimeout !== 'function') {
        globalThis.clearTimeout = function(id) {
          try {
            if (typeof __NATIVE_FLUTTER_JS__setTimeoutCallbacks !== 'undefined') {
              delete __NATIVE_FLUTTER_JS__setTimeoutCallbacks[String(id)];
            }
          } catch (e) {}
        };
      }
      var __lx_intervals__ = {};
      if (typeof globalThis.setInterval !== 'function') {
        globalThis.setInterval = function(fn, ms) {
          if (typeof fn !== 'function') throw new Error('callback required a function');
          var args = Array.prototype.slice.call(arguments, 2);
          var id = null;
          var stopped = false;
          var run = function() {
            if (stopped) return;
            try { fn.apply(null, args); } catch (e) {}
            id = setTimeout(run, ms);
          };
          id = setTimeout(run, ms);
          __lx_intervals__[id] = true;
          return id;
        };
      }
      if (typeof globalThis.clearInterval !== 'function') {
        globalThis.clearInterval = function(id) {
          if (id in __lx_intervals__) {
            delete __lx_intervals__[id];
          }
          clearTimeout(id);
        };
      }
      // console 补齐（flutter_js 只有 log/warn/error）
      if (typeof console.info !== 'function') console.info = console.log;
      if (typeof console.debug !== 'function') console.debug = console.log;
      // btoa / atob（部分脚本使用）
      if (typeof globalThis.btoa !== 'function') {
        globalThis.btoa = function(input) {
          var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
          var bytes = [];
          for (var i = 0; i < input.length; i++) {
            var c = input.charCodeAt(i);
            if (c < 128) bytes.push(c);
            else if (c < 2048) { bytes.push((c >> 6) | 192, (c & 63) | 128); }
            else { bytes.push((c >> 12) | 224, ((c >> 6) & 63) | 128, (c & 63) | 128); }
          }
          var out = '';
          for (var j = 0; j < bytes.length; j += 3) {
            var b1 = bytes[j], b2 = j + 1 < bytes.length ? bytes[j + 1] : -1, b3 = j + 2 < bytes.length ? bytes[j + 2] : -1;
            out += chars.charAt(b1 >> 2);
            out += chars.charAt(((b1 & 3) << 4) | (b2 >= 0 ? b2 >> 4 : 0));
            out += b2 >= 0 ? chars.charAt(((b2 & 15) << 2) | (b3 >= 0 ? b3 >> 6 : 0)) : '=';
            out += b3 >= 0 ? chars.charAt(b3 & 63) : '=';
          }
          return out;
        };
      }
      if (typeof globalThis.atob !== 'function') {
        globalThis.atob = function(input) {
          var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
          var clean = String(input).replace(/[^A-Za-z0-9+\\/]/g, '');
          var out = '';
          for (var i = 0; i < clean.length; i += 4) {
            var a = chars.indexOf(clean[i]);
            var b = chars.indexOf(clean[i + 1]);
            var c = chars.indexOf(clean[i + 2]);
            var d = chars.indexOf(clean[i + 3]);
            out += String.fromCharCode((a << 2) | (b >> 4));
            if (c >= 0 && c < 64) out += String.fromCharCode(((b & 15) << 4) | (c >> 2));
            if (d >= 0 && d < 64) out += String.fromCharCode(((c & 3) << 6) | d);
          }
          return out;
        };
      }
      // 响应头大小写兼容：Dart http 会把响应头 key 转小写，
      // 脚本按原始大小写（如 headers['Content-Type']）取值会失败
      globalThis.__lx_wrap_headers__ = function(headers) {
        if (!headers || typeof headers !== 'object') return headers;
        try {
          return new Proxy(headers, {
            get: function(target, prop) {
              if (prop in target) return target[prop];
              var l = String(prop).toLowerCase();
              for (var k in target) {
                if (k.toLowerCase() === l) return target[k];
              }
              return undefined;
            },
            has: function(target, prop) {
              if (prop in target) return true;
              var l = String(prop).toLowerCase();
              for (var k in target) {
                if (k.toLowerCase() === l) return true;
              }
              return false;
            }
          });
        } catch (e) {
          return headers;
        }
      };
    ''');

    // Inject real MD5 implementation
    evalOrThrow('''
(function() {
  // 标准 blueimp MD5 实现（与 lx-music 原生 MD5 一致，含 UTF-8 支持）
  function safeAdd(x, y) {
    var lsw = (x & 0xffff) + (y & 0xffff)
    var msw = (x >> 16) + (y >> 16) + (lsw >> 16)
    return (msw << 16) | (lsw & 0xffff)
  }
  function bitRotateLeft(num, cnt) {
    return (num << cnt) | (num >>> (32 - cnt))
  }
  function md5cmn(q, a, b, x, s, t) {
    return safeAdd(bitRotateLeft(safeAdd(safeAdd(a, q), safeAdd(x, t)), s), b)
  }
  function md5ff(a, b, c, d, x, s, t) {
    return md5cmn((b & c) | (~b & d), a, b, x, s, t)
  }
  function md5gg(a, b, c, d, x, s, t) {
    return md5cmn((b & d) | (c & ~d), a, b, x, s, t)
  }
  function md5hh(a, b, c, d, x, s, t) {
    return md5cmn(b ^ c ^ d, a, b, x, s, t)
  }
  function md5ii(a, b, c, d, x, s, t) {
    return md5cmn(c ^ (b | ~d), a, b, x, s, t)
  }
  function binlMD5(x, len) {
    x[len >> 5] |= 0x80 << len % 32
    x[(((len + 64) >>> 9) << 4) + 14] = len
    var i, olda, oldb, oldc, oldd
    var a = 1732584193
    var b = -271733879
    var c = -1732584194
    var d = 271733878
    for (i = 0; i < x.length; i += 16) {
      olda = a; oldb = b; oldc = c; oldd = d
      a = md5ff(a, b, c, d, x[i], 7, -680876936)
      d = md5ff(d, a, b, c, x[i + 1], 12, -389564586)
      c = md5ff(c, d, a, b, x[i + 2], 17, 606105819)
      b = md5ff(b, c, d, a, x[i + 3], 22, -1044525330)
      a = md5ff(a, b, c, d, x[i + 4], 7, -176418897)
      d = md5ff(d, a, b, c, x[i + 5], 12, 1200080426)
      c = md5ff(c, d, a, b, x[i + 6], 17, -1473231341)
      b = md5ff(b, c, d, a, x[i + 7], 22, -45705983)
      a = md5ff(a, b, c, d, x[i + 8], 7, 1770035416)
      d = md5ff(d, a, b, c, x[i + 9], 12, -1958414417)
      c = md5ff(c, d, a, b, x[i + 10], 17, -42063)
      b = md5ff(b, c, d, a, x[i + 11], 22, -1990404162)
      a = md5ff(a, b, c, d, x[i + 12], 7, 1804603682)
      d = md5ff(d, a, b, c, x[i + 13], 12, -40341101)
      c = md5ff(c, d, a, b, x[i + 14], 17, -1502002290)
      b = md5ff(b, c, d, a, x[i + 15], 22, 1236535329)
      a = md5gg(a, b, c, d, x[i + 1], 5, -165796510)
      d = md5gg(d, a, b, c, x[i + 6], 9, -1069501632)
      c = md5gg(c, d, a, b, x[i + 11], 14, 643717713)
      b = md5gg(b, c, d, a, x[i], 20, -373897302)
      a = md5gg(a, b, c, d, x[i + 5], 5, -701558691)
      d = md5gg(d, a, b, c, x[i + 10], 9, 38016083)
      c = md5gg(c, d, a, b, x[i + 15], 14, -660478335)
      b = md5gg(b, c, d, a, x[i + 4], 20, -405537848)
      a = md5gg(a, b, c, d, x[i + 9], 5, 568446438)
      d = md5gg(d, a, b, c, x[i + 14], 9, -1019803690)
      c = md5gg(c, d, a, b, x[i + 3], 14, -187363961)
      b = md5gg(b, c, d, a, x[i + 8], 20, 1163531501)
      a = md5gg(a, b, c, d, x[i + 13], 5, -1444681467)
      d = md5gg(d, a, b, c, x[i + 2], 9, -51403784)
      c = md5gg(c, d, a, b, x[i + 7], 14, 1735328473)
      b = md5gg(b, c, d, a, x[i + 12], 20, -1926607734)
      a = md5hh(a, b, c, d, x[i + 5], 4, -378558)
      d = md5hh(d, a, b, c, x[i + 8], 11, -2022574463)
      c = md5hh(c, d, a, b, x[i + 11], 16, 1839030562)
      b = md5hh(b, c, d, a, x[i + 14], 23, -35309556)
      a = md5hh(a, b, c, d, x[i + 1], 4, -1530992060)
      d = md5hh(d, a, b, c, x[i + 4], 11, 1272893353)
      c = md5hh(c, d, a, b, x[i + 7], 16, -155497632)
      b = md5hh(b, c, d, a, x[i + 10], 23, -1094730640)
      a = md5hh(a, b, c, d, x[i + 13], 4, 681279174)
      d = md5hh(d, a, b, c, x[i], 11, -358537222)
      c = md5hh(c, d, a, b, x[i + 3], 16, -722521979)
      b = md5hh(b, c, d, a, x[i + 6], 23, 76029189)
      a = md5hh(a, b, c, d, x[i + 9], 4, -640364487)
      d = md5hh(d, a, b, c, x[i + 12], 11, -421815835)
      c = md5hh(c, d, a, b, x[i + 15], 16, 530742520)
      b = md5hh(b, c, d, a, x[i + 2], 23, -995338651)
      a = md5ii(a, b, c, d, x[i], 6, -198630844)
      d = md5ii(d, a, b, c, x[i + 7], 10, 1126891415)
      c = md5ii(c, d, a, b, x[i + 14], 15, -1416354905)
      b = md5ii(b, c, d, a, x[i + 5], 21, -57434055)
      a = md5ii(a, b, c, d, x[i + 12], 6, 1700485571)
      d = md5ii(d, a, b, c, x[i + 3], 10, -1894986606)
      c = md5ii(c, d, a, b, x[i + 10], 15, -1051523)
      b = md5ii(b, c, d, a, x[i + 1], 21, -2054922799)
      a = md5ii(a, b, c, d, x[i + 8], 6, 1873313359)
      d = md5ii(d, a, b, c, x[i + 15], 10, -30611744)
      c = md5ii(c, d, a, b, x[i + 6], 15, -1560198380)
      b = md5ii(b, c, d, a, x[i + 13], 21, 1309151649)
      a = md5ii(a, b, c, d, x[i + 4], 6, -145523070)
      d = md5ii(d, a, b, c, x[i + 11], 10, -1120210379)
      c = md5ii(c, d, a, b, x[i + 2], 15, 718787259)
      b = md5ii(b, c, d, a, x[i + 9], 21, -343485551)
      a = safeAdd(a, olda)
      b = safeAdd(b, oldb)
      c = safeAdd(c, oldc)
      d = safeAdd(d, oldd)
    }
    return [a, b, c, d]
  }
  function binl2rstr(input) {
    var i, output = ''
    var length32 = input.length * 32
    for (i = 0; i < length32; i += 8) {
      output += String.fromCharCode((input[i >> 5] >>> i % 32) & 0xff)
    }
    return output
  }
  function rstr2binl(input) {
    var i, output = []
    output[(input.length >> 2) - 1] = undefined
    for (i = 0; i < output.length; i += 1) { output[i] = 0 }
    var length8 = input.length * 8
    for (i = 0; i < length8; i += 8) {
      output[i >> 5] |= (input.charCodeAt(i / 8) & 0xff) << i % 32
    }
    return output
  }
  function rstrMD5(s) {
    return binl2rstr(binlMD5(rstr2binl(s), s.length * 8))
  }
  function rstr2hex(input) {
    var hexTab = '0123456789abcdef'
    var output = ''
    var x, i
    for (i = 0; i < input.length; i += 1) {
      x = input.charCodeAt(i)
      output += hexTab.charAt((x >>> 4) & 0x0f) + hexTab.charAt(x & 0x0f)
    }
    return output
  }
  function str2rstrUTF8(input) {
    // 手动 UTF-8 编码（支持 4 字节 emoji，不依赖 unescape）
    var res = '';
    for (var n = 0; n < input.length; n++) {
      var c = input.charCodeAt(n);
      if (c < 128) {
        res += String.fromCharCode(c);
      } else if (c > 127 && c < 2048) {
        res += String.fromCharCode((c >> 6) | 192);
        res += String.fromCharCode((c & 63) | 128);
      } else if (c >= 0xD800 && c <= 0xDBFF && n + 1 < input.length) {
        // 代理对（4 字节字符，如 emoji）
        var c2 = input.charCodeAt(n + 1);
        if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
          var cp = ((c - 0xD800) * 0x400) + (c2 - 0xDC00) + 0x10000;
          res += String.fromCharCode((cp >> 18) | 240);
          res += String.fromCharCode(((cp >> 12) & 63) | 128);
          res += String.fromCharCode(((cp >> 6) & 63) | 128);
          res += String.fromCharCode((cp & 63) | 128);
          n++;
          continue;
        }
      } else {
        res += String.fromCharCode((c >> 12) | 224);
        res += String.fromCharCode(((c >> 6) & 63) | 128);
        res += String.fromCharCode((c & 63) | 128);
      }
    }
    return res;
  }
  function rawMD5(s) {
    return rstrMD5(str2rstrUTF8(s))
  }
  function hexMD5(s) {
    return rstr2hex(rawMD5(s))
  }
  var md5 = function(string, key, raw) {
    if (!key) {
      if (!raw) return hexMD5(string)
      return rawMD5(string)
    }
    if (!raw) return hexMD5(string)
    return rawMD5(string)
  };
  globalThis.__lx_md5__ = md5;
})();

globalThis.__lx_utils__ = {
    crypto: {
      md5: function(str) {
        if (typeof str !== 'string') throw new Error('param required a string');
        return globalThis.__lx_md5__(str);
      },
      // 对齐原版：随机字节（纯 JS 实现）
      randomBytes: function(size) {
        var byteArray = new Uint8Array(size);
        for (var i = 0; i < size; i++) {
          byteArray[i] = Math.floor(Math.random() * 256);
        }
        return byteArray;
      }
    },
    buffer: {
      from: function(input, encoding) {
        if (typeof input === 'string') {
          switch (encoding) {
            case 'base64': {
              // Pure JS base64 decode
              var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
              var bytes = [];
              for (var i = 0; i < input.length; i += 4) {
                var a = chars.indexOf(input[i]);
                var b = chars.indexOf(input[i + 1] || '=');
                var c = chars.indexOf(input[i + 2] || '=');
                var d = chars.indexOf(input[i + 3] || '=');
                bytes.push((a << 2) | (b >> 4));
                if (c !== -1) bytes.push(((b & 15) << 4) | (c >> 2));
                if (d !== -1) bytes.push(((c & 3) << 6) | d);
              }
              return bytes;
            }
            case 'hex':
              var hexBytes = [];
              for (var i = 0; i < input.length; i += 2)
                hexBytes.push(parseInt(input.substring(i, i + 2), 16));
              return hexBytes;
            default:
              // UTF-8 string to bytes
              var utf8Bytes = [];
              for (var i = 0; i < input.length; i++) {
                var c = input.charCodeAt(i);
                if (c < 128) {
                  utf8Bytes.push(c);
                } else if (c < 2048) {
                  utf8Bytes.push((c >> 6) | 192);
                  utf8Bytes.push((c & 63) | 128);
                } else {
                  utf8Bytes.push((c >> 12) | 224);
                  utf8Bytes.push(((c >> 6) & 63) | 128);
                  utf8Bytes.push((c & 63) | 128);
                }
              }
              return utf8Bytes;
          }
        } else if (Array.isArray(input)) {
          return input;
        }
        throw new Error('Unsupported input type');
      },
      bufToString: function(buf, format) {
        if (Array.isArray(buf)) {
          switch (format) {
            case 'hex':
              var hex = '';
              for (var i = 0; i < buf.length; i++)
                hex += (buf[i] & 0xff).toString(16).padStart(2, '0');
              return hex;
            case 'base64': {
              var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
              var result = '';
              for (var i = 0; i < buf.length; i += 3) {
                var a = buf[i], b = buf[i + 1] || 0, c = buf[i + 2] || 0;
                result += chars[a >> 2] + chars[((a & 3) << 4) | (b >> 4)];
                if (i + 1 < buf.length) result += chars[((b & 15) << 2) | (c >> 6)];
                else result += '=';
                if (i + 2 < buf.length) result += chars[c & 63];
                else result += '=';
              }
              return result;
            }
            case 'utf8':
            case 'utf-8':
            default:
              var result = '';
              var i = 0;
              while (i < buf.length) {
                var byte = buf[i];
                if (byte < 128) {
                  result += String.fromCharCode(byte);
                  i++;
                } else if (byte >= 192 && byte < 224) {
                  result += String.fromCharCode(((byte & 31) << 6) | (buf[i + 1] & 63));
                  i += 2;
                } else {
                  result += String.fromCharCode(((byte & 15) << 12) | ((buf[i + 1] & 63) << 6) | (buf[i + 2] & 63));
                  i += 3;
                }
              }
              return result;
          }
        }
        throw new Error('Input is not a valid buffer');
      }
    },
    string: {
      match: function(str, pattern) {
        try {
          var re = new RegExp(pattern);
          var result = str.match(re);
          return result ? result[0] : null;
        } catch(e) {
          return null;
        }
      }
    }
  };
  // Node 风格 Buffer 兼容（部分移植脚本使用 Buffer.from/toString）
  if (typeof globalThis.Buffer === 'undefined') {
    globalThis.Buffer = {
      from: function(input, encoding) { return globalThis.__lx_utils__.buffer.from(input, encoding); },
      isBuffer: function(obj) { return obj instanceof Uint8Array || Array.isArray(obj); }
    };
    globalThis.Buffer.prototype = {
      toString: function(format) { return globalThis.__lx_utils__.buffer.bufToString(this, format); }
    };
  }
    ''', 'md5');

    evalOrThrow('''
      globalThis.lx = {
        EVENT_NAMES: {
          request: 'request',
          response: 'response',
          inited: 'inited',
          updateAlert: 'updateAlert'
        },
        // 对齐原版：固定 API 版本号（脚本用它在多版本宿主间做特性检测，
        // 传脚本自身版本会让检测走错分支）
        version: '2.0.0',
        currentScriptInfo: {
          name: ${jsonEncode(script.name)},
          version: ${jsonEncode(script.version)},
          author: ${jsonEncode(script.author)},
          description: ${jsonEncode(script.description)},
          homepage: ${jsonEncode(script.homepage)},
          rawScript: ${jsonEncode(rawScript)}
        },
        env: '',
        utils: globalThis.__lx_utils__,
        request: function(url, options, callback) {
          if (typeof options === 'function') {
            callback = options;
            options = {};
          }
          options = options || {};
          var settled = false;
          var requestInfo = { aborted: false };
          var doRequest = function(resolve, reject) {
            globalThis.__lx_request_queue__.push({
              url: url, options: options, requestInfo: requestInfo,
              hasCallback: false,
              resolve: function(resp) {
                if (settled || requestInfo.aborted) return; settled = true;
                if (resolve) resolve(resp);
              },
              reject: function(err) {
                if (settled || requestInfo.aborted) return; settled = true;
                if (reject) reject(err);
              }
            });
          };
          if (typeof callback === 'function') {
            // 回调风格（对齐原版）：成功 callback(null, resp, resp.body)，失败 callback(err)；返回 abort 闭包
            doRequest(function(resp) { callback(null, resp, resp ? resp.body : null); },
              function(err) { callback(err, null, null); });
            return function() {
              requestInfo.aborted = true;
            };
          }
          // Promise 风格（本应用扩展，await lx.request(...)）
          return new Promise(function(resolve, reject) { doRequest(resolve, reject); });
        },
        on: function(event, handler) {
          // 对齐原版：返回 Promise，脚本可能 .catch()
          if (event !== 'request') {
            return Promise.reject(new Error('The event is not supported: ' + event));
          }
          globalThis.__lx_handlers__[event] = handler;
          return Promise.resolve();
        },
        send: function(event, data) {
          // 对齐原版：返回 Promise；inited 只允许一次；支持 updateAlert
          return new Promise(function(resolve, reject) {
            if (event === 'inited' || event === 'init') {
              if (globalThis.__lx_inited__) return reject(new Error('Script is inited'));
              globalThis.__lx_inited__ = true;
              try {
                globalThis.__lx_init_data__ = JSON.stringify(data);
                resolve();
              } catch (e) { reject(e); }
            } else if (event === 'updateAlert') {
              try {
                if (!data || typeof data !== 'object' || !data.log) throw new Error('log is required.');
                globalThis.__lx_update_alert__ = JSON.stringify({ log: String(data.log).substring(0, 1024), updateUrl: data.updateUrl || null });
                resolve();
              } catch (e) { reject(e); }
            } else {
              reject(new Error('The event is not supported: ' + event));
            }
          });
        }
      };
    ''', 'lx');
  }

  // ===================== Request Processing =====================

  /// 全局 HTTP 连接池：复用 TCP/TLS 连接（原版 fetch 走 RN 网络栈自带连接池，
  /// 我们每次 new Client 都重新握手，慢 200~500ms/请求）
  static final http.Client _sharedHttpClient = http.Client();

  /// 处理队列中的 HTTP 请求：快照队列后并行处理（脚本一次取 URL 常并行发多个
  /// lx.request —— 签名/转链，串行处理时间相加，原版 fetch 天然并发）
  /// 响应统一通过 item.resolve(item) 交付（callback 风格已在 lx.request 内包装成 resolve/reject）
  Future<void> _processPendingRequests([JavascriptRuntime? runtime, int maxIterations = 100]) async {
    final rt = runtime ?? _jsRuntime!;
    // 1) 快照：一次性取出队列中所有待处理请求（Dart 侧逐项持有，JS 侧先不弹出）
    final items = <({Map<String, dynamic> data})>[];
    for (var i = 0; i < maxIterations; i++) {
      final metaResult = rt.evaluate('''
          (function() {
            var item = globalThis.__lx_request_queue__[$i];
            if (!item) return null;
            return JSON.stringify({idx: $i, url: item.url, options: item.options, aborted: item.requestInfo ? item.requestInfo.aborted : false});
          })()
        ''');
      if (metaResult.isError || metaResult.stringResult == 'null' || metaResult.stringResult.isEmpty) {
        break;
      }
      final requestData = jsonDecode(metaResult.stringResult);
      final idx = requestData['idx'] as int;
      final url = requestData['url']?.toString() ?? '';
      final aborted = requestData['aborted'] == true;
      if (aborted) {
        _log('请求已取消（脚本 abort）: $url', type: DebugLogType.warn);
        rt.evaluate('''
            (function() {
              var item = globalThis.__lx_request_queue__.shift();
              if (item && item.reject) { try { item.reject(new Error('request aborted')); } catch(_) {} }
            })()
          ''');
        i--; // 弹出后队列左移，重查当前下标
        continue;
      }
      final options = requestData['options'] as Map<String, dynamic>? ?? {};
      items.add((data: {...requestData, 'options': options},));
      if (items.length >= 20) break; // 单批上限，防极端长队
      // 每5项让出一次事件循环，避免快照阶段连续阻塞 UI
      if (items.length % 5 == 0) await Future.delayed(Duration.zero);
    }
    if (items.isEmpty) return;

    _log('并行处理 ${items.length} 个请求');

    // 抢占检查点：高优切歌在等锁时，低优任务让出（异常由调用方捕获）\n    _checkPreempted();\n\n    // 2) 并行发出所有 HTTP 请求（共享连接池，复用 TLS）
    final responses = await Future.wait(items.map((item) async {
      try {
        final resp = await _makeHttpRequest(item.data['url']?.toString() ?? '', item.data['options']);
        return (item: item, resp: resp);
      } catch (e) {
        return (item: item, resp: null as Map<String, dynamic>?);
      }
    }));

    // 3) 按原入队顺序逐个弹出并交付响应（JS 单线程，逐项 evaluate）
    for (final r in responses) {
      final item = r.item;
      final resp = r.resp;
      if (resp == null) {
        final safeErr = jsonEncode('request failed');
        rt.evaluate('globalThis.__lx_last_request_error__ = $safeErr');
        rt.evaluate('''
          (function() {
            var item = globalThis.__lx_request_queue__.shift();
            var msg = globalThis.__lx_last_request_error__;
            globalThis.__lx_last_request_error__ = null;
            if (item && item.reject) {
              try { item.reject(new Error(msg)); } catch(_) {}
            }
          })()
        ''');
        continue;
      }
      final fullResponse = {
        'statusCode': resp['statusCode'],
        'statusMessage': resp['statusMessage'],
        'headers': resp['headers'],
        'body': resp['body'],
        'ok': resp['ok'],
        'url': resp['url'],
      };
      final bodyStr = jsonEncode(resp['body']);
      _log('响应 ${resp['statusCode']}: ${bodyStr.substring(0, bodyStr.length > 200 ? 200 : bodyStr.length)}');

      final responseJson = jsonEncode(fullResponse);
      final safeJson = responseJson.codeUnits.map((c) => '\\u${c.toRadixString(16).padLeft(4, '0')}').join('');
      rt.evaluate('globalThis.__lx_callback_response__ = "$safeJson"');
      rt.evaluate('''
          (function() {
            var item = globalThis.__lx_request_queue__.shift();
            if (!item || !item.resolve) return;
            var raw = globalThis.__lx_callback_response__;
            globalThis.__lx_callback_response__ = null;
            try {
              var resp = JSON.parse(raw);
              // headers 大小写兼容包装
              resp.headers = __lx_wrap_headers__(resp.headers);
              item.resolve(resp);
            } catch(e) {
              if (item.reject) { try { item.reject(new Error(e && e.message ? e.message : String(e))); } catch(_) {} }
            }
          })()
        ''');

      final errCheck = rt.evaluate('globalThis.__lx_last_error__');
      if (!errCheck.isError && errCheck.stringResult != 'null' && errCheck.stringResult.isNotEmpty) {
        _log('脚本回调错误: ${errCheck.stringResult}', type: DebugLogType.error);
        rt.evaluate('globalThis.__lx_last_error__ = null');
      }
      // 每个响应交付后让出事件循环，避免连续 evaluate 阻塞 UI
      await Future.delayed(Duration.zero);
    }
  }
  // ===================== Source Registration =====================

  void _parseInitData(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr);
      if (data is Map) {
        final sourcesData = data['sources'];
        if (sourcesData is Map && sourcesData.isNotEmpty) {
          _sources = {};
          sourcesData.forEach((key, value) {
            if (value is Map) {
              _sources[key] = UserApiSource(
                type: value['type']?.toString() ?? 'music',
                actions: List<String>.from(value['actions'] ?? []),
                qualitys: List<String>.from(value['qualitys'] ?? []),
              );
            }
          });
          _log('注册音源: ${_sources.keys.join(', ')} (共 ${_sources.length} 个)');
        } else {
          _log('init 数据中 sources 为空或非 Map: $sourcesData', type: DebugLogType.warn);
        }
        final updateUrl = data['updateUrl'];
        if (updateUrl != null) {
          _updateUrl = updateUrl.toString();
        }
      } else {
        _log('init 数据顶层非 Map: ${jsonStr.substring(0, jsonStr.length > 200 ? 200 : jsonStr.length)}', type: DebugLogType.warn);
      }
    } catch (e) {
      _log('解析初始化数据错误: $e', type: DebugLogType.error);
    }
  }

  // ===================== Music URL via User API =====================

  Future<String?> getMusicUrl({
    required String apiId,
    required dynamic music,
    String quality = '320k',
  }) async {
    try {
      return await _withJsLock(() => _getMusicUrlLocked(apiId, music, quality), priority: true);
    } on TimeoutException {
      _log('获取播放地址超时（锁等待或执行超 20s）', type: DebugLogType.warn);
      return null;
    }
  }

  /// 获取播放地址超时（锁等待或执行超时）
  Future<String?> getMusicUrlParallel({
    required String apiId,
    required dynamic music,
    String quality = '320k',
  }) async {
    final script = _scripts[apiId];
    if (script == null) return null;
    if (!_scriptInitialized) return null;

    // 独立临时运行时：环境、请求队列、结果槽全部隔离，
    // 与主运行时并行工作互不污染（跨源并行换源用）
    JavascriptRuntime? tempRuntime;
    // 整体 15 秒超时：防止脚本卡死导致换源流程无限等待
    try {
      return await _doGetMusicUrlParallel(script, music, quality).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          _log('getMusicUrlParallel 整体超时 15s，放弃', type: DebugLogType.warn);
          try { tempRuntime?.dispose(); } catch (_) {}
          return null;
        },
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _doGetMusicUrlParallel(dynamic script, dynamic music, String quality) async {
    JavascriptRuntime? tempRuntime;
    try {
      tempRuntime = getJavascriptRuntime();
      // 完整 lx 环境（polyfill/utils/lx），与主运行时同一套实现
      _setupLxApi(script, tempRuntime);
      // 同步初始化（脚本 evaluate 即注册 handler/inited）
      final execResult = tempRuntime.evaluate(script.content);
      if (execResult.isError) {
        _log('临时运行时脚本执行失败: ${execResult.stringResult}', type: DebugLogType.error);
        return null;
      }
      // 等待 init（同步→轮询，与主运行时逻辑一致但更快退出）
      final initOk = await _waitForInitOnRuntime(tempRuntime);
      if (!initOk) return null;

      final url = await _fetchUrlOnRuntime(tempRuntime, music, quality);
      return url;
    } catch (e) {
      _log('并行取 URL 异常: $e', type: DebugLogType.warn);
      return null;
    } finally {
      tempRuntime?.dispose();
    }
  }

  /// 在指定运行时上等待脚本 init 数据（含请求处理），最长 ~6 秒
  Future<bool> _waitForInitOnRuntime(JavascriptRuntime runtime) async {
    var initData = runtime.evaluate('globalThis.__lx_init_data__');
    if (!initData.isError && initData.stringResult != 'null' && initData.stringResult.isNotEmpty) {
      return true;
    }
    for (var i = 0; i < 40; i++) {
      await _processPendingRequests(runtime, 50);
      for (var j = 0; j < 20; j++) {
        runtime.executePendingJob();
      }
      await Future.delayed(Duration.zero);
      initData = runtime.evaluate('globalThis.__lx_init_data__');
      if (!initData.isError && initData.stringResult != 'null' && initData.stringResult.isNotEmpty) {
        return true;
      }
      final qLen = runtime.evaluate('globalThis.__lx_request_queue__.length');
      if (qLen.isError || qLen.stringResult == '0') break;
    }
    return false;
  }

  /// 在指定运行时上调用 request handler 获取 URL（轮询逻辑与主运行时一致）
  Future<String?> _fetchUrlOnRuntime(JavascriptRuntime runtime, dynamic music, String quality) async {
    final musicInfo = {
      'id': music.id,
      'name': music.name,
      'singer': music.singer,
      'album': music.album,
      'source': music.source,
      'songId': music.songId,
      'songmid': music.songmid,
      'strMediaMid': music.strMediaMid,
      'copyrightId': music.copyrightId,
      'hash': music.hash,
    };

    runtime.evaluate('globalThis.__lx_result__ = null');
    runtime.evaluate('globalThis.__lx_request_queue__ = []');

    final jsCode = '''
        (function() {
          var handler = globalThis.__lx_handlers__['request'];
          if (!handler) {
            return JSON.stringify({error: 'No handler registered'});
          }
          try {
            var called = false;
            var __lx_info__ = {
                musicInfo: ${jsonEncode(musicInfo)},
                type: ${jsonEncode(quality)}
              };
            var result = handler({
              source: ${jsonEncode(music.source ?? 'kw')},
              action: 'musicUrl',
              info: __lx_info__,
              params: __lx_info__
            }, function(err, data) {
              called = true;
              if (err) {
                globalThis.__lx_result__ = JSON.stringify({error: err.message || String(err)});
              } else {
                globalThis.__lx_result__ = JSON.stringify(data === undefined ? null : data);
              }
            });
            if (result && typeof result.then === 'function') {
              result.then(function(data) {
                globalThis.__lx_result__ = JSON.stringify(data === undefined ? null : data);
              }).catch(function(err) {
                globalThis.__lx_result__ = JSON.stringify({error: err.message || err.toString()});
              });
              return 'promise';
            }
            if (result && typeof result === 'object') {
              return JSON.stringify(result);
            }
            if (called) {
              return 'promise';
            }
            return JSON.stringify({error: 'Invalid result'});
          } catch (e) {
            return JSON.stringify({error: e.message || e.toString()});
          }
        })()
      ''';

    final result = runtime.evaluate(jsCode);
    if (result.isError) return null;

    final resultStr = result.stringResult;
    if (resultStr == 'promise' || resultStr == '"promise"') {
      for (var i = 0; i < 20; i++) {
        await _processPendingRequests(runtime, 50);
        for (var j = 0; j < 20; j++) {
          runtime.executePendingJob();
        }
        await Future.delayed(Duration.zero);
        final resultData = runtime.evaluate('globalThis.__lx_result__');
        if (!resultData.isError && resultData.stringResult != 'null' && resultData.stringResult.isNotEmpty) {
          return _extractUrlFromResult(resultData.stringResult);
        }
        final qLen = runtime.evaluate('globalThis.__lx_request_queue__.length');
        if (qLen.isError || qLen.stringResult == '0') break;
      }
      return null;
    }
    return _extractUrlFromResult(resultStr);
  }

  Future<String?> _getMusicUrlLocked(String apiId, dynamic music, String quality) async {
    try {
      final script = _scripts[apiId];
      if (script == null) {
        _log('脚本不存在: $apiId', type: DebugLogType.error);
        return null;
      }
      if (_jsRuntime == null || _currentScript?.id != apiId) {
        await _initJsRuntime(script);
      }
      // 激活指令刚下发、JS 仍在初始化时（冷启动恢复后立即播放），等待初始化完成
      if (!_scriptInitialized) {
        await _waitForScriptInit();
      }
      if (!_scriptInitialized) {
        _log('脚本未初始化', type: DebugLogType.error);
        return null;
      }

      final musicInfo = {
        'id': music.id,
        'name': music.name,
        'singer': music.singer,
        'album': music.album,
        'source': music.source,
        'songId': music.songId,
        'songmid': music.songmid,
        'strMediaMid': music.strMediaMid,
        'copyrightId': music.copyrightId,
        'hash': music.hash,
      };

      _jsRuntime!.evaluate('globalThis.__lx_result__ = null');
      _jsRuntime!.evaluate('globalThis.__lx_request_queue__ = []');

      final jsCode = '''
        (function() {
          var handler = globalThis.__lx_handlers__['request'];
          if (!handler) {
            return JSON.stringify({error: 'No handler registered'});
          }
          try {
            var called = false;
            var __lx_info__ = {
                musicInfo: ${jsonEncode(musicInfo)},
                type: ${jsonEncode(quality)}
              };
            var result = handler({
              source: ${jsonEncode(music.source ?? 'kw')},
              action: 'musicUrl',
              info: __lx_info__,
              // 新版脚本（如 qdy）从 params 取参，别名传递提升兼容
              params: __lx_info__
            }, function(err, data) {
              // 兼容 handler(request, callback) 回调风格
              called = true;
              if (err) {
                globalThis.__lx_result__ = JSON.stringify({error: err.message || String(err)});
              } else {
                globalThis.__lx_result__ = JSON.stringify(data === undefined ? null : data);
              }
            });
            if (result && typeof result.then === 'function') {
              result.then(function(data) {
                globalThis.__lx_result__ = JSON.stringify(data === undefined ? null : data);
              }).catch(function(err) {
                globalThis.__lx_result__ = JSON.stringify({error: err.message || err.toString()});
              });
              return 'promise';
            }
            if (result && typeof result === 'object') {
              return JSON.stringify(result);
            }
            // 回调风格：handler 内部异步调用 callback，等待结果
            if (called) {
              return 'promise';
            }
            return JSON.stringify({error: 'Invalid result'});
          } catch (e) {
            return JSON.stringify({error: e.message || e.toString()});
          }
        })()
      ''';

      final result = _jsRuntime!.evaluate(jsCode);
      if (result.isError) {
        _log('JS 执行错误: ${result.stringResult}', type: DebugLogType.error);
        return null;
      }

      final resultStr = result.stringResult;
      if (resultStr == '"promise"' || resultStr == 'promise') {
        var errored = false;
        // 循环处理：请求 + 微任务刷新 + 检查结果
        for (var i = 0; i < 30; i++) {
          // 一次性处理队列中所有 HTTP 请求（无内部延迟）
          await _processPendingRequests(null, 50);
          // 刷新 JS 微任务链（Promise/async/await 结果传递）
          for (var j = 0; j < 20; j++) {
            _jsRuntime!.executePendingJob();
          }
          // 让出事件循环，避免同步 FFI 连续阻塞 UI
          await Future.delayed(Duration.zero);
          final resultData = _jsRuntime!.evaluate('globalThis.__lx_result__');
          if (!resultData.isError && resultData.stringResult != 'null' && resultData.stringResult.isNotEmpty) {
            final url = _extractUrlFromResult(resultData.stringResult);
            if (url != null) {
              _log('从用户 API 获取 URL: $url');
              return url;
            }
            // 脚本已明确报错（转链失败等），立即退出 —— 快速失败让上层换源，
            // 继续轮询只会白等网络超时
            errored = true;
            break;
          }
          // 队列为空且结果未到：脚本没有更多异步操作，不再空转等待
          final qLen = _jsRuntime!.evaluate('globalThis.__lx_request_queue__.length');
          if (qLen.isError || qLen.stringResult == '0') break;
        }
        if (!errored) {
          final resultData = _jsRuntime!.evaluate('globalThis.__lx_result__');
          if (!resultData.isError && resultData.stringResult != 'null' && resultData.stringResult.isNotEmpty) {
            final url = _extractUrlFromResult(resultData.stringResult);
            if (url != null) {
              _log('从用户 API 获取 URL: $url');
              return url;
            }
          } else {
            _log('无结果数据 (stringResult=${resultData.stringResult})', type: DebugLogType.warn);
          }
        }
      } else {
        final url = _extractUrlFromResult(resultStr);
        if (url != null) {
          _log('从用户 API 获取 URL (同步): $url');
          return url;
        }
      }
      return null;
    } catch (e) {
      _log('获取播放地址错误: $e', type: DebugLogType.error);
      return null;
    }
  }

  /// 获取歌词 - 通过用户自定义源API
  Future<Map<String, String?>?> getLyric({
    required String apiId,
    required dynamic music,
  }) async {
    try {
      return await _withJsLock(() => _getLyricLocked(apiId, music), priority: false);
    } on TimeoutException {
      _log('获取歌词超时', type: DebugLogType.warn);
      return null;
    }
  }

  Future<Map<String, String?>?> _getLyricLocked(String apiId, dynamic music) async {
    try {
      final script = _scripts[apiId];
      if (script == null) {
        _log('脚本不存在: $apiId', type: DebugLogType.error);
        return null;
      }
      if (_jsRuntime == null || _currentScript?.id != apiId) {
        await _initJsRuntime(script);
      }
      if (!_scriptInitialized) {
        await _waitForScriptInit();
      }
      if (!_scriptInitialized) {
        _log('脚本未初始化', type: DebugLogType.error);
        return null;
      }

      final musicInfo = {
        'id': music.id,
        'name': music.name,
        'singer': music.singer,
        'album': music.album,
        'source': music.source,
        'songId': music.songId,
        'songmid': music.songmid,
        'strMediaMid': music.strMediaMid,
        'copyrightId': music.copyrightId,
        'hash': music.hash,
      };

      _jsRuntime!.evaluate('globalThis.__lx_result__ = null');
      _jsRuntime!.evaluate('globalThis.__lx_request_queue__ = []');

      final jsCode = '''
        (function() {
          var handler = globalThis.__lx_handlers__['request'];
          if (!handler) {
            return JSON.stringify({error: 'No handler registered'});
          }
          try {
            var __lx_info__ = {
                musicInfo: ${jsonEncode(musicInfo)}
              };
            var result = handler({
              source: ${jsonEncode(music.source ?? 'kw')},
              action: 'lyric',
              info: __lx_info__,
              params: __lx_info__
            });
            if (result && typeof result.then === 'function') {
              result.then(function(data) {
                globalThis.__lx_result__ = JSON.stringify(data === undefined ? null : data);
              }).catch(function(err) {
                globalThis.__lx_result__ = JSON.stringify({error: err.message || err.toString()});
              });
              return 'promise';
            }
            if (result && typeof result === 'object') {
              return JSON.stringify(result);
            }
            return JSON.stringify({error: 'Invalid result'});
          } catch (e) {
            return JSON.stringify({error: e.message || e.toString()});
          }
        })()
      ''';

      final result = _jsRuntime!.evaluate(jsCode);
      if (result.isError) {
        _log('JS 执行错误: ${result.stringResult}', type: DebugLogType.error);
        return null;
      }

      final resultStr = result.stringResult;
      if (resultStr == '"promise"' || resultStr == 'promise') {
        for (var i = 0; i < 30; i++) {
          await _processPendingRequests(null, 50);
          for (var j = 0; j < 20; j++) {
            _jsRuntime!.executePendingJob();
          }
          await Future.delayed(Duration.zero);
          final resultData = _jsRuntime!.evaluate('globalThis.__lx_result__');
          if (!resultData.isError && resultData.stringResult != 'null' && resultData.stringResult.isNotEmpty) {
            return _parseLyricResult(resultData.stringResult);
          }
          final qLen = _jsRuntime!.evaluate('globalThis.__lx_request_queue__.length');
          if (qLen.isError || qLen.stringResult == '0') break;
        }
      } else {
        return _parseLyricResult(resultStr);
      }
      return null;
    } catch (e) {
      _log('获取歌词错误: $e', type: DebugLogType.error);
      return null;
    }
  }

  /// 解析歌词结果
  Map<String, String?>? _parseLyricResult(String resultStr) {
    try {
      final decoded = jsonDecode(resultStr);
      if (decoded is Map) {
        if (decoded['error'] != null) {
          _log('脚本错误: ${decoded['error']}', type: DebugLogType.error);
          return null;
        }
        // 兼容多种返回格式
        String? lyric;
        String? tlyric;
        if (decoded['lyric'] is String) {
          lyric = decoded['lyric'];
        } else if (decoded['data'] is String) {
          lyric = decoded['data'];
        } else if (decoded['data'] is Map && decoded['data']['lyric'] is String) {
          lyric = decoded['data']['lyric'];
        }
        if (decoded['tlyric'] is String) {
          tlyric = decoded['tlyric'];
        } else if (decoded['data'] is Map && decoded['data']['tlyric'] is String) {
          tlyric = decoded['data']['tlyric'];
        }
        if (lyric != null && lyric.isNotEmpty) {
          _log('获取歌词成功');
          return {'lyric': lyric, 'tlyric': tlyric};
        }
      } else if (decoded is String && decoded.isNotEmpty) {
        // 直接返回歌词文本
        _log('获取歌词成功（纯文本）');
        return {'lyric': decoded, 'tlyric': null};
      }
    } catch (e) {
      _log('歌词解析错误: $e', type: DebugLogType.error);
    }
    return null;
  }

  /// 从脚本返回结果中提取播放 URL
  /// 兼容格式: 字符串URL, {url: '...'}, {data: '...'}, {data: {url: '...'}}
  String? _extractUrlFromResult(String resultStr) {
    lastScriptError = null;
    try {
      // 先处理裸字符串（可能带JSON引号）
      var raw = resultStr.trim();
      if (raw.startsWith('"') && raw.endsWith('"')) {
        raw = raw.substring(1, raw.length - 1);
      }
      if (raw.startsWith('http://') || raw.startsWith('https://')) {
        _log('解析到 URL(裸串): $raw');
        return raw;
      }

      final decoded = jsonDecode(resultStr);
      if (decoded is String) {
        final url = decoded.trim();
        if (url.startsWith('http://') || url.startsWith('https://')) {
          _log('解析到 URL: $url');
          return url;
        }
        return null;
      }
      if (decoded is Map) {
        if (decoded['error'] != null) {
          final errMsg = decoded['error'].toString();
          _log('脚本错误: $errMsg', type: DebugLogType.error);
          lastScriptError = errMsg;
          return null;
        }
        // LX 源返回格式: {code:0, msg:'', data:'url', source:'kw', time:123}
        final candidates = [decoded['url'], decoded['data'], decoded['data']?['url']];
        for (final c in candidates) {
          if (c is String && (c.startsWith('http://') || c.startsWith('https://'))) {
            _log('解析到 URL: $c');
            return c;
          }
          if (c is Map) {
            final nestedUrl = c['url'];
            if (nestedUrl is String && (nestedUrl.startsWith('http://') || nestedUrl.startsWith('https://'))) {
              _log('解析到嵌套 URL: $nestedUrl');
              return nestedUrl;
            }
          }
        }
        _log('结果中未找到有效 URL: $resultStr', type: DebugLogType.warn);
        return null;
      }
    } catch (e) {
      _log('结果解析错误: $e', type: DebugLogType.error);
    }
    return null;
  }

  // ===================== HTTP Request =====================

  /// 对齐 lx-music-mobile request.js 的请求语义：
  /// - 默认 User-Agent（Chrome）与 Accept，脚本显式传入的头优先
  /// - form → application/x-www-form-urlencoded
  /// - formData → multipart/form-data
  /// - body 为对象且未指定 Content-Type → JSON
  /// - 超时默认 13s，脚本传入时上限 60s
  /// - binary → body 返回字节数组
  /// - 网络错误直接抛出（由上层 reject 脚本回调）
  Future<Map<String, dynamic>> _makeHttpRequest(String url, Map<String, dynamic> options) async {
    try {
      final method = (options['method']?.toString() ?? 'GET').toUpperCase();
      final scriptHeaders = <String, String>{};
      (options['headers'] ?? const {}).forEach((k, v) {
        scriptHeaders[k.toString()] = v.toString();
      });

      if (url.startsWith('/')) {
        url = 'https://flower.tempmusics.tk/v1' + url;
      }

      _log('HTTP $method $url');

      // 默认头（对齐原版）：脚本传入的头优先
      final headers = <String, String>{
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.100 Safari/537.36',
        'Accept': 'application/json',
        ...scriptHeaders,
      };

      // 超时：默认 13s（对齐原版），脚本传入时上限 60s（对齐原版 preload min(timeout, 60_000)）
      var timeoutMs = 13000;
      final scriptTimeout = options['timeout'];
      if (scriptTimeout is num && scriptTimeout > 0) {
        timeoutMs = scriptTimeout > 60000 ? 60000 : scriptTimeout.toInt();
      }

      final form = options['form'];
      final formData = options['formData'];
      final body = options['body'];
      final binary = options['binary'] == true;

      http.StreamedResponse response;
      if (formData is Map && formData.isNotEmpty) {
        // multipart/form-data
        final request = http.MultipartRequest(method, Uri.parse(url));
        request.headers.addAll(headers);
        formData.forEach((k, v) {
          if (v is http.MultipartFile) {
            request.files.add(v);
          } else {
            request.fields[k.toString()] = v?.toString() ?? '';
          }
        });
        response = await _sharedHttpClient.send(request).timeout(Duration(milliseconds: timeoutMs));
      } else {
        final request = http.Request(method, Uri.parse(url));
        if (form is Map && form.isNotEmpty) {
          // application/x-www-form-urlencoded（对齐原版：逐字段 encodeURIComponent）
          headers.putIfAbsent('Content-Type', () => 'application/x-www-form-urlencoded');
          request.body = form.entries
              .map((e) => '${Uri.encodeComponent(e.key.toString())}=${Uri.encodeComponent(e.value?.toString() ?? '')}')
              .join('&');
        } else if (body != null) {
          if (body is String) {
            request.body = body;
          } else if (body is List<int>) {
            request.bodyBytes = body;
          } else {
            headers.putIfAbsent('Content-Type', () => 'application/json');
            request.body = jsonEncode(body);
          }
        }
        request.headers.addAll(headers);
        response = await _sharedHttpClient.send(request).timeout(Duration(milliseconds: timeoutMs));
      }

      final statusCode = response.statusCode;
      // 非 2xx 且 content-type 明确为 JSON 时也按文本读，统一走 bytes
      final bytes = await response.stream.toBytes();
      dynamic parsedBody;
      if (binary) {
        parsedBody = bytes.toList();
      } else {
        final responseBody = utf8.decode(bytes, allowMalformed: true);
        try {
          parsedBody = jsonDecode(responseBody);
        } catch (e) {
          parsedBody = responseBody;
        }
      }

      return {
        'statusCode': statusCode,
        'statusMessage': response.reasonPhrase ?? (statusCode == 200 ? 'OK' : 'Error'),
        'headers': response.headers,
        'body': parsedBody,
        'ok': statusCode >= 200 && statusCode < 300,
        'url': url,
      };
    } catch (e) {
      // 对齐原版：网络层错误抛给脚本回调（callback(err) / promise reject）
      rethrow;
    } finally {}
  }

  // ===================== Lifecycle =====================

  Future<void> deactivateScript() async {
    _jsRuntime?.dispose();
    _jsRuntime = null;
    _currentScript = null;
    _scriptInitialized = false;
    _sources = {};
    _updateUrl = null;
    lastActivationError = null;
    lastScriptError = null;
    await StorageService().setUserApiActiveScriptId(null);
    _stateController.add(UserApiServiceState.idle);
    _eventController.add(UserApiEvent.scriptDeactivated());
  }

  Future<void> removeScript(String scriptId) async {
    if (_currentScript?.id == scriptId) {
      await deactivateScript();
    }
    _scripts.remove(scriptId);
    await _saveScriptsToStorage();
    _eventController.add(UserApiEvent.scriptRemoved(scriptId));
  }

  UserApiScript? getScript(String scriptId) {
    return _scripts[scriptId];
  }

  String? getPersistedActiveScriptId() {
    return StorageService().getUserApiActiveScriptId();
  }

  List<UserApiScript> getAllScripts() {
    return _scripts.values.toList();
  }

  void dispose() {
    _jsRuntime?.dispose();
    _stateController.close();
    _eventController.close();
  }
}

enum UserApiServiceState {
  idle,
  loading,
  loaded,
  active,
  error,
}

class UserApiEvent {
  final UserApiEventType type;
  final dynamic data;
  UserApiEvent(this.type, [this.data]);

  static UserApiEvent scriptImported(UserApiScript script) =>
      UserApiEvent(UserApiEventType.scriptImported, script);
  static UserApiEvent scriptActivated(UserApiScript script) =>
      UserApiEvent(UserApiEventType.scriptActivated, script);
  static UserApiEvent scriptDeactivated() =>
      UserApiEvent(UserApiEventType.scriptDeactivated);
  static UserApiEvent scriptError(UserApiScript? script, String? message) =>
      UserApiEvent(UserApiEventType.scriptError, {'script': script, 'message': message});
  static UserApiEvent scriptRemoved(String scriptId) =>
      UserApiEvent(UserApiEventType.scriptRemoved, scriptId);
  static UserApiEvent requestSent(dynamic data) =>
      UserApiEvent(UserApiEventType.requestSent, data);
}

enum UserApiEventType {
  scriptImported,
  scriptActivated,
  scriptDeactivated,
  scriptRemoved,
  requestSent,
  scriptError,
}

class UserApiScript {
  final String id;
  final String name;
  final String description;
  final String author;
  final String version;
  final String homepage;
  final String content;
  final DateTime importedAt;
  final Map<String, UserApiSource> sources;

  UserApiScript({
    required this.id,
    required this.name,
    required this.description,
    required this.author,
    required this.version,
    required this.homepage,
    required this.content,
    required this.importedAt,
    this.sources = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'author': author,
      'version': version,
      'homepage': homepage,
      'importedAt': importedAt.toIso8601String(),
    };
  }

  factory UserApiScript.fromJson(Map<String, dynamic> json, {String? content}) {
    return UserApiScript(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      author: json['author'] ?? '',
      version: json['version'] ?? '1.0.0',
      homepage: json['homepage'] ?? '',
      content: content ?? '',
      importedAt: DateTime.parse(json['importedAt']),
    );
  }
}

class UserApiSource {
  final String type;
  final List<String> actions;
  final List<String> qualitys;

  UserApiSource({
    required this.type,
    required this.actions,
    required this.qualitys,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'actions': actions,
      'qualitys': qualitys,
    };
  }

  factory UserApiSource.fromJson(Map<String, dynamic> json) {
    return UserApiSource(
      type: json['type'] ?? 'music',
      actions: List<String>.from(json['actions'] ?? []),
      qualitys: List<String>.from(json['qualitys'] ?? []),
    );
  }
}

enum DebugLogType { info, warn, error }

class DebugLog {
  final DateTime time;
  final DebugLogType type;
  final String message;

  DebugLog({
    required this.time,
    required this.type,
    required this.message,
  });

  @override
  String toString() {
    final prefix = switch (type) {
      DebugLogType.info => 'INFO',
      DebugLogType.warn => 'WARN',
      DebugLogType.error => 'ERR ',
    };
    final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    return '[$timeStr][$prefix] $message';
  }
}