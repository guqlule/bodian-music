import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 酷狗 KRC（逐字歌词）解密
///
/// KRC 不是 AES，而是：
///   base64 解码 → 跳过前 4 字节 → 与 16 字节固定密钥 XOR → zlib 解压
///
/// 密钥固定（与 accesskey 无关）：
///   0x40 0x47 0x61 0x77 0x5e 0x32 0x74 0x47 0x51 0x36 0x31 0x2d 0xce 0xd2 0x6e 0x69
class KrcDecoder {
  static const List<int> _xorKey = [
    0x40, 0x47, 0x61, 0x77, 0x5e, 0x32, 0x74, 0x47, //
    0x51, 0x36, 0x31, 0x2d, 0xce, 0xd2, 0x6e, 0x69,
  ];

  /// 解密 KRC content（base64 字符串）为明文歌词。
  /// 失败返回 null，调用方应降级到 LRC。
  static String? decode(String base64Content) {
    try {
      Uint8List bytes;
      try {
        bytes = base64Decode(_padBase64(base64Content));
      } catch (_) {
        // 已经是明文（服务端未加密）
        return base64Content;
      }
      if (bytes.length <= 4) return null;

      // 跳过 4 字节头
      final payload = Uint8List.sublistView(bytes, 4);
      // XOR
      final xored = Uint8List(payload.length);
      for (int i = 0; i < payload.length; i++) {
        xored[i] = payload[i] ^ _xorKey[i % 16];
      }

      // zlib 包装 = 2 字节头 + raw deflate + adler32 尾。
      // Dart 的 ZLibCodec 处理完整 zlib 流；这里直接用它。
      return utf8.decode(ZLibCodec().decode(xored));
    } catch (_) {
      return null;
    }
  }

  /// 补齐 base64 padding
  static String _padBase64(String s) {
    final t = s.trim();
    final pad = (4 - t.length % 4) % 4;
    return pad == 0 ? t : t + ('=' * pad);
  }
}
