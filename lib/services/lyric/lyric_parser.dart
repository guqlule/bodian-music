import 'dart:convert';
import 'package:crypto/crypto.dart';

/// 单个字/词，带独立时间戳（逐字歌词用）
class LyricWord {
  final Duration time;
  final String text;
  final Duration? duration; // 该字持续到下一个字的时间

  LyricWord({
    required this.time,
    required this.text,
    this.duration,
  });
}

class LyricLine {
  final Duration time;
  final String text;
  final String? translation;
  final String? romanization;
  final List<LyricWord>? words; // 逐字歌词数据，null 表示非逐字模式

  LyricLine({
    required this.time,
    required this.text,
    this.translation,
    this.romanization,
    this.words,
  });

  /// 是否为逐字歌词行
  bool get hasWords => words != null && words!.isNotEmpty;
}

class LyricParser {
  static final RegExp _timeRegExp = RegExp(r'\[(\d{2}):(\d{2})\.?(\d{0,3})\]');
  static final RegExp _tagRegExp = RegExp(r'\[([a-zA-Z]+):(.+)\]');
  // 逐字时间标签 <mm:ss.xx>
  static final RegExp _wordTimeRegExp = RegExp(r'<(\d{2}):(\d{2})\.?(\d{0,3})>');

  static List<LyricLine> parse(String lyricText) {
    if (lyricText.isEmpty) return [];

    final List<LyricLine> lines = [];
    final Map<String, String> tags = {};
    final List<MapEntry<Duration, String>> timedLines = [];

    final List<String> rawLines = lyricText.split('\n');

    for (final line in rawLines) {
      final String trimmedLine = line.trim();
      if (trimmedLine.isEmpty) continue;

      final tagMatch = _tagRegExp.firstMatch(trimmedLine);
      if (tagMatch != null) {
        tags[tagMatch.group(1)!] = tagMatch.group(2)!;
        continue;
      }

      final matches = _timeRegExp.allMatches(trimmedLine).toList();
      if (matches.isEmpty) continue;

      final String text = trimmedLine.replaceAll(_timeRegExp, '').trim();
      if (text.isEmpty) continue;

      for (final match in matches) {
        final int minutes = int.parse(match.group(1)!);
        final int seconds = int.parse(match.group(2)!);
        final int milliseconds = match.group(3)!.isNotEmpty
            ? int.parse(match.group(3)!.padRight(3, '0'))
            : 0;

        final Duration time = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );

        timedLines.add(MapEntry(time, text));
      }
    }

    timedLines.sort((a, b) => a.key.compareTo(b.key));

    for (final entry in timedLines) {
      // 尝试解析逐字数据
      final words = _parseWords(entry.value);
      if (words != null && words.isNotEmpty) {
        // 逐字模式：用第一个字的时间作为行时间
        lines.add(LyricLine(
          time: words.first.time,
          text: words.map((w) => w.text).join(),
          words: words,
        ));
      } else {
        lines.add(LyricLine(
          time: entry.key,
          text: entry.value,
        ));
      }
    }

    return lines;
  }

  /// 解析逐字歌词
  /// 支持格式: <mm:ss.xx>字<mm:ss.xx>字 或 纯文本（无时间标签则返回 null）
  static List<LyricWord>? _parseWords(String lineText) {
    final matches = _wordTimeRegExp.allMatches(lineText).toList();
    if (matches.isEmpty) return null;

    final words = <LyricWord>[];
    // 提取纯文本（去掉时间标签）
    final pureText = lineText.replaceAll(_wordTimeRegExp, '').trim();
    if (pureText.isEmpty) return null;

    // 如果时间标签数量与字符数不匹配，按字符均分
    final chars = pureText.split('');
    if (matches.length == chars.length) {
      // 一对一：每个字一个时间标签
      for (int i = 0; i < matches.length; i++) {
        final m = matches[i];
        final t = _parseDuration(m.group(1)!, m.group(2)!, m.group(3)!);
        words.add(LyricWord(time: t, text: chars[i]));
      }
    } else if (matches.length < chars.length) {
      // 时间标签少于字符数：均匀分配多余的字符
      for (int i = 0; i < chars.length; i++) {
        final tagIdx = (i * matches.length / chars.length).floor().clamp(0, matches.length - 1);
        final m = matches[tagIdx];
        final t = _parseDuration(m.group(1)!, m.group(2)!, m.group(3)!);
        words.add(LyricWord(time: t, text: chars[i]));
      }
    } else {
      // 时间标签多于字符数：忽略多余的标签
      for (int i = 0; i < chars.length; i++) {
        final m = matches[i];
        final t = _parseDuration(m.group(1)!, m.group(2)!, m.group(3)!);
        words.add(LyricWord(time: t, text: chars[i]));
      }
    }

    // 计算每个字的持续时间（到下一个字的时间差）
    for (int i = 0; i < words.length; i++) {
      if (i + 1 < words.length) {
        words[i] = LyricWord(
          time: words[i].time,
          text: words[i].text,
          duration: words[i + 1].time - words[i].time,
        );
      } else {
        words[i] = LyricWord(
          time: words[i].time,
          text: words[i].text,
          duration: const Duration(seconds: 1),
        );
      }
    }

    return words;
  }

  static Duration _parseDuration(String mm, String ss, String ms) {
    final int minutes = int.parse(mm);
    final int seconds = int.parse(ss);
    final int milliseconds = ms.isNotEmpty ? int.parse(ms.padRight(3, '0')) : 0;
    return Duration(
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  static List<LyricLine> mergeWithTranslation(
    List<LyricLine> original,
    String? translationText,
  ) {
    if (translationText == null || translationText.isEmpty) {
      return original;
    }

    final List<LyricLine> translationLines = parse(translationText);
    final Map<Duration, String> translationMap = {
      for (final line in translationLines) line.time: line.text,
    };

    return original.map((line) {
      final translation = translationMap[line.time];
      return LyricLine(
        time: line.time,
        text: line.text,
        translation: translation,
        words: line.words,
      );
    }).toList();
  }

  static String getTitle(Map<String, String> tags) {
    return tags['ti'] ?? '';
  }

  static String getArtist(Map<String, String> tags) {
    return tags['ar'] ?? '';
  }

  static String getAlbum(Map<String, String> tags) {
    return tags['al'] ?? '';
  }

  static String getOffset(Map<String, String> tags) {
    return tags['offset'] ?? '0';
  }

  static String calculateHash(String text) {
    return md5.convert(utf8.encode(text)).toString();
  }
}
