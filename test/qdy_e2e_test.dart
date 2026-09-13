// 端到端：真实 UserApiService + qdy 脚本 + 并行请求处理
// 验证：handler 调用 → 3 请求并行处理 → 失败 reject → allSettled 汇总 error → 上层快速失败
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lx_music_flutter/services/api/user_api_service.dart';
import 'package:lx_music_flutter/core/storage/storage_service.dart';
import 'package:lx_music_flutter/core/storage/hive_adapters.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    const dllPath =
        r'C:\Users\Administrator\AppData\Local\Pub\Cache\hosted\pub.dev\flutter_js-0.8.7\windows\shared\quickjs_c_bridge.dll';
    if (Platform.isWindows && File(dllPath).existsSync()) {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final loadLib = kernel32.lookupFunction<IntPtr Function(Pointer<Utf16>),
          int Function(Pointer<Utf16>)>('LoadLibraryW');
      loadLib(dllPath.toNativeUtf16());
    }
    HiveAdapters.registerAdapters();
    await StorageService().init(hivePath: Directory.systemTemp.createTempSync('qdy_e2e').path);
  });

  test('qdy 端到端：脚本激活 + 取URL（并行请求处理）', () async {
    final svc = UserApiService();
    await svc.init();
    final scriptContent = File('lx-music-source-main/qdy/latest.js').readAsStringSync();
    final script = await svc.importScript(scriptContent);

    // 激活（初始化为同步路径，qdy 在 evaluate 时即 send inited）
    await svc.activateScript(script.id);
    // 等待异步 _initScriptRuntime 完成
    for (var i = 0; i < 50 && !svc.isActive; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    print('isActive=${svc.isActive} sources=${svc.sources.keys.toList()}');
    expect(svc.isActive, isTrue, reason: 'qdy 应同步初始化成功');

    // 取 URL（tx 源会真实发 3 个 HTTP——测试网络环境下预期失败并汇总报错，但绝不能"无结果静默"）
    final music = _FakeMusic();
    final url = await svc.getMusicUrl(apiId: script.id, music: music, quality: '128k');
    print('url=$url lastError=${svc.lastScriptError}');
    print('debugLog tail:');
    final logs = svc.debugLogs.map((l) => l.toString()).toList();
    for (final l in logs.skip(logs.length > 12 ? logs.length - 12 : 0)) {
      print('  $l');
    }
    // 关键断言：请求被真实处理过（有"并行处理"或"请求:"日志）
    final processed = logs.any((l) => l.contains('并行处理') || l.contains('请求: '));
    expect(processed, isTrue, reason: '队列请求必须被处理（此前"无结果 null"即此 bug）');
    svc.deactivateScript();
  }, timeout: const Timeout(Duration(seconds: 60)));
}

class _FakeMusic {
  String get id => 'tx_0034i9N23YKMOB';
  String get name => '测试歌';
  String get singer => '测试';
  String get album => '';
  String? get source => 'tx';
  String get songId => '711782289';
  String get songmid => '0034i9N23YKMOB';
  String get strMediaMid => '0034i9N23YKMOB';
  String get copyrightId => '';
  String? get hash => null;
}
