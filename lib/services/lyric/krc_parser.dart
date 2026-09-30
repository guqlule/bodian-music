import 'lyric_parser.dart' show LyricLine, LyricWord;

/// 酷狗 KRC 逐字歌词解析
///
/// 格式：
/// ```
/// [id:$00000000]                              ← 元数据行，跳过
/// [12500,4200]<0,300,0>戴<300,400,0>佩<700,500,0>妮  ← 逐字行
/// ```
///
/// 行首 `[start_ms,duration_ms]` 是毫秒；
/// 词级 `<offset_ms,duration_ms,prop>` 的 offset **相对于行首**。
class KrcParser {
  /// 行级时间戳：`[start_ms,duration_ms]`
  static final RegExp _lineTs = RegExp(r'^\[(\d+),(\d+)\](.*)$');

  /// 词级时间标签：`<offset,duration>` 或 `<offset,duration,prop>`（prop 恒为 0，忽略）
  static final RegExp _wordTag = RegExp(r'<(-?\d+),(-?\d+)(?:,-?\d+)?>');

  /// 元数据行（KRC/LRC 共用）
  static final RegExp _metaHeader = RegExp(r'^\[[A-Za-z][A-Za-z0-9]*:');
  static const List<String> _metaPrefixes = [
    '[id:', '[ar:', '[ti:', '[by:', '[hash:', '[al:', '[sign:',
    '[qq:', '[total:', '[offset:', '[language:', '[kana:',
  ];

  static bool isKrc(String text) {
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || _isMeta(line)) continue;
      return RegExp(r'^\[\d+,\d+\]').hasMatch(line);
    }
    return false;
  }

  static bool _isMeta(String line) {
    if (_metaHeader.hasMatch(line)) return true;
    for (final p in _metaPrefixes) {
      if (line.startsWith(p)) return true;
    }
    return false;
  }

  static List<LyricLine> parse(String krcText) {
    try {
      final lines = <LyricLine>[];
      if (krcText.isEmpty) return lines;

      for (final raw in krcText.split('\n')) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        if (_isMeta(line)) continue;

        final m = _lineTs.firstMatch(line);
        if (m == null) {
          // 有些 KRC 词标签被换行拆开：把剥掉标签的文本接到上一行
          if (_wordTag.hasMatch(line) && lines.isNotEmpty) {
            final stripped = line.replaceAll(_wordTag, '').trim();
            if (stripped.isNotEmpty) {
              final last = lines.removeLast();
              lines.add(LyricLine(
                time: last.time,
                text: '${last.text}$stripped',
                translation: last.translation,
                words: last.words,
              ));
            }
          }
          continue;
        }

        final lineStartMs = int.tryParse(m.group(1)!) ?? 0;
        final rest = m.group(3) ?? '';
        final words = _parseWords(rest, lineStartMs);

        if (words.isEmpty) {
          // 有行时间戳但无词标签 → 纯文本行
          final plain = rest.replaceAll(_wordTag, '').trim();
          lines.add(LyricLine(
            time: Duration(milliseconds: lineStartMs),
            // 用 NBSP 占位，保证该行占布局高度（对应参考实现的 \u00A0）
            text: plain.isEmpty ? '\u00A0' : plain,
          ));
          continue;
        }

        lines.add(LyricLine(
          time: Duration(milliseconds: lineStartMs),
          text: words.map((w) => w.text).join(),
          words: words,
        ));
      }

      lines.sort((a, b) => a.time.compareTo(b.time));
      return lines;
    } catch (_) {
      return [];
    }
  }

  /// 解析词标签。词的文本 = 从本标签结束到下一标签开始之间的字符串。
  static List<LyricWord> _parseWords(String rest, int lineStartMs) {
    if (rest.isEmpty) return const [];
    final matches = _wordTag.allMatches(rest).toList();
    if (matches.isEmpty) return const [];

    final words = <LyricWord>[];
    for (int i = 0; i < matches.length; i++) {
      final m = matches[i];
      final offset = int.tryParse(m.group(1) ?? '');
      final duration = int.tryParse(m.group(2) ?? '');
      if (offset == null || duration == null) continue;

      final textEnd = i + 1 < matches.length ? matches[i + 1].start : rest.length;
      final text = rest.substring(m.end, textEnd);
      if (text.isEmpty) continue;

      words.add(LyricWord(
        // 绝对时间 = 行首 + 词偏移
        time: Duration(milliseconds: lineStartMs + offset),
        duration: Duration(milliseconds: duration),
        text: text,
      ));
    }
    return words;
  }
}
