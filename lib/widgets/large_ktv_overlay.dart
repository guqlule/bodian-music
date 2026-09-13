import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../providers/app_providers.dart';
import '../services/lyric/lyric_parser.dart';

/// 全屏大歌词 overlay — RichText 逐字符 Color.lerp 扫字
class LargeKtvLyricOverlay extends ConsumerStatefulWidget {
  const LargeKtvLyricOverlay({super.key});

  @override
  ConsumerState<LargeKtvLyricOverlay> createState() => _LargeKtvLyricOverlayState();
}

class _LargeKtvLyricOverlayState extends ConsumerState<LargeKtvLyricOverlay>
    with SingleTickerProviderStateMixin {
  List<LyricLine> _lyrics = [];
  String _lyricKey = '';
  Duration _basePos = Duration.zero;
  DateTime _basePosTime = DateTime.now();
  bool _playing = false;
  late Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readInitial();
    });
  }

  void _readInitial() {
    if (!mounted) return;
    _tryParseLyric(ref.read(lyricProvider).valueOrNull);
    _basePos = ref.read(positionProvider).valueOrNull ?? Duration.zero;
    _basePosTime = DateTime.now();
    _playing = ref.read(isPlayingProvider).valueOrNull ?? false;
    _syncTicker();
    // 监听播放状态变化
    ref.listen<AsyncValue<bool>>(isPlayingProvider, (prev, next) {
      final p = next.valueOrNull ?? false;
      if (p != _playing && mounted) {
        _playing = p;
        _syncTicker();
      }
    });
  }

  void _syncTicker() {
    if (_playing && !_ticker.isActive) {
      _ticker.start();
    } else if (!_playing && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tryParseLyric(Map<String, String?>? lyricMap) {
    final lyricText = lyricMap?['lyric'] ?? '';
    final key = '${ref.read(currentMusicProvider).valueOrNull?.id ?? ''}_$lyricText';
    if (key == _lyricKey) return;
    _lyricKey = key;
    _lyrics = LyricParser.parse(lyricText);
  }

  int _findIndex(Duration pos) {
    int idx = -1;
    for (int i = 0; i < _lyrics.length; i++) {
      if (pos >= _lyrics[i].time) idx = i;
      else break;
    }
    return idx;
  }

  Duration get _estPos {
    final p = ref.read(positionProvider).valueOrNull ?? Duration.zero;
    return _playing ? p + DateTime.now().difference(_basePosTime) : p;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(lyricProvider, (prev, next) {
      _tryParseLyric(next.valueOrNull);
    });
    ref.listen(positionProvider, (prev, next) {
      next.whenData((p) {
        _basePos = p;
        _basePosTime = DateTime.now();
      });
    });
    ref.listen(isPlayingProvider, (prev, next) {
      _playing = next.valueOrNull ?? false;
    });
    ref.listen(currentMusicProvider, (prev, next) {
      if (prev?.valueOrNull?.id != next.valueOrNull?.id) {
        _lyricKey = '';
        _lyrics = [];
        _tryParseLyric(ref.read(lyricProvider).valueOrNull);
      }
    });

    if (_lyricKey.isEmpty) {
      _tryParseLyric(ref.read(lyricProvider).valueOrNull);
    }

    final idx = _findIndex(_estPos);
    if (idx < 0 || _lyrics.isEmpty) {
      return Container(
        color: Colors.black54,
        alignment: Alignment.center,
        child: const Text('暂无歌词',
            style: TextStyle(color: Colors.white54, fontSize: 18)),
      );
    }

    final current = _lyrics[idx];
    final currentEnd = idx + 1 < _lyrics.length
        ? _lyrics[idx + 1].time
        : current.time + const Duration(seconds: 5);
    final currentDur = currentEnd - current.time;
    final currentProgress = currentDur > Duration.zero
        ? ((_estPos - current.time).inMilliseconds / currentDur.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    final hasNext = idx + 1 < _lyrics.length;
    final nextLine = hasNext ? _lyrics[idx + 1] : null;

    // 自适应字号
    final screenW = MediaQuery.of(context).size.width;
    final maxChars = [current.text.length, if (nextLine != null) nextLine.text.length]
        .reduce((a, b) => a > b ? a : b);
    double mainFontSize;
    if (maxChars <= 8) mainFontSize = 68;
    else if (maxChars <= 14) mainFontSize = 58;
    else if (maxChars <= 20) mainFontSize = 48;
    else if (maxChars <= 30) mainFontSize = 40;
    else mainFontSize = 34;
    final isPortrait = screenW < 500;
    if (isPortrait && maxChars > 12) mainFontSize = (mainFontSize * 0.85).clamp(30.0, 68.0);
    final subFontSize = (mainFontSize * 0.65).clamp(24.0, 44.0);

    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (current.text.isNotEmpty)
              current.hasWords
                  ? _buildWordByWordText(current, _estPos, mainFontSize)
                  : LerpScanText(
                      text: current.text,
                      progress: currentProgress,
                      scannedColor: AppColors.primaryDark,
                      unscannedColor: AppColors.textHint,
                      fontSize: mainFontSize,
                      fontWeight: FontWeight.w900,
                    ),
            if (nextLine != null && nextLine.text.isNotEmpty) ...[
              const SizedBox(height: 32),
              RichText(
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                text: TextSpan(
                  text: nextLine.text,
                  style: TextStyle(
                    fontSize: subFontSize,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textHint,
                    fontFamily: 'sans-serif',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 逐字 KTV 文字渲染
  Widget _buildWordByWordText(LyricLine line, Duration position, double fontSize) {
    final words = line.words!;
    final spans = <TextSpan>[];

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final wordEnd = word.duration != null
          ? word.time + word.duration!
          : word.time + const Duration(seconds: 1);

      double wordProgress;
      if (position < word.time) {
        wordProgress = 0.0;
      } else if (position >= wordEnd) {
        wordProgress = 1.0;
      } else {
        wordProgress = (position - word.time).inMilliseconds /
            (wordEnd - word.time).inMilliseconds;
      }
      wordProgress = wordProgress.clamp(0.0, 1.0);

      final color = Color.lerp(
        AppColors.textHint,
        AppColors.primaryDark,
        wordProgress,
      )!;

      spans.add(TextSpan(
        text: word.text,
        style: TextStyle(color: color),
      ));
    }

    return RichText(
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      text: TextSpan(
        children: spans,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

/// 逐字符 Color.lerp 扫字 — 无 ShaderMask / ClipRect，零伪影。
/// 每个字符根据 progress 在 scannedColor 与 unscannedColor 之间平滑插值。
/// 过渡带宽度约 2 个字符宽，边界处柔和渐变。
class LerpScanText extends StatelessWidget {
  final String text;
  final double progress;
  final Color scannedColor;
  final Color unscannedColor;
  final double fontSize;
  final FontWeight fontWeight;

  const LerpScanText({
    required this.text,
    required this.progress,
    required this.scannedColor,
    required this.unscannedColor,
    required this.fontSize,
    required this.fontWeight,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final len = text.length;
    // 过渡带宽度 = 2 个字符
    final transitionWidth = 2.0 / len;
    final scanCenter = progress;

    final spans = <TextSpan>[];
    for (int i = 0; i < len; i++) {
      // 字符中心位置
      final charCenter = (i + 0.5) / len;
      // 计算该字符的扫描权重 (0=未扫, 1=已扫)
      double weight;
      if (scanCenter <= 0) {
        weight = 0;
      } else if (scanCenter >= 1) {
        weight = 1;
      } else {
        // 在 transitionWidth 范围内从 0 平滑过渡到 1
        weight = ((charCenter - scanCenter) / transitionWidth + 0.5)
            .clamp(0.0, 1.0);
      }
      final color = Color.lerp(scannedColor, unscannedColor, weight)!;
      spans.add(TextSpan(
        text: text[i],
        style: TextStyle(color: color),
      ));
    }

    return RichText(
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      text: TextSpan(
        children: spans,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontFamily: 'sans-serif',
        ),
      ),
    );
  }
}
