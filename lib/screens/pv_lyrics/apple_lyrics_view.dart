import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../services/lyric/lyric_parser.dart';

/// Apple Music 风格歌词视图
///
/// 移植自 md3Music 的 apple_lyrics_view 实现要点：
/// - 单个 CustomPainter 绘制全部歌词，无 ListView / ScrollController
/// - 文本统一白色，靠 alpha 渐变表达层次（不用不同颜色）
/// - 非当前行按行距分级高斯模糊（σ = 1 + |Δline|）
/// - 逐字歌词用连续 alpha 播放头 + 软过渡带扫过
/// - 滚动由解析弹簧驱动，欠阻尼有回弹
/// - ShaderMask 做上下 24px 渐隐
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

  // ---- 布局常量（对齐参考项目的默认值）----
  static const double _fontSize = 27.0;
  static const double _lineHeightMultiplier = 1.9; // 行间距倍率
  static const double _inactiveScale = 0.85; // 非当前行缩放
  static const double _alignPosition = 0.35; // 当前行锚定在视口 35% 处
  static const double _leftPaddingEm = 1.0; // 左内边距 = 1em
  static const double _maxLiftPx = -3.0; // 已唱字上浮
  static const double _overscan = 300.0; // 视口外剔除缓冲

  // ---- 弹簧状态 ----
  final _Spring _posY = _Spring(mass: 1, stiffness: 120, damping: 24.0);
  final List<_Spring> _lineScales = [];

  // ---- 几何缓存 ----
  List<double> _lineTops = [];
  List<double> _lineHeights = [];
  double _viewportH = 0;
  double _viewportW = 0;

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

  double get _lineHeight => _fontSize * _lineHeightMultiplier;

  void _rebuild() {
    _lineTops = <double>[];
    _lineHeights = <double>[];
    var y = 0.0;
    for (final l in widget.lines) {
      final hasTrans = l.translation != null && l.translation!.isNotEmpty;
      // 当前行额外为翻译行预留高度
      final h = _lineHeight + (hasTrans ? _fontSize * 0.95 : 0);
      _lineTops.add(y);
      _lineHeights.add(h);
      y += h;
    }
    // 每行一个缩放弹簧（欠阻尼，换行时有回弹）
    while (_lineScales.length < widget.lines.length) {
      _lineScales.add(_Spring(
        mass: 2,
        stiffness: 100,
        damping: 25,
        initial: _inactiveScale,
      ));
    }
    if (_lineScales.length > widget.lines.length) {
      _lineScales.removeRange(widget.lines.length, _lineScales.length);
    }
    _posY.setPosition(_posY.position, 0);
  }

  double _topOf(int i) => i < _lineTops.length ? _lineTops[i] : 0.0;
  double _heightOf(int i) => i < _lineHeights.length ? _lineHeights[i] : _lineHeight;

  /// 当前行锚定目标：使该行中心落在视口 35% 高度
  double _targetY(int index) {
    if (index < 0) return 0;
    return -(_topOf(index) + _heightOf(index) / 2 - _viewportH * _alignPosition);
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed.inMicroseconds / 1e6).clamp(0.0, 0.05);

    // 1) 同步当前行
    final pos = widget.position;
    if (pos != _lastPos) {
      _lastPos = pos;
      _currentIndex = _findIndex(pos);
      if (!_userScrolling) {
        _posY.setTarget(_targetY(_currentIndex));
      }
      // 自动回位计时
      if (_userScrolling && _autoReturnMs <= 0) {
        _autoReturnMs = 3000;
      }
    }

    // 2) 用户松手后 3s 自动回位
    if (_userScrolling && _autoReturnMs > 0) {
      _autoReturnMs -= (dt * 1000).round();
      if (_autoReturnMs <= 0) {
        _userScrolling = false;
        _posY.setTarget(_targetY(_currentIndex));
      }
    }

    // 3) 推进弹簧
    _posY.step(dt);
    for (int i = 0; i < _lineScales.length; i++) {
      _lineScales[i].setTarget(i == _currentIndex ? 1.0 : _inactiveScale);
      _lineScales[i].step(dt);
    }

    _frame.value++;
  }

  int _findIndex(Duration pos) {
    var idx = -1;
    for (int i = widget.lines.length - 1; i >= 0; i--) {
      if (pos >= widget.lines[i].time) {
        idx = i;
        break;
      }
    }
    return idx;
  }

  // ---------------- 手势 ----------------

  void _onDragUpdate(DragUpdateDetails d) {
    _userScrolling = true;
    _autoReturnMs = 3000;
    _dragTotal += d.primaryDelta ?? 0;
    _posY.setPosition(_posY.position + (d.primaryDelta ?? 0), _posY.velocity);
  }

  void _onDragEnd(DragEndDetails d) {
    // 惯性：velocity × 0.3s，钳制 ±300px（AMLL 标准）
    final v = d.velocity.pixelsPerSecond.dy;
    final inertia = (v * 0.3).clamp(-300.0, 300.0);
    if (inertia.abs() > 5) {
      final cur = _posY.position;
      _posY.setPosition(cur, v);
      _posY.setTarget(cur + inertia);
    }
  }

  void _onTapUp(TapUpDetails d) {
    if (_dragTotal.abs() > 10) {
      _dragTotal = 0;
      return; // 是滑动不是点击
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
    // 反解：p.y = top + height/2 + posY
    final contentY = p.dy - _posY.position;
    for (int i = widget.lines.length - 1; i >= 0; i--) {
      if (contentY >= _topOf(i) - _lineHeight * 0.5) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportW = constraints.maxWidth;
        _viewportH = constraints.maxHeight;
        // 首次布局后对齐当前行
        if (_lineScales.isNotEmpty && _posY.position == 0 && _currentIndex >= 0) {
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
            // 上下 24px alpha 渐隐
            shaderCallback: (bounds) {
              final r = (24.0 / bounds.height).clamp(0.0, 0.5);
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
                    viewportW: _viewportW,
                    fontSize: _fontSize,
                    leftPadding: _fontSize * _leftPaddingEm,
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

/// 解析解阻尼谐振子（临界/欠阻尼/过阻尼三态）
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
  double get target => _target;

  void setTarget(double t) => _target = t;
  void setPosition(double x, double v) {
    _x = x;
    _v = v;
  }

  void step(double dt) {
    if (dt <= 0) return;
    // 半隐式欧拉，固定子步长保证稳定
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
  final double viewportH, viewportW, fontSize, leftPadding;
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
    required this.leftPadding,
    required this.inactiveScale,
    required this.maxLiftPx,
    required this.overscan,
  });

  /// 关键：全白文字，只用 alpha 表达层次
  /// dark  = factor*0.2 + 0.2  → 0.2 ~ 0.4
  /// bright= factor*0.8 + 0.2  → 0.2 ~ 1.0
  double _darkFor(double scale) {
    final f = ((scale - inactiveScale) / (1.0 - inactiveScale)).clamp(0.0, 1.0);
    return f * 0.2 + 0.2;
  }

  double _brightFor(double scale) {
    final f = ((scale - inactiveScale) / (1.0 - inactiveScale)).clamp(0.0, 1.0);
    return f * 0.8 + 0.2;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (lines.isEmpty) return;
    final paint = Paint();
    final tp = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < lines.length; i++) {
      final lineH = heightOf(i);
      final y = topOf(i) + posY;
      // 视口外剔除
      if (y + lineH < -overscan) continue;
      if (y > viewportH + overscan) break;

      final isActive = i == currentIndex;
      final scale = i < scales.length ? scales[i].position : inactiveScale;
      final pivotY = y + lineH / 2;

      // 非当前行：按行距分级模糊（σ = 1 + |Δline|，上限 10）
      if (!isActive) {
        final dist = (i - currentIndex).abs();
        final sigma = (1.0 + dist).clamp(0.5, 10.0);
        final rect = Rect.fromLTRB(0, y - sigma * 2, viewportW, y + lineH + sigma * 2);
        canvas.saveLayer(
          rect,
          Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        );
      }

      canvas.save();
      canvas.translate(leftPadding, pivotY);
      canvas.scale(scale, scale);
      canvas.translate(-leftPadding, -pivotY);

      _paintLine(
        canvas: canvas,
        tp: tp,
        paint: paint,
        line: lines[i],
        y: y,
        isActive: isActive,
        scale: scale,
      );

      canvas.restore();

      if (!isActive) canvas.restore(); // saveLayer
    }
  }

  void _paintLine({
    required Canvas canvas,
    required TextPainter tp,
    required Paint paint,
    required LyricLine line,
    required double y,
    required bool isActive,
    required double scale,
  }) {
    final dark = _darkFor(scale);
    final bright = _brightFor(scale);
    final maxW = viewportW - leftPadding - fontSize * 0.5;

    // 翻译行只在当前行显示（0.7em / alpha 0.5）
    final hasTrans = line.translation != null && line.translation!.isNotEmpty;
    final transSize = math.max(fontSize * 0.7, 12.0);

    if (isActive && line.hasWords) {
      _paintWordByWord(canvas, line, y, maxW, dark, bright);
    } else {
      // 整行模式
      final alpha = isActive ? bright : dark;
      tp.text = TextSpan(
        text: line.text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: alpha),
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      );
      tp.layout(maxWidth: maxW);
      tp.paint(canvas, Offset(leftPadding, y + (fontSize * 1.35 - fontSize) / 2));
    }

    if (hasTrans && isActive) {
      tp.text = TextSpan(
        text: line.translation!,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: transSize,
          fontWeight: FontWeight.w400,
          height: 1.5,
        ),
      );
      tp.layout(maxWidth: maxW);
      tp.paint(canvas, Offset(leftPadding, y + fontSize * 1.5));
    }
  }

  /// 逐字歌词：连续 alpha 播放头 + 软过渡带
  ///
  /// maskX = 已完成字累计宽度 + 当前字内进度 × 当前字宽
  /// 过渡带半宽固定为**行内平均字宽**（若用当前字宽会在字切换时闪烁）
  void _paintWordByWord(
    Canvas canvas,
    LyricLine line,
    double y,
    double maxW,
    double dark,
    double bright,
  ) {
    final words = line.words!;
    if (words.isEmpty) return;

    // 量出每个字的宽度与起始 X
    final tp = TextPainter(textDirection: TextDirection.ltr);
    final widths = <double>[];
    final starts = <double>[];
    var x = 0.0;
    for (final w in words) {
      tp.text = TextSpan(
        text: w.text,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      );
      tp.layout();
      starts.add(x);
      widths.add(tp.width);
      x += tp.width;
    }

    // 播放头位置
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
      maskX = double.infinity; // 全部唱完
    } else if (curIdx < 0) {
      maskX = -1.0; // 未开始
    } else {
      maskX = starts[curIdx] + widths[curIdx] * intra;
    }

    // 过渡带半宽 = 行内平均字宽
    final meanW = widths.isEmpty ? 0.0 : widths.reduce((a, b) => a + b) / widths.length;
    final halfBand = meanW;

    // 每个字按播放头采样左右端 alpha，用渐变填充 → 平滑扫过
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
        final e = intra * intra * (3 - 2 * intra); // smoothstep
        liftY = maxLiftPx * e;
      }

      final rect = Rect.fromLTWH(sx, y + liftY, sw, fontSize * 1.35);
      // 用渐变做前景色，实现字内平滑过渡
      final shader = ui.Gradient.linear(
        Offset(rect.left, 0),
        Offset(rect.right, 0),
        [
          Colors.white.withValues(alpha: aL),
          Colors.white.withValues(alpha: aR),
        ],
      );
      tp.text = TextSpan(
        text: w.text,
        style: TextStyle(
          foreground: Paint()..shader = shader,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(leftPadding + sx, y + liftY + (fontSize * 1.35 - fontSize) / 2));
    }
  }

  /// X 坐标处的 alpha（播放头软带核心）
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
