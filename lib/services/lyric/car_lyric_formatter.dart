/// 车机歌词 LRC 预处理。
///
/// 参考 md3Music（vivo 原子随身听 / Jovi InCar ucar 协议）的实现：
/// 车机侧会用 LRC 解析器按时间轴滚动显示整首歌词，但它的解析器很脆弱，
/// 直接喂原始歌词会失败或显示异常，必须做两步清洗：
///
/// 1. 剥掉 ELRC 逐字标签 `<mm:ss.xxx>`——车机解析器会把它当正文渲染出来
/// 2. 同一时间戳只保留第一行——翻译行通常与原文同时间戳，
///    重复时间戳会让部分解析器错乱
class CarLyricFormatter {
  /// ELRC 逐字时间标签，如 `<00:12.345>`、`<1:02>`、`<00:05.1>`
  static final RegExp _wordTag = RegExp(r'<\d{1,3}:\d{1,2}(?:\.\d{1,3})?>');

  /// 行首时间标签，如 `[00:12.34]`、`[00:12]`
  static final RegExp _lineTag = RegExp(r'^\s*\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

  /// 整首歌词 → 车机可用 LRC
  static String format(String rawLrc) {
    if (rawLrc.trim().isEmpty) return '';

    final lines = rawLrc.split(RegExp(r'\r?\n'));
    final out = <String>[];
    // 已出现的时间戳（毫秒），用于去重翻译行
    final seenMs = <int>{};

    for (final raw in lines) {
      var line = raw.replaceAll(_wordTag, '').trimRight();
      if (line.trim().isEmpty) continue;

      final m = _lineTag.firstMatch(line);
      if (m == null) {
        // 无时间标签的行（如纯翻译、纯文本行）原样保留
        out.add(line);
        continue;
      }

      // 归一化到毫秒：[00:12.5] 与 [00:12.050] 视为同一时间点
      final min = int.tryParse(m.group(1) ?? '0') ?? 0;
      final sec = int.tryParse(m.group(2) ?? '0') ?? 0;
      final fracRaw = m.group(3) ?? '0';
      final frac = int.tryParse(fracRaw.padRight(3, '0').substring(0, 3)) ?? 0;
      final ms = min * 60 * 1000 + sec * 1000 + frac;

      if (!seenMs.add(ms)) continue; // 同时间戳重复 → 丢弃（通常是译文）
      out.add(line);
    }

    return out.join('\n');
  }
}
