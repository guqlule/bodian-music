import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../services/lyric/lyric_parser.dart';

/// Apple Music 风格歌词视图
///
/// 设计要点：
/// - 单 CustomPainter 绘制全部歌词，无 ListView / ScrollController
/// - 文本统一白色，仅用 alpha 表达层次（不做大范围高斯模糊，保证可读）
/// - 缩放 + alpha 按行距**平滑衰减**，没有突兀断层
/// - 逐字歌词用连续 alpha 播放头 + 软过渡带扫过
/// - 滚动由解析弹簧驱动，欠阻尼有回弹
/// - ShaderMask 上下渐隐
class AppleLyricsView extends StatefulWidget {
  final List<LyricLine> lines;
  final Duration position;
  final ValueChanged<Duration> onSeek;

  const AppleLyricsView({
    super.key,
    required this.lines,
    required this.position,
    required this.onSeek,
  });

  @override
  State<AppleLyricsView> createState() => _AppleLyricsViewState();
}

class _AppleLyricsViewState extends State<AppleLyricsView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  // ---- 布局常量 ----
  static const double _fontSize = 27.0;
  static const double _lineSpacing = 1.62; // 行高倍率（紧凑，接近 Apple Music）
  static const double _inactiveScale = 0.86;
  static const double _alignPosition = 0.36; // 当前行锚定在视口 36%
  static const double _leftPaddingEm = 1.1;
  static const double _maxLiftPx = -3.0;
  static const double _overscan = 240.0;

  // ---- 弹簧 ----
  final _Spring _posY = _Spring(mass: 1, stiffness: 130, damping: 26.0);
  final List<_Spring> _lineScales = [];

  // ---- 几何缓存 ----
  final List<double> _lineTops = [];
  final List<double> _lineHeights = [];
  double _viewportH = 0;

  // ---- 交互 ----
  double _dragTotal = 0;
  bool _userScrolling = false;
  int _autoReturnMs = 0;
  Duration _lastPos = Duration.zero;
  int _currentIndex = -1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _rebuild();
  }

  @override
  void didUpdateWidget(covariant AppleLyricsView old) {
    super.didUpdateWidget(old);
    if (old.lines != widget.lines) _rebuild();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  double get _rowHeight => _fontSize * _lineSpacing;

  void _rebuild() {
    _lineTops.clear();
    _lineHeights.clear();
    var y = 0.0;
    for (final l in widget.lines) {
      final hasTrans = l.translation != null && l.translation!.isNotEmpty;
      final h = _rowHeight + (hasTrans ? _fontSize * 0.9 : 0);
      _lineTops.add(y);
      _lineHeights.add(h);
      y += h;
    }
    while (_lineScales.length < widget.lines.length) {
      _lineScales.add(_Spring(
        mass: 2,
        stiffness: 120,
        damping: 26,
        initial: _inactiveScale,
      ));
    }
    if (_lineScales.length > widget.lines.length) {
      _lineScales.removeRange(widget.lines.length, _lineScales.length);
    }
  }

  double _topOf(int i) => i < _lineTops.length ? _lineTops[i] : 0.0;
  double _heightOf(int i) =>
      i < _lineHeights.length ? _lineHeights[i] : _rowHeight;

  double _targetY(int index) {
    if (index < 0) return 0;
    return -(_topOf(index) + _heightOf(index) / 2 - _viewportH * _alignPosition);
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed.inMicroseconds / 1e6).clamp(0.0, 0.05);

    final pos = widget.position;
    if (pos != _lastPos) {
      _lastPos = pos;
      final idx = _findIndex(pos);
      if (idx != _currentIndex) {
        _currentIndex = idx;
        if (!_userScrolling) _posY.setTarget(_targetY(idx));
      }
    }

    if (_userScrolling && _autoReturnMs > 0) {
      _autoReturnMs -= (dt * 1000).round();
      if (_autoReturnMs <= 0) {
        _userScrolling = false;
        _posY.setTarget(_targetY(_currentIndex));
      }
    }

    _posY.step(dt);
    for (int i = 0; i < _lineScales.length; i++) {
      _lineScales[i].setTarget(i == _currentIndex ? 1.0 : _inactiveScale);
      _lineScales[i].step(dt);
    }

    _frame.value++;
  }

  int _findIndex(Duration pos) {
    for (int i = widget.lines.length - 1; i >= 0; i--) {
      if (pos >= widget.lines[i].time) return i;
    }
    return -1;
  }

  // ---------------- 手势 ----------------

  void _onDragUpdate(DragUpdateDetails d) {
    _userScrolling = true;
    _autoReturnMs = 3000;
    _dragTotal += d.primaryDelta ?? 0;
    _posY.setPosition(
        _posY.position + (d.primaryDelta ?? 0), _posY.velocity);
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dy;
    final inertia = (v * 0.25).clamp(-240.0, 240.0);
    if (inertia.abs() > 5) {
      final cur = _posY.position;
      _posY.setPosition(cur, v);
      _posY.setTarget(cur + inertia);
    }
  }

  void _onTapUp(TapUpDetails d) {
    if (_dragTotal.abs() > 10) {
      _dragTotal = 0;
      return;
    }
    _dragTotal = 0;
    final idx = _hitTest(d.localPosition);
    if (idx >= 0) {
      widget.onSeek(widget.lines[idx].time);
      _userScrolling = false;
      _autoReturnMs = 0;
      _posY.setTarget(_targetY(idx));
    }
  }

  int _hitTest(Offset p) {
    if (_viewportH <= 0) return -1;
    final contentY = p.dy - _posY.position;
    for (int i = widget.lines.length - 1; i >= 0; i--) {
      if (contentY >= _topOf(i) - _rowHeight * 0.5) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportH = constraints.maxHeight;
        if (_currentIndex >= 0 && _lineScales.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _posY.setTarget(_targetY(_currentIndex));
          });
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _onTapUp,
          onVerticalDragUpdate: _onDragUpdate,
          onVerticalDragEnd: _onDragEnd,
          child: ShaderMask(
            shaderCallback: (bounds) {
              final r = (28.0 / bounds.height).clamp(0.0, 0.5);
              return LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: const [
                  Colors.transparent,
                  Colors.black,
                  Colors.black,
                  Colors.transparent,
                ],
                stops: [0.0, r, 1.0 - r, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: ClipRect(
              child: ValueListenableBuilder<int>(
                valueListenable: _frame,
                builder: (context, _, __) => CustomPaint(
                  painter: _AppleLyricsPainter(
                    lines: widget.lines,
                    currentIndex: _currentIndex,
                    position: widget.position,
                    posY: _posY.position,
                    scales: _lineScales,
                    topOf: _topOf,
                    heightOf: _heightOf,
                    viewportH: _viewportH,
                    viewportW: constraints.maxWidth,
                    fontSize: _fontSize,
                    rowHeight: _rowHeight,
                    leftPadding: _fontSize * _leftPaddingEm,
                    rightPadding: _fontSize * 0.9,
                    inactiveScale: _inactiveScale,
                    maxLiftPx: _maxLiftPx,
                    overscan: _overscan,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 解析解阻尼谐振子（半隐式欧拉 + 固定子步长）
class _Spring {
  double _x;
  double _v;
  double _target;
  final double mass, stiffness, damping;

  _Spring({
    this.mass = 1,
    this.stiffness = 100,
    this.damping = 20,
    double initial = 0,
  })  : _x = initial,
        _v = 0,
        _target = initial;

  double get position => _x;
  double get velocity => _v;

  void setTarget(double t) => _target = t;
  void setPosition(double x, double v) {
    _x = x;
    _v = v;
  }

  void step(double dt) {
    if (dt <= 0) return;
    const sub = 0.008;
    var remain = dt;
    while (remain > 0) {
      final h = math.min(sub, remain);
      remain -= h;
      final a = (-stiffness * (_x - _target) - damping * _v) / mass;
      _v += a * h;
      _x += _v * h;
    }
    if ((_x - _target).abs() < 0.01 && _v.abs() < 0.01) {
      _x = _target;
      _v = 0;
    }
  }
}

/// 歌词绘制器
class _AppleLyricsPainter extends CustomPainter {
  final List<LyricLine> lines;
  final int currentIndex;
  final Duration position;
  final double posY;
  final List<_Spring> scales;
  final double Function(int) topOf;
  final double Function(int) heightOf;
  final double viewportH, viewportW, fontSize, rowHeight;
  final double leftPadding, rightPadding;
  final double inactiveScale, maxLiftPx, overscan;

  _AppleLyricsPainter({
    required this.lines,
    required this.currentIndex,
    required this.position,
    required this.posY,
    required this.scales,
    required this.topOf,
    required this.heightOf,
    required this.viewportH,
    required this.viewportW,
    required this.fontSize,
    required this.rowHeight,
    required this.leftPadding,
    required this.rightPadding,
    required this.inactiveScale,
    required this.maxLiftPx,
    required this.overscan,
  });

  /// 按行距平滑衰减的 alpha。
  ///
  /// 关键：连续曲线而非分段常量，避免出现「当前行清晰、相邻行突然消失」的断层。
  /// factor: 当前行 1.0 → 距离 1 约 0.55 → 距离 2 约 0.33 → 距离 3+ 收敛到 0.18
  double _alphaFor(int dist, {required bool active}) {
    if (active) return 1.0;
    // 1 / (1 + 1.15 * d^1.25)
    final f = 1.0 / (1.0 + 1.15 * math.pow(dist.toDouble(), 1.25));
    return 0.16 + f * 0.42;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (lines.isEmpty) return;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    final maxW = viewportW - leftPadding - rightPadding;

    for (int i = 0; i < lines.length; i++) {
      final lineH = heightOf(i);
      final y = topOf(i) + posY;
      if (y + lineH < -overscan) continue;
      if (y > viewportH + overscan) break;

      final isActive = i == currentIndex;
      final scale = i < scales.length ? scales[i].position : inactiveScale;
      final pivotY = y + lineH / 2;

      canvas.save();
      // 以左边缘为缩放中心（Apple Music 的锚点）
      canvas.translate(leftPadding, pivotY);
      canvas.scale(scale, scale);
      canvas.translate(-leftPadding, -pivotY);

      _paintLine(
        canvas: canvas,
        tp: tp,
        line: lines[i],
        lineIndex: i,
        y: y,
        maxW: maxW,
        isActive: isActive,
        dist: (i - currentIndex).abs(),
        scale: scale,
      );

      canvas.restore();
    }
  }

  void _paintLine({
    required Canvas canvas,
    required TextPainter tp,
    required LyricLine line,
    required int lineIndex,
    required double y,
    required double maxW,
    required bool isActive,
    required int dist,
    required double scale,
  }) {
    final alpha = _alphaFor(dist, active: isActive);
    final hasTrans = line.translation != null && line.translation!.isNotEmpty;

    if (isActive && line.hasWords) {
      _paintWordByWord(canvas, tp, line, y, maxW);
    } else if (isActive) {
      // 当前行 + 无逐字时间戳 → 行级扫光
      final a = _lineSweep(line, lineIndex);
      _paintText(canvas, tp, line.text, y, maxW, a.$1, a.$2);
    } else {
      _paintText(canvas, tp, line.text, y, maxW, alpha, alpha);
    }

    // 翻译行：只在当前行显示，跟随该行透明度
    if (hasTrans) {
      final transAlpha = isActive ? 0.55 : alpha * 0.8;
      final transSize = math.max(fontSize * 0.6, 12.0);
      tp.text = TextSpan(
        text: line.translation!,
        style: TextStyle(
          color: Colors.white.withValues(alpha: transAlpha),
          fontSize: transSize,
          fontWeight: FontWeight.w400,
          height: 1.35,
        ),
      );
      tp.layout(maxWidth: maxW);
      tp.paint(canvas, Offset(leftPadding, y + fontSize * 1.32));
    }
  }

  /// 绘制一行文字，支持左右不同 alpha（扫光渐变）
  void _paintText(
    Canvas canvas,
    TextPainter tp,
    String text,
    double y,
    double maxW,
    double alphaLeft,
    double alphaRight,
  ) {
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      height: 1.32,
    );

    if ((alphaLeft - alphaRight).abs() < 0.012) {
      tp.text = TextSpan(
        text: text,
        style: style.copyWith(
          color: Colors.white.withValues(alpha: alphaLeft),
        ),
      );
    } else {
      // 需要渐变：先量宽度，再用 shader 作为前景
      tp.text = TextSpan(text: text, style: style);
      tp.layout(maxWidth: maxW);
      final w = math.max(tp.width, 1.0);
      tp.text = TextSpan(
        text: text,
        style: style.copyWith(
          foreground: Paint()
            ..shader = ui.Gradient.linear(
              Offset(leftPadding, 0),
              Offset(leftPadding + w, 0),
              [
                Colors.white.withValues(alpha: alphaLeft),
                Colors.white.withValues(alpha: alphaRight),
              ],
            ),
        ),
      );
    }
    tp.layout(maxWidth: maxW);
    tp.paint(canvas, Offset(leftPadding, y + (fontSize * 1.32 - fontSize) / 2));
  }

  /// 当前行的演唱进度 0~1
  double _lineProgress(LyricLine line, int lineIndex) {
    final end = (lineIndex + 1 < lines.length)
        ? lines[lineIndex + 1].time
        : line.time + const Duration(seconds: 4);
    final total = end - line.time;
    if (total.inMilliseconds <= 0) return 1.0;
    final elapsed = position - line.time;
    if (elapsed.inMilliseconds <= 0) return 0.0;
    return (elapsed.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  /// 行级扫光（无逐字时间戳时）：亮区从左扫到右。
  /// 返回整行左右端的 alpha，中间由渐变插值。
  (double, double) _lineSweep(LyricLine line, int lineIndex) {
    final p = _lineProgress(line, lineIndex);
    const soft = 0.16; // 软带宽度（约 3 个字符）
    double a(double x) {
      final t = ((x - p) / soft + 1) / 2;
      final e = t.clamp(0.0, 1.0);
      final smooth = e * e * (3 - 2 * e); // smoothstep
      // 未唱部分 0.45（仍可读），已唱部分 1.0
      return 0.45 + smooth * 0.55;
    }

    return (a(0.0), a(1.0));
  }

  /// 逐字歌词：连续 alpha 播放头 + 软过渡带
  ///
  /// maskX = 已完成字累计宽度 + 当前字内进度 × 当前字宽
  /// 过渡带半宽固定为**行内平均字宽**（用当前字宽会在字切换瞬间闪烁）
  void _paintWordByWord(
    Canvas canvas,
    TextPainter tp,
    LyricLine line,
    double y,
    double maxW,
  ) {
    final words = line.words!;
    if (words.isEmpty) return;

    // 量出每个字的宽度与起始 X
    final widths = <double>[];
    final starts = <double>[];
    var x = 0.0;
    const baseStyle = TextStyle(
      color: Colors.white,
      fontSize: 27.0,
      fontWeight: FontWeight.w600,
      height: 1.32,
    );
    for (final w in words) {
      tp.text = TextSpan(text: w.text, style: baseStyle);
      tp.layout();
      starts.add(x);
      widths.add(tp.width);
      x += tp.width;
    }

    // 定位当前词与词内进度
    double maskX;
    var curIdx = -1;
    var intra = 0.0;
    for (int i = 0; i < words.length; i++) {
      final w = words[i];
      final wEnd = w.duration != null
          ? w.time + w.duration!
          : w.time + const Duration(seconds: 1);
      if (position >= wEnd) {
        curIdx = i + 1;
      } else if (position >= w.time) {
        curIdx = i;
        final total = wEnd - w.time;
        intra = total.inMilliseconds > 0
            ? ((position - w.time).inMilliseconds / total.inMilliseconds)
                .clamp(0.0, 1.0)
            : 1.0;
        break;
      } else {
        curIdx = i;
        intra = 0.0;
        break;
      }
    }

    if (curIdx >= words.length) {
      maskX = double.infinity;
    } else if (curIdx < 0) {
      maskX = -1.0;
    } else {
      maskX = starts[curIdx] + widths[curIdx] * intra;
    }

    // 过渡带半宽 = 行内平均字宽
    final meanW =
        widths.isEmpty ? 0.0 : widths.reduce((a, b) => a + b) / widths.length;
    final halfBand = meanW;

    const bright = 1.0;
    const dark = 0.45; // 未唱字仍保持可读

    for (int i = 0; i < words.length; i++) {
      final w = words[i];
      final sx = starts[i];
      final sw = widths[i];

      double aL, aR;
      if (maskX.isInfinite) {
        aL = aR = bright;
      } else if (maskX < 0) {
        aL = aR = dark;
      } else {
        final bandStart = maskX - halfBand;
        final bandSpan = halfBand * 2;
        aL = _alphaAtX(sx, bandStart, bandSpan, bright, dark);
        aR = _alphaAtX(sx + sw, bandStart, bandSpan, bright, dark);
      }

      // 已唱字轻微上浮
      double liftY = 0.0;
      if (i < curIdx) {
        liftY = maxLiftPx;
      } else if (i == curIdx) {
        final e = intra * intra * (3 - 2 * intra);
        liftY = maxLiftPx * e;
      }

      // 字内渐变 → 平滑扫过
      TextStyle style;
      if ((aL - aR).abs() < 0.012) {
        style = baseStyle.copyWith(
          color: Colors.white.withValues(alpha: aL),
        );
      } else {
        style = baseStyle.copyWith(
          foreground: Paint()
            ..shader = ui.Gradient.linear(
              Offset(leftPadding + sx, 0),
              Offset(leftPadding + sx + math.max(sw, 1.0), 0),
              [
                Colors.white.withValues(alpha: aL),
                Colors.white.withValues(alpha: aR),
              ],
            ),
        );
      }

      tp.text = TextSpan(text: w.text, style: style);
      tp.layout();
      tp.paint(canvas,
          Offset(leftPadding + sx, y + liftY + (fontSize * 1.32 - fontSize) / 2));
    }
  }

  /// X 坐标处的 alpha（软带）
  static double _alphaAtX(
    double x,
    double bandStart,
    double bandSpan,
    double bright,
    double dark,
  ) {
    if (bandSpan <= 0) return x <= bandStart ? bright : dark;
    if (x <= bandStart) return bright;
    final t = (x - bandStart) / bandSpan;
    if (t >= 1.0) return dark;
    return bright + (dark - bright) * t;
  }

  @override
  bool shouldRepaint(covariant _AppleLyricsPainter old) => true;
}
