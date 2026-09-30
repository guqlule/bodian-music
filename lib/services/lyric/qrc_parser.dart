import 'lyric_parser.dart' show LyricLine, LyricWord;

/// QQ 音乐 QRC 逐字歌词解析
///
/// 格式（时间单位为毫秒）：
/// ```
/// [start,duration]word(start,duration)word(start,duration)...
/// [81000,2720]Stop(81000,720) me(81720,640) now(82360,1360)
/// ```
///
/// 注意：词文本在**自己时间标签之前**，
/// 所以文本 = 上一标签的 `)` 到本标签的 `(` 之间的字符串。
class QrcParser {
  /// 行级时间戳：`[start,duration]`
  static final RegExp _lineTs = RegExp(r'^\[(\d+),(\d+)\](.*)$');

  /// 词标签：`(start,duration)`，圆括号
  static final RegExp _wordTag = RegExp(r'\((\d+),(\d+)\)');

  static final RegExp _metaHeader = RegExp(r'^\[[A-Za-z][A-Za-z0-9]*:');
  static const List<String> _metaPrefixes = [
    '[id:', '[ar:', '[ti:', '[by:', '[hash:', '[al:', '[sign:',
    '[qq:', '[total:', '[offset:', '[language:', '[kana:',
  ];

  static bool isQrc(String text) {
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || _isMeta(line)) continue;
      // 行首是 [数字,数字] 且正文含 (数字,数字) 词标签
      if (RegExp(r'^\[\d+,\d+\]').hasMatch(line)) {
        return _wordTag.hasMatch(line);
      }
      return false;
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

  /// QRC 时间单位即毫秒，无需换算
  static Duration _ms(int v) => Duration(milliseconds: v);

  static List<LyricLine> parse(String qrcText) {
    try {
      final lines = <LyricLine>[];
      if (qrcText.isEmpty) return lines;

      for (final raw in qrcText.split('\n')) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        if (_isMeta(line)) continue;

        final m = _lineTs.firstMatch(line);
        if (m == null) continue;

        final lineStart = int.tryParse(m.group(1)!) ?? 0;
        final rest = m.group(3) ?? '';

        final tags = _wordTag.allMatches(rest).toList();
        if (tags.isEmpty) {
          // 无词标签，纯文本行
          final plain = rest.trim();
          lines.add(LyricLine(
            time: _ms(lineStart),
            text: plain.isEmpty ? '\u00A0' : plain,
          ));
          continue;
        }

        final words = <LyricWord>[];
        // 上一标签结束位置，即本词文本起点
        var cursor = 0;
        for (final t in tags) {
          final startMs = int.tryParse(t.group(1)!) ?? 0;
          final durMs = int.tryParse(t.group(2)!) ?? 0;
          // 文本 = cursor 到本标签开始之间
          final text = rest.substring(cursor, t.start);
          if (text.isNotEmpty) {
            words.add(LyricWord(
              time: _ms(startMs),
              duration: _ms(durMs),
              text: text,
            ));
          }
          // 下一个词的文本从本标签的 `)` 之后开始
          cursor = t.end;
        }

        lines.add(LyricLine(
          time: _ms(lineStart),
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
}
