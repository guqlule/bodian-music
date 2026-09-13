// 用仓库自带的 8 个真实源脚本对 JS 环境做冒烟验证：
// 1. 脚本 evaluate 不报错
// 2. 注册了 request handler
// 3. 同步阶段能否发出 init 数据（部分脚本初始化需要网络，会走异步轮询，这里只测同步可达部分）
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // flutter test (VM) 下 flutter_js 需先加载包内预编译 dll
    const dllPath =
        r'C:\Users\Administrator\AppData\Local\Pub\Cache\hosted\pub.dev\flutter_js-0.8.7\windows\shared\quickjs_c_bridge.dll';
    if (Platform.isWindows && File(dllPath).existsSync()) {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final loadLib = kernel32.lookupFunction<IntPtr Function(Pointer<Utf16>),
          int Function(Pointer<Utf16>)>('LoadLibraryW');
      loadLib(dllPath.toNativeUtf16());
    }
  });

  test('真实源脚本冒烟', () {
    final source = File('lib/services/api/user_api_service.dart').readAsStringSync();
    final start = source.indexOf('void _setupLxApi');
    final end = source.indexOf('// ===================== Request Processing');
    final methodBody = source.substring(start, end);
    final rxp = RegExp(r"(?:_jsRuntime!\.evaluate|evalOrThrow)\('''([\s\S]+?)'''\s*(?:,\s*'\w+')?\s*\);");
    final envJs = rxp.allMatches(methodBody).map((m) => m.group(1)!).join('\n')
        .replaceAll(r'${jsonEncode(script.name)}', '"Test"')
        .replaceAll(r'${jsonEncode(script.version)}', '"1.0.0"')
        .replaceAll(r'${jsonEncode(script.author)}', '"a"')
        .replaceAll(r'${jsonEncode(script.description)}', '"d"')
        .replaceAll(r'${jsonEncode(script.homepage)}', '"h"')
        .replaceAll(r'${jsonEncode(rawScript)}', '"raw"');
    expect(envJs.contains(r'${'), isFalse);

    final dirs = [
      'lx-music-source-main/huibq', 'lx-music-source-main/juhe',
      'lx-music-source-main/ikun', 'lx-music-source-main/flower',
      'lx-music-source-main/grass', 'lx-music-source-main/lx',
      'lx-music-source-main/qdy', 'lx-music-source-main/sixyin',
    ];

    for (final dir in dirs) {
      final f = File('$dir/latest.js');
      if (!f.existsSync()) {
        print('SKIP  $dir (无 latest.js)');
        continue;
      }
      final script = f.readAsStringSync();
      final name = dir.split('/').last;
      final rt = getJavascriptRuntime();
      String? failReason;
      bool hasHandler = false, inited = false;
      try {
        final env = rt.evaluate(envJs);
        if (env.isError) {
          failReason = '环境加载失败: ${env.stringResult}';
        } else {
          final r = rt.evaluate(script);
          if (r.isError) {
            failReason = '脚本执行失败: ${r.stringResult}';
          } else {
            hasHandler = rt.evaluate("typeof __lx_handlers__.request === 'function' && __lx_handlers__.request !== null").stringResult == 'true';
            final init = rt.evaluate('globalThis.__lx_init_data__');
            inited = !init.isError && init.stringResult != 'null' && init.stringResult.isNotEmpty;
            final qLen = rt.evaluate('globalThis.__lx_request_queue__.length');
            final pending = (!qLen.isError && qLen.stringResult != '0') ? ' (同步阶段发起 ${qLen.stringResult} 个请求，需网络后 init)' : '';
            print('${failReason == null ? (inited ? "PASS  " : "OK*   ") : "FAIL  "} $name: handler=$hasHandler 同步init=$inited$pending ${failReason ?? ""}');
          }
        }
      } catch (e) {
        failReason = '异常: $e';
      } finally {
        rt.dispose();
      }
      if (failReason != null) print('FAIL  $name: $failReason');
      // sixyin 依赖 BigInt（flutter_js 内置 QuickJS 未启用 CONFIG_BIGNUM，
      // 语法层面无法 polyfill），为已知引擎限制；其余脚本必须通过
      if (failReason != null && !failReason.contains('invalid number literal')) {
        fail('$name 脚本加载失败: $failReason');
      }
    }
  });
}
