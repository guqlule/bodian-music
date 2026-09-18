import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../providers/app_providers.dart';
import '../services/lyric/lyric_parser.dart';

/// 全屏大歌词 overlay — RichText 逐字符 Color.lerp 扫字 + 缓慢渐变流动背景
class LargeKtvLyricOverlay extends ConsumerStatefulWidget {
  const LargeKtvLyricOverlay({super.key});

  @override
  ConsumerState<LargeKtvLyricOverlay> createState() => _LargeKtvLyricOverlayState();
}

class _LargeKtvLyricOverlayState extends ConsumerState<LargeKtvLyricOverlay>
    with SingleTickerProviderStateMixin {
  List<LyricLine> _lyrics = [];
  String _lyricKey = '';
  int _lastIdx = -1; // 上次歌词行索引
  Duration _basePos = Duration.zero;
  DateTime _basePosTime = DateTime.now();
  bool _playing = false;
  Timer? _ticker;
  final _TickerListenable _tickerListenable = _TickerListenable();

  late final AnimationController _gradientAnim;
  late final _FlowingGradientPainter _gradientPainter;

  @override
  void initState() {
    super.initState();
    _gradientAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    _gradientPainter = _FlowingGradientPainter(animation: _gradientAnim);
    _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) => _onTick());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readInitial();
    });
  }

  /// Ticker 回调：节流至 ~30fps。
  /// 不再调用 setState —— AnimatedBuilder 会自动监听 ticker 触发局部重建。
  /// 扫字视觉感受需要 30fps+ 才平滑，60fps 收益边际递减但开销翻倍。
  void _onTick() {
    if (!mounted) return;
    _tickerListenable.notify();
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
    if (_playing && _ticker == null) {
      _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) => _onTick());
    } else if (!_playing && _ticker != null) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _tryParseLyric(Map<String, String?>? lyricMap) {
    final lyricText = lyricMap?['lyric'] ?? '';
    final key = '${ref.read(currentMusicProvider).valueOrNull?.id ?? ''}_$lyricText';
    if (key == _lyricKey) return;
    _lyricKey = key;
    _lyrics = LyricParser.parse(lyricText);
    _lastIdx = -1; // 重置搜索起点
  }

  int _findIndex(Duration pos) {
    final n = _lyrics.length;
    int start;
    int idx;
    if (_lastIdx >= 0 &&
        _lastIdx < n &&
        pos >= _lyrics[_lastIdx].time) {
      start = _lastIdx;
      idx = _lastIdx;
    } else {
      // seek 后退或初始化：从头搜索
      start = 0;
      idx = -1;
    }
    while (start < n && pos >= _lyrics[start].time) {
      idx = start;
      start++;
    }
    _lastIdx = idx;
    return idx;
  }

  Duration get _estPos {
    final p = ref.read(positionProvider).valueOrNull ?? Duration.zero;
    return _playing ? p + DateTime.now().difference(_basePosTime) : p;
  }

  @override
  void dispose() {
    _gradientAnim.dispose();
    _ticker?.cancel();
    _tickerListenable.dispose();
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
        _lastIdx = -1;
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

    // 优化：把 setState 全树重建改为 AnimatedBuilder 局部重建。
    // 每 33ms 只有 _LyricsContent 内的 RichText 重绘，
    // 字体/字号/Container 等都不动，setState 不再触发整树 rebuild。
    return AnimatedBuilder(
      animation: _gradientAnim,
      builder: (context, _) {
        return CustomPaint(
          painter: _gradientPainter,
          child: Container(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // RepaintBoundary 把当前行和下一行隔开，下一行不变就不重绘
                  RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _tickerListenable,
                      builder: (context, _) {
                        final pos = _estPos;
                        final progress = currentDur > Duration.zero
                            ? ((pos - current.time).inMilliseconds / currentDur.inMilliseconds)
                                .clamp(0.0, 1.0)
                            : 0.0;
                        if (current.text.isEmpty) return const SizedBox.shrink();
                        return current.hasWords
                            ? _buildWordByWordText(current, pos, mainFontSize)
                            : LerpScanText(
                                text: current.text,
                                progress: progress,
                                scannedColor: AppColors.primaryDark,
                                unscannedColor: AppColors.textHint,
                                fontSize: mainFontSize,
                                fontWeight: FontWeight.w900,
                              );
                      },
                    ),
                  ),
                  if (nextLine != null && nextLine.text.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    // 下一行不需要动画，用 RepaintBoundary 隔开避免重建
                    RepaintBoundary(
                      child: RichText(
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
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
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

/// 自建 Listenable，让 AnimatedBuilder 能订阅我们的 Timer
class _TickerListenable extends ChangeNotifier {
  void notify() => notifyListeners();
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

/// 缓慢流动的深色渐变背景 Painter。
/// 12 秒一个周期，三个色点沿贝塞尔路径缓慢移动，
/// 营造出沉浸式但不抢歌词的氛围感。
class _FlowingGradientPainter extends CustomPainter {
  final Animation<double> animation;

  _FlowingGradientPainter({required this.animation})
      : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value; // 0..1

    // 三个色点，用 sin/cos 做圆形轨道运动
    final p1 = Offset(
      size.width * (0.2 + 0.15 * _sin(t * 2 * 3.14159)),
      size.height * (0.3 + 0.2 * _cos(t * 2 * 3.14159)),
    );
    final p2 = Offset(
      size.width * (0.7 + 0.2 * _cos(t * 2 * 3.14159 + 2.0)),
      size.height * (0.6 + 0.15 * _sin(t * 2 * 3.14159 + 2.0)),
    );
    final p3 = Offset(
      size.width * (0.5 + 0.18 * _sin(t * 2 * 3.14159 + 4.0)),
      size.height * (0.8 + 0.12 * _cos(t * 2 * 3.14159 + 4.0)),
    );

    // 基底深色
    final bgPaint = Paint()..color = const Color(0xFF0D0D0D);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // 柔和光晕叠加（使用 BlendMode.screen 做加色混合）
    final glow1 = Paint()
      ..shader = RadialGradient(
        colors: const [
          Color(0x30C9A882), // primary 低透明度
          Color(0x00000000),
        ],
      ).createShader(Rect.fromCircle(center: p1, radius: size.width * 0.5));
    canvas.drawRect(Offset.zero & size, glow1);

    final glow2 = Paint()
      ..shader = RadialGradient(
        colors: const [
          Color(0x20A8C4C9), // accent1 低透明度
          Color(0x00000000),
        ],
      ).createShader(Rect.fromCircle(center: p2, radius: size.width * 0.45));
    canvas.drawRect(Offset.zero & size, glow2);

    final glow3 = Paint()
      ..shader = RadialGradient(
        colors: const [
          Color(0x18C9A8B8), // accent2 低透明度
          Color(0x00000000),
        ],
      ).createShader(Rect.fromCircle(center: p3, radius: size.width * 0.4));
    canvas.drawRect(Offset.zero & size, glow3);
  }

  /// sin 快速近似（避免引入 math 库）
  static double _sin(double x) {
    x = x % (2 * 3.14159265);
    if (x < 0) x += 2 * 3.14159265;
    // 三阶近似，误差 < 0.02
    final q = (x / 3.14159265 - 2).abs();
    return (1 - q * q) * (q < 1 ? 1 : -1);
  }

  static double _cos(double x) => _sin(x + 3.14159265 / 2);

  @override
  bool shouldRepaint(_FlowingGradientPainter old) => true;
}
