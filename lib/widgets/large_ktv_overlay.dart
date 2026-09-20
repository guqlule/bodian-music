import 'dart:async';
import 'dart:math' as math;

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
  late final _FireworksBokehPainter _gradientPainter;

  @override
  void initState() {
    super.initState();
    _gradientAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    _gradientPainter = _FireworksBokehPainter(
      repaint: Listenable.merge([_gradientAnim, _tickerListenable]),
      animation: _gradientAnim,
      playing: () => _playing,
    );
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
      animation: Listenable.merge([_gradientAnim, _tickerListenable]),
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

/// 烟花 + 流行（bokeh 流光粒子）混合背景 Painter。
/// 不依赖频谱，自包含。播放中持续发射烟花 + 漂浮 bokeh；暂停时粒子冻结。
/// 通过 [notify] 每帧触发重绘（由外部 ticker 驱动）。
class _FireworksBokehPainter extends CustomPainter {
  final Animation<double> animation;
  final bool Function() playing;

  final math.Random _random = math.Random();
  final List<_FwRocket> _rockets = [];
  final List<_FwSpark> _sparks = [];
  final List<_Bokeh> _bokeh = [];

  _FireworksBokehPainter({
    required Listenable repaint,
    required this.animation,
    required this.playing,
  }) : super(repaint: repaint) {
    _initBokeh();
  }

  void _initBokeh() {
    for (int i = 0; i < 24; i++) {
      _bokeh.add(_Bokeh(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        size: 0.02 + _random.nextDouble() * 0.06,
        vx: (0.0002 + _random.nextDouble() * 0.0004) * (_random.nextBool() ? 1 : -1),
        vy: -(0.0001 + _random.nextDouble() * 0.0003),
        hue: 180 + _random.nextDouble() * 120, // 蓝-紫-粉
        alpha: 0.05 + _random.nextDouble() * 0.12,
        pulsePhase: _random.nextDouble() * 6.28,
      ));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final isPlaying = playing();

    // 1. 深色基底
    final bgPaint = Paint()..color = const Color(0xFF0A0A12);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // 2. 环境光晕（底部暖光 + 顶部冷光，缓慢脉动）
    final t = animation.value;
    final breathe = 0.5 + 0.5 * _sin(t * 6.283);
    final warmGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.fromARGB((20 + (10 * breathe).round()), 200, 120, 60),
          Color(0x00000000),
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(w * 0.5, h * 0.95),
        radius: h * 0.7,
      ));
    canvas.drawRect(Offset.zero & size, warmGlow);

    final coolGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.fromARGB((15 + (8 * breathe).round()), 60, 100, 200),
          Color(0x00000000),
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(w * 0.5, h * 0.1),
        radius: h * 0.6,
      ));
    canvas.drawRect(Offset.zero & size, coolGlow);

    if (isPlaying) {
      // 3. 发射烟花（约每 800ms 一枚，最多 5 枚同时）
      _maybeLaunchRocket(w, h);

      // 4. 更新 & 绘制烟花弹
      for (int i = _rockets.length - 1; i >= 0; i--) {
        final r = _rockets[i];
        r.y += r.vy;
        r.vy += 0.1;
        r.x += r.vx;
        if (r.y <= r.targetY || r.vy >= -1) {
          _explode(r, w, h);
          _rockets.removeAt(i);
        } else {
          final alpha = r.life;
          final rocketColor = HSLColor.fromAHSL(alpha, 40, 1.0, 0.75).toColor();
          final rp = Paint()
            ..color = rocketColor
            ..strokeCap = StrokeCap.round;
          canvas.drawCircle(Offset(r.x, r.y), 2 + alpha * 2, rp);
          // 拖尾
          final trail = Paint()
            ..color = Color.fromARGB((alpha * 80).round(), 255, 200, 100)
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(Offset(r.x, r.y), Offset(r.x, r.y - r.vy * 4), trail);
        }
      }

      // 5. 更新 & 绘制爆炸火花
      for (int i = _sparks.length - 1; i >= 0; i--) {
        final s = _sparks[i];
        s.x += s.vx;
        s.y += s.vy;
        s.vy += 0.05; // 重力
        s.vx *= 0.99;
        s.life -= 0.012 / s.maxLife;
        if (s.life <= 0) {
          _sparks.removeAt(i);
          continue;
        }
        final alpha = s.life.clamp(0.0, 1.0);
        final color = HSLColor.fromAHSL(alpha, s.hue, 0.9, 0.5 + alpha * 0.25).toColor();
        final radius = s.size * s.life;
        // 外晕
        final halo = Paint()..color = color.withValues(alpha: alpha * 0.08);
        canvas.drawCircle(Offset(s.x, s.y), radius * 3.5, halo);
        // 内核
        final core = Paint()..color = color;
        canvas.drawCircle(Offset(s.x, s.y), radius, core);
      }

      // 6. 更新 & 绘制 bokeh 流光
      for (final b in _bokeh) {
        b.x += b.vx;
        b.y += b.vy;
        // 边界回绕
        if (b.y < -0.1) b.y = 1.1;
        if (b.x < -0.1) b.x = 1.1;
        if (b.x > 1.1) b.x = -0.1;
        final pulse = 0.5 + 0.5 * _sin(t * 4 + b.pulsePhase);
        final alpha = b.alpha * (0.5 + pulse * 0.5);
        final bx = b.x * w;
        final by = b.y * h;
        final br = b.size * w * (0.8 + pulse * 0.4);
        final bp = Paint()
          ..shader = RadialGradient(
            colors: [
              HSLColor.fromAHSL(alpha, b.hue, 0.7, 0.6).toColor(),
              Color(0x00000000),
            ],
          ).createShader(Rect.fromCircle(center: Offset(bx, by), radius: br));
        canvas.drawCircle(Offset(bx, by), br, bp);
      }
    } else {
      // 暂停：只画静止的 bokeh（无烟花）
      for (final b in _bokeh) {
        final bx = b.x * w;
        final by = b.y * h;
        final br = b.size * w;
        final bp = Paint()
          ..shader = RadialGradient(
            colors: [
              HSLColor.fromAHSL(b.alpha * 0.5, b.hue, 0.7, 0.6).toColor(),
              Color(0x00000000),
            ],
          ).createShader(Rect.fromCircle(center: Offset(bx, by), radius: br));
        canvas.drawCircle(Offset(bx, by), br, bp);
      }
    }
  }

  void _maybeLaunchRocket(double w, double h) {
    if (_rockets.length >= 5) return;
    // 概率发射（约 0.66 帧发射一次，~40ms 内）
    if (_random.nextDouble() < 0.08) {
      final hue = _random.nextDouble() * 360;
      _rockets.add(_FwRocket(
        x: w * (0.15 + _random.nextDouble() * 0.7),
        y: h,
        targetY: h * (0.1 + _random.nextDouble() * 0.35),
        vx: (_random.nextDouble() - 0.5) * 1.5,
        vy: -(7 + _random.nextDouble() * 5),
        hue: hue,
      ));
    }
  }

  void _explode(_FwRocket r, double w, double h) {
    final count = 30 + _random.nextInt(20);
    for (int i = 0; i < count; i++) {
      final angle = (i / count) * 6.283 + _random.nextDouble() * 0.5;
      final speed = 1.5 + _random.nextDouble() * 3.5;
      _sparks.add(_FwSpark(
        x: r.x,
        y: r.y,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed,
        hue: r.hue + _random.nextDouble() * 20 - 10,
        size: 1.5 + _random.nextDouble() * 1.5,
        life: 1.0,
        maxLife: 0.6 + _random.nextDouble() * 0.5,
      ));
    }
  }

  static double _sin(double x) {
    x = x % 6.2831853;
    if (x < 0) x += 6.2831853;
    final q = (x / 3.14159265 - 2).abs();
    return (1 - q * q) * (q < 1 ? 1 : -1);
  }

  @override
  bool shouldRepaint(covariant _FireworksBokehPainter old) => true;
}

// ---- 粒子数据结构 ----
class _FwRocket {
  double x, y, targetY, vx, vy;
  final double hue;
  double life = 1.0;
  _FwRocket({
    required this.x,
    required this.y,
    required this.targetY,
    required this.vx,
    required this.vy,
    required this.hue,
  });
}

class _FwSpark {
  double x, y, vx, vy, hue, size, life, maxLife;
  _FwSpark({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.hue,
    required this.size,
    required this.life,
    required this.maxLife,
  });
}

class _Bokeh {
  double x, y, size, vx, vy, hue, alpha, pulsePhase;
  _Bokeh({
    required this.x,
    required this.y,
    required this.size,
    required this.vx,
    required this.vy,
    required this.hue,
    required this.alpha,
    required this.pulsePhase,
  });
}
