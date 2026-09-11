// 验证 user_api_service 注入的 JS 环境语法与关键 API 行为
// （对齐 lx-music-mobile user-api-preload.js 的兼容面）
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late JavascriptRuntime rt;

  setUpAll(() {
    // flutter test (VM) 下 flutter_js 通过 DynamicLibrary.open('quickjs_c_bridge.dll')
    // 按标准搜索顺序加载；先用 LoadLibraryW 把包内预编译 dll 的绝对路径加载进进程
    const dllPath =
        r'C:\Users\Administrator\AppData\Local\Pub\Cache\hosted\pub.dev\flutter_js-0.8.7\windows\shared\quickjs_c_bridge.dll';
    if (Platform.isWindows && File(dllPath).existsSync()) {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final loadLib = kernel32.lookupFunction<IntPtr Function(Pointer<Utf16>),
          int Function(Pointer<Utf16>)>('LoadLibraryW');
      final loaded = loadLib(dllPath.toNativeUtf16());
      expect(loaded, isNot(0), reason: '预编译 quickjs_c_bridge.dll 加载失败');
    }
    rt = getJavascriptRuntime();
  });

  tearDownAll(() {
    rt.dispose();
  });

  void check(String label, String code, String want) {
    final r = rt.evaluate(code);
    expect(r.isError, isFalse, reason: '$label 执行出错: ${r.stringResult}');
    expect(r.stringResult, want, reason: label);
  }

  test('JS 环境加载 + lx API 行为', () {
    final source = File('lib/services/api/user_api_service.dart').readAsStringSync();
    final start = source.indexOf('void _setupLxApi');
    final end = source.indexOf('// ===================== Request Processing');
    final methodBody = source.substring(start, end);

    final rxp = RegExp(r"(?:_jsRuntime!\.evaluate|evalOrThrow|runtime\.evaluate)\('''([\s\S]+?)'''\s*(?:,\s*'\w+')?\s*\);");
    final blocks = rxp.allMatches(methodBody).map((m) => m.group(1)!).toList();
    expect(blocks.length, greaterThanOrEqualTo(3), reason: '应提取到 polyfill/md5+utils/lx 三段 JS');

    var joined = blocks.join('\n');
    // 还原 Dart 插值（rawScript 是方法局部变量，插值形式与其它字段不同）
    joined = joined.replaceAll(r'${jsonEncode(rawScript)}', '"raw"');
    String sentinel(String key) => '\${jsonEncode(script.$key)}';
    joined = joined
        .replaceAll(sentinel('name'), '"Test"')
        .replaceAll(sentinel('version'), '"1.0.0"')
        .replaceAll(sentinel('author'), '"a"')
        .replaceAll(sentinel('description'), '"d"')
        .replaceAll(sentinel('homepage'), '"h"')
        .replaceAll(sentinel('rawScript'), '"raw"');
    // 确认没有残留未替换的插值
    expect(joined.contains(r'${'), isFalse, reason: 'JS 中残留未替换的 Dart 插值');

    final result = rt.evaluate(joined);
    expect(result.isError, isFalse, reason: 'JS 环境加载失败: ${result.stringResult}');

    // 诊断探针：确认各段定义都生效
    final probes = ['typeof clearTimeout', 'typeof __lx_wrap_headers__',
      'typeof __lx_utils__', 'typeof lx', 'typeof globalThis.lx'];
    for (final p in probes) {
      final pr = rt.evaluate(p);
      print('PROBE $p => ${pr.isError ? "ERR ${pr.stringResult}" : pr.stringResult}');
    }
  });

  test('polyfill 可用', () {
    check('clearTimeout', 'typeof clearTimeout', 'function');
    check('setInterval', 'typeof setInterval', 'function');
    check('clearInterval', 'typeof clearInterval', 'function');
    check('btoa', 'btoa("hi")', 'aGk=');
    check('atob', 'atob("aGk=")', 'hi');
    check('console.info', 'typeof console.info', 'function');
    check('console.debug', 'typeof console.debug', 'function');
    check('wrap_headers', 'typeof __lx_wrap_headers__', 'function');
  });

  test('headers 大小写兼容包装', () {
    check('小写查大写', '__lx_wrap_headers__({"content-type":"x"})["Content-Type"]', 'x');
    check('大写查小写', '__lx_wrap_headers__({"Content-Type":"y"})["content-type"]', 'y');
    check('原样命中', '__lx_wrap_headers__({"Content-Type":"z"})["Content-Type"]', 'z');
  });

  test('utils.crypto / utils.buffer / Buffer', () {
    check('md5', 'lx.utils.crypto.md5("abc")', '900150983cd24fb0d6963f7d28e17f72');
    check('randomBytes 长度', 'lx.utils.crypto.randomBytes(4).length', '4');
    check('buffer.from hex', 'lx.utils.buffer.from("aabb","hex")[0]', '170');
    check('buffer.from b64', 'lx.utils.buffer.from("aGk=","base64")[0]', '104');
    check('buffer.from utf8', 'lx.utils.buffer.from("hi")[0]', '104');
    check('bufToString hex', 'lx.utils.buffer.bufToString([170,187],"hex")', 'aabb');
    check('Buffer.from', 'Buffer.from("aabb","hex")[1]', '187');
  });

  test('lx 对象对齐原版', () {
    check('version', 'lx.version', '2.0.0');
    check('env', 'lx.env', 'mobile');
    check('EVENT_NAMES.request', 'lx.EVENT_NAMES.request', 'request');
    check('currentScriptInfo.name', 'lx.currentScriptInfo.name', 'Test');
    check('currentScriptInfo.author', 'lx.currentScriptInfo.author', 'a');
    check('on 返回 Promise', 'lx.on("request", function(){}) instanceof Promise', 'true');
    check('on 非法事件 reject', 'lx.on("xxx", function(){}) instanceof Promise', 'true');
    check('send 返回 Promise', 'lx.send("inited", {sources:{kw:{type:"music",actions:["musicUrl"],qualitys:["320k"]}}}) instanceof Promise', 'true');
    check('init 数据已存', 'typeof __lx_init_data__', 'string');
    check('inited 幂等保护', 'lx.send("inited", {}) instanceof Promise', 'true');
    check('updateAlert 存 Promise', 'lx.send("updateAlert", {log:"v2"}) instanceof Promise', 'true');
    check('updateAlert 已存', 'JSON.parse(__lx_update_alert__).log', 'v2');
    check('request 回调风格', 'typeof lx.request("http://x", {}, function(){})', 'function');
    check('request Promise 风格', 'lx.request("http://x") instanceof Promise', 'true');
  });

  test('init 数据内容正确', () {
    final r = rt.evaluate('JSON.parse(__lx_init_data__).sources.kw.qualitys[0]');
    expect(r.stringResult, '320k');
  });

  test('注册 handler 并触发请求队列', () {
    // 清理前面的测试残留请求，避免队列计数污染
    rt.evaluate('globalThis.__lx_request_queue__ = []; globalThis.__lx_cb_args__ = null;');
    rt.evaluate('''
      lx.on('request', function(req) { __lx_handler_called__ = true; });
      lx.request('http://example.com', {}, function(err, resp, body) {
        __lx_cb_args__ = { err: err ? String(err) : null, ok: resp ? resp.ok : null, body: body, ct: resp && resp.headers ? resp.headers['Content-Type'] : null };
      });
      var q = globalThis.__lx_request_queue__;
      __lx_test_queue_len__ = q.length;
    ''');
    check('请求已入队', 'String(__lx_test_queue_len__)', '1');
    // 模拟 Dart 侧交付响应
    rt.evaluate('''
      (function() {
        var item = __lx_request_queue__.shift();
        item.resolve({ statusCode: 200, headers: __lx_wrap_headers__({'content-type':'application/json'}), body: {ok:1}, ok: true, url: 'http://example.com' });
      })()
    ''');
    // 微任务刷新
    for (var i = 0; i < 10; i++) {
      rt.executePendingJob();
    }
    check('回调 err 为空', 'String(__lx_cb_args__.err)', 'null');
    check('回调 ok 字段', 'String(__lx_cb_args__.ok)', 'true');
    check('回调 body 透传', 'String(__lx_cb_args__.body.ok)', '1');
    check('headers 大小写兼容', '__lx_cb_args__.ct', 'application/json');
  });

  test('脚本样例环境冒烟（setTimeout/setInterval 语法可用）', () {
    final r = rt.evaluate('''
      (function() {
        var calls = 0;
        setTimeout(function(){ calls++; }, 0);
        var iv = setInterval(function(){ calls++; }, 0);
        clearInterval(iv);
        return calls;
      })()
    ''');
    expect(r.isError, isFalse, reason: 'timer 语法执行失败: ${r.stringResult}');
  });
}
