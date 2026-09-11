// 模拟 App _getMusicUrlLocked 的轮询循环，验证 qLen 提前退出竞态
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    const dllPath =
        r'C:\Users\Administrator\AppData\Local\Pub\Cache\hosted\pub.dev\flutter_js-0.8.7\windows\shared\quickjs_c_bridge.dll';
    if (Platform.isWindows && File(dllPath).existsSync()) {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final loadLib = kernel32.lookupFunction<IntPtr Function(Pointer<Utf16>),
          int Function(Pointer<Utf16>)>('LoadLibraryW');
      loadLib(dllPath.toNativeUtf16());
    }
  });

  test('App 循环复现：qLen 提前退出竞态', () async {
    final source = File('lib/services/api/user_api_service.dart').readAsStringSync();
    final start = source.indexOf('void _setupLxApi');
    final end = source.indexOf('// ===================== Request Processing');
    final methodBody = source.substring(start, end);
    final rxp = RegExp(r"(?:_jsRuntime!\.evaluate|evalOrThrow|runtime\.evaluate)\('''([\s\S]+?)'''\s*(?:,\s*'\w+')?\s*\);");
    var envJs = rxp.allMatches(methodBody).map((m) => m.group(1)!).join('\n')
        .replaceAll(r'${jsonEncode(script.name)}', '"Test"')
        .replaceAll(r'${jsonEncode(script.version)}', '"1.0.0"')
        .replaceAll(r'${jsonEncode(script.author)}', '"a"')
        .replaceAll(r'${jsonEncode(script.description)}', '"d"')
        .replaceAll(r'${jsonEncode(script.homepage)}', '"h"')
        .replaceAll(r'${jsonEncode(rawScript)}', '"raw"');

    final rt = getJavascriptRuntime();
    rt.evaluate(envJs);
    rt.evaluate(File('lx-music-source-main/qdy/latest.js').readAsStringSync());

    // ===== 完全复刻 App 循环：process(快照循环) → pump → check → qLen break =====
    rt.evaluate('globalThis.__lx_result__ = null');
    rt.evaluate('globalThis.__lx_request_queue__ = []');
    final call = rt.evaluate('''
        (function() {
          var handler = globalThis.__lx_handlers__['request'];
          var __lx_info__ = {
              musicInfo: { id: 'tx_0034i9N23YKMOB', name: '测试歌', singer: '测试', album: '', source: 'tx', songId: '711782289', songmid: '0034i9N23YKMOB' },
              type: '128k'
            };
          var result = handler({ source: 'tx', action: 'musicUrl', info: __lx_info__, params: __lx_info__ });
          if (result && typeof result.then === 'function') {
            result.then(function(data) { globalThis.__lx_result__ = JSON.stringify(data); })
                  .catch(function(err) { globalThis.__lx_result__ = JSON.stringify({error: err.message || String(err)}); });
            return 'promise';
          }
          return typeof result;
        })()
      ''');
    print('call: ${call.stringResult}');

    var exitReason = 'max';
    for (var i = 0; i < 30; i++) {
      // _processPendingRequests 快照循环（App 新实现）
      // 第一轮：evaluate 后同步段应已入队（qLen=3）？检查！
      final qLenBefore = rt.evaluate('globalThis.__lx_request_queue__.length').stringResult;
      if (i == 0) print('i=0 进入循环时 qLen=$qLenBefore');

      // pump 微任务（App 是 process 后 pump——第一轮 process 时微任务还没跑！）
      if (i == 0) {
        // 模拟 App：第一轮 process 时 handler 的 async 体还没执行（0 微任务）
        print('i=0 process 时队列: ${rt.evaluate('globalThis.__lx_request_queue__.length').stringResult}');
      }
      for (var j = 0; j < 20; j++) {
        rt.executePendingJob();
      }
      final resultData = rt.evaluate('globalThis.__lx_result__');
      if (resultData.stringResult != 'null' && resultData.stringResult.isNotEmpty) {
        print('i=$i RESULT: ${resultData.stringResult}');
        break;
      }
      final qLen = rt.evaluate('globalThis.__lx_request_queue__.length').stringResult;
      print('i=$i qLen=$qLen');
      if (qLen == '0') { exitReason = 'qLen==0 at i=$i'; break; }
    }
    print('exit: $exitReason');
    rt.dispose();
  });
}
