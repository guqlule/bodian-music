import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../services/lyric/lyric_parser.dart';
import 'lyric_effect_config.dart';

/// JIZURA 风格特效歌词
///
/// 参考 852wa/JIZURA（ScriptUI 歌词特效脚本）的视觉语言。
/// 与常规「滚动歌词列表」的根本差异：**没有上下句滚动，只有当前一句**，
/// 巨号铺满全屏，配色差错位 / 逐字波浪 / 弹跳入场等特效。
///
/// 效果可通过 [LyricEffectConfig] 切换（设置里选，或页面右上角菜单）。
class JizuraLyricsView extends StatefulWidget {
  final List<LyricLine> lines;
  final Duration position;
  final LyricEffectConfig config;
  final ValueChanged<Duration> onSeek;

  const JizuraLyricsView({
    super.key,
    required this.lines,
    required this.position,
    required this.config,
    required this.onSeek,
  });

  @override
  State<JizuraLyricsView> createState() => _JizuraLyricsViewState();
}

class _JizuraLyricsViewState extends State<JizuraLyricsView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  int _index = -1;
  Duration _lastPos = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final pos = widget.position;
    if (pos != _lastPos) {
      _lastPos = pos;
      final idx = _findIndex(pos);
      if (idx != _index) setState(() => _index = idx);
    }
    _frame.value++;
  }

  int _findIndex(Duration pos) {
    for (int i = widget.lines.length - 1; i >= 0; i--) {
      if (pos >= widget.lines[i].time) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.config.palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_index >= 0) widget.onSeek(widget.lines[_index].time);
      },
      child: ColoredBox(
        color: pal.bg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.1),
                  radius: 1.1,
                  colors: [pal.fg.withValues(alpha: 0.05), Colors.transparent],
                ),
              ),
            ),
            ValueListenableBuilder<int>(
              valueListenable: _frame,
              builder: (context, _, __) => CustomPaint(
                painter: _JizuraPainter(
                  lines: widget.lines,
                  index: _index,
                  position: widget.position,
                  config: widget.config,
                ),
                size: Size.infinite,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// JIZURA 风格绘制器
class _JizuraPainter extends CustomPainter {
  final List<LyricLine> lines;
  final int index;
  final Duration position;
  final LyricEffectConfig config;

  _JizuraPainter({
    required this.lines,
    required this.index,
    required this.position,
    required this.config,
  });

  // ---------------- JIZURA 缓动 ----------------
  static double _cl(double x) => x.clamp(0.0, 1.0);
  static double _oc(double x) => 1 - math.pow(1 - _cl(x), 3).toDouble();
  static double _ocubic(double x) => x * x * x;
  static double _iq(double x) => x * x;
  static double _outBack(double x, double s) {
    final v = _cl(x);
    final c = s + 1;
    return 1 + c * math.pow(v - 1, 3) + s * math.pow(v - 1, 2).toDouble();
  }
  static double _outExpo(double x) {
    final v = _cl(x);
    return v >= 1 ? 1 : 1 - math.pow(2, -10 * v).toDouble();
  }
  static double _inOutExpo(double x) {
    final v = _cl(x);
    if (v <= 0 || v >= 1) return v;
    return v < 0.5
        ? math.pow(2, 20 * v - 10).toDouble() / 2
        : (2 - math.pow(2, -20 * v + 10).toDouble()) / 2;
  }
  static double _hash(int n) {
    final x = math.sin(n * 127.1 + 311.7) * 43758.5453;
    return x - x.floor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pal = config.palette;
    if (lines.isEmpty || index < 0 || index >= lines.length) {
      _drawIdle(canvas, size);
      return;
    }
    final line = lines[index];
    if (line.text.trim().isEmpty || line.text == '\u00A0') {
      _drawIdle(canvas, size);
      return;
    }

    // 时间轴
    final dur = _lineDuration(index);
    final lineStart = line.time;
    final t = ((position - lineStart).inMilliseconds / 1000.0).clamp(0.0, dur);
    final inDur = (dur * 0.36).clamp(0.12, 0.6);
    final outDur = config.exit == LyricExit.none
        ? 0.0
        : (dur * 0.3).clamp(0.14, 0.55);
    final outStart = dur - outDur;

    final enter = _cl(t / inDur);
    final exit = outDur > 0.002 ? _cl((t - outStart) / outDur) : 0.0;
    // hold 强度：入场 85% 后 0.25s 升到 1，出场衰减
    final amt = _cl((t - inDur * 0.85) / 0.25) * (1 - exit);

    final seed = _hash(index * 37 + 11);
    final u = size.height / 1080.0;

    // 字重生长：前半段 cubic-out
    final weightK = 1 - math.pow(1 - _cl(t / (dur * 0.5)), 3).toDouble();

    final layout = _layout(line.text, size);

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);

    // ---- 入场变换 ----
    final xf = _entranceTransform(config.entrance, enter, seed, layout.size);
    canvas.translate(xf.dx, xf.dy);
    if (xf.rot != 0) canvas.rotate(xf.rot);
    canvas.scale(xf.scale, xf.scaleY);

    // ---- 出场变换 ----
    final xo = _exitTransform(config.exit, exit, seed);
    canvas.translate(xo.dx, xo.dy);
    canvas.scale(xo.scale, xo.scale);
    if (xo.rot != 0) canvas.rotate(xo.rot);

    final globalAlpha = (xo.alpha).clamp(0.0, 1.0);
    if (globalAlpha <= 0.003) {
      canvas.restore();
      return;
    }

    // ---- 色差错位（ghost）----
    final chromaBase = config.treat == LyricTreat.chroma ? 1.5 : 0.7;
    final chroma = chromaBase * (1.0 + amt * 0.25);
    if (config.treat != LyricTreat.outline) {
      _pass(canvas, layout, pal.accent.withValues(alpha: globalAlpha * 0.85),
          Offset(3.2 * chroma * u, 1.9 * chroma * u), weightK, amt, t, false);
      _pass(canvas, layout, pal.accent2.withValues(alpha: globalAlpha * 0.85),
          Offset(-3.4 * chroma * u, -1.3 * chroma * u), weightK, amt, t, false);
    }

    // ---- 主层 ----
    _pass(canvas, layout, pal.fg.withValues(alpha: globalAlpha), Offset.zero,
        weightK, amt, t, true);

    canvas.restore();

    // ---- 翻译行 ----
    final tr = line.translation;
    if (tr != null && tr.isNotEmpty && exit < 0.4) {
      final trAlpha = (1 - exit) * (0.4 + amt * 0.3);
      final tp = TextPainter(textDirection: TextDirection.ltr);
      tp.text = TextSpan(
        text: tr,
        style: TextStyle(
          color: pal.sub.withValues(alpha: trAlpha),
          fontSize: (layout.size * 0.16).clamp(11.0, 20.0),
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
      );
      tp.layout(maxWidth: size.width * 0.8);
      tp.paint(
        canvas,
        Offset((size.width - tp.width) / 2, size.height / 2 + layout.size * 0.62),
      );
    }
  }

// ---------------- 时长 ----------------
  double _lineDuration(int i) {
    final end = (i + 1 < lines.length)
        ? lines[i + 1].time
        : lines[i].time + const Duration(seconds: 4);
    final d = end - lines[i].time;
    return d.inMilliseconds <= 0 ? 4.0 : d.inMilliseconds / 1000.0;
  }

  // ---------------- 入场 ----------------
  ({double dx, double dy, double scale, double scaleY, double rot})
      _entranceTransform(LyricEntrance e, double p, double seed, double fontSize) {
    final motion = config.motion;
    switch (e) {
      case LyricEntrance.pop:
        return (
          dx: 0,
          dy: 0,
          scale: _outBack(p, 2.6),
          scaleY: _outBack(p, 2.6),
          rot: (seed > 0.5 ? 1 : -1) * (1 - _oc(p)) * 28.0 * math.pi / 180.0
        );
      case LyricEntrance.spin:
        return (
          dx: 0,
          dy: 0,
          scale: 0.15 + 0.85 * _outExpo(p),
          scaleY: 0.15 + 0.85 * _outExpo(p),
          rot: (seed > 0.5 ? 1 : -1) * (1 - _outExpo(p)) * 200.0 * math.pi / 180.0
        );
      case LyricEntrance.drop:
        return (
          dx: 0,
          dy: (1 - Curves.bounceOut.transform(p)) * fontSize * 2.4 * motion,
          scale: 0.8 + 0.2 * p,
          scaleY: 1 + (1 - _oc(p)) * 0.5,
          rot: 0
        );
      case LyricEntrance.type:
        // 打字由 _pass 内部按字显现处理，这里给一个轻微放大
        return (dx: 0, dy: 0, scale: 0.96 + 0.04 * p, scaleY: 1, rot: 0);
      case LyricEntrance.zoom:
        return (
          dx: 0,
          dy: 0,
          scale: 1.7 - 0.7 * _outExpo(p),
          scaleY: 1.7 - 0.7 * _outExpo(p),
          rot: 0
        );
      case LyricEntrance.blur:
        return (
          dx: 0,
          dy: 0,
          scale: 1.08 - 0.08 * _oc(p),
          scaleY: 1.08 - 0.08 * _oc(p),
          rot: 0
        );
      case LyricEntrance.wipe:
        return (
          dx: -(fontSize * 6) * (1 - _inOutExpo(p)),
          dy: 0,
          scale: 1.0,
          scaleY: 1.0,
          rot: 0
        );
    }
  }

  // ---------------- 出场 ----------------
  ({double dx, double dy, double scale, double rot, double alpha})
      _exitTransform(LyricExit e, double p, double seed) {
    switch (e) {
      case LyricExit.none:
        return (dx: 0, dy: 0, scale: 1, rot: 0, alpha: 1);
      case LyricExit.shrink:
        return (
          dx: 0,
          dy: 0,
          scale: 1 - 0.96 * _ocubic(p),
          rot: 0,
          alpha: 1 - _ocubic(p) * _ocubic(p)
        );
      case LyricExit.explode:
        final dir = seed > 0.5 ? 1.0 : -1.0;
        return (
          dx: dir * _oc(p) * 260 * config.motion,
          dy: -_oc(p) * 160 * config.motion,
          scale: 1 + _oc(p) * 0.4,
          rot: _oc(p) * 120.0 * math.pi / 180.0,
          alpha: 1 - _oc(p)
        );
      case LyricExit.blurOut:
        return (dx: 0, dy: 0, scale: 1, rot: 0, alpha: 1 - _iq(p));
      case LyricExit.wipeOut:
        return (
          dx: _inOutExpo(p) * 320,
          dy: 0,
          scale: 1,
          rot: 0,
          alpha: 1 - _oc(p)
        );
    }
  }

  // ---------------- 版式 ----------------
  _Layout _layout(String text, Size size) {
    final clean = text.replaceAll('\u00A0', '').trim();
    if (clean.isEmpty) return _Layout(const [], 48, const []);

    if (config.layout == LyricLayout.vertical) {
      return _layoutVertical(clean, size);
    }

    final W = size.width;
    final H = size.height;
    final n = clean.characters.length;

    // 基准字号
    double baseFs;
    switch (config.layout) {
      case LyricLayout.huge:
        baseFs = math.min(H * 0.98, W * 1.3 / (n * 0.96));
        break;
      case LyricLayout.center:
        baseFs = math.min(H * 0.33, W * 0.84 / (n * 0.7));
        break;
      case LyricLayout.stack:
      case LyricLayout.marquee:
      case LyricLayout.tile:
        baseFs = math.min(H * 0.30, W * 0.80 / (n * 0.72));
        break;
      default:
        baseFs = math.min(H * 0.5, W * 0.9 / n);
    }
    baseFs = baseFs.clamp(18.0, 190.0);

    final tp = TextPainter(textDirection: TextDirection.ltr);
    Style mk(double fs) => TextStyle(
          fontSize: fs,
          fontWeight: FontWeight.w900,
          height: 1.05,
          letterSpacing: -0.02 * fs,
        );

    // 决定是否折行
    var segs = <String>[clean];
    tp.text = TextSpan(text: clean, style: mk(baseFs));
    tp.layout();
    if (tp.width > W * 0.88) {
      final k = (W * 0.88) / math.max(tp.width, 1.0);
      if (k > 0.34) {
        baseFs *= k;
      } else if (clean.length > 8) {
        baseFs = math.min(baseFs * k, W / 4.2);
        final mid = (clean.length / 2).ceil();
        segs = [clean.substring(0, mid), clean.substring(mid)];
      }
    }

    // 逐字排版
    final lines = <List<_Glyph>>[];
    var y = 0.0;
    for (final seg in segs) {
      final st = mk(baseFs);
      tp.text = TextSpan(text: seg, style: st);
      tp.layout();
      double x = -tp.width / 2;
      final row = <_Glyph>[];
      var gi = 0;
      for (final ch in seg.characters) {
        tp.text = TextSpan(text: ch, style: st);
        tp.layout();
        row.add(_Glyph(ch, x, y, tp.width, baseFs, gi++));
        x += tp.width;
      }
      lines.add(row);
      y += baseFs * 1.1;
    }
    final totalH = y - baseFs * 0.1;
    for (final row in lines) {
      for (final g in row) {
        g.y += -totalH / 2;
      }
    }

    return _Layout(lines.expand((e) => e).toList(), baseFs, lines);
  }

  /// 竖排：单字从上到下
  _Layout _layoutVertical(String text, Size size) {
    final W = size.width;
    final H = size.height;
    final chars = text.characters.toList();
    final n = chars.length;
    final fs = math.min(H * 0.82 / n, W * 0.5).clamp(16.0, 120.0);
    final tp = TextPainter(textDirection: TextDirection.ltr);
    final st = TextStyle(fontSize: fs, fontWeight: FontWeight.w900, height: 1.0);
    final glyphs = <_Glyph>[];
    var y = -fs * n / 2;
    var gi = 0;
    for (final ch in chars) {
      tp.text = TextSpan(text: ch, style: st);
      tp.layout();
      glyphs.add(_Glyph(ch, -tp.width / 2, y, tp.width, fs, gi++));
      y += fs * 1.12;
    }
    return _Layout(glyphs, fs, [glyphs]);
  }

  // ---------------- 绘制一层 ----------------
  void _pass(
    Canvas canvas,
    _Layout layout,
    Color color,
    Offset offset,
    double weightK,
    double amt,
    double t,
    bool isMain,
  ) {
    if (layout.glyphs.isEmpty) return;
    final pal = config.palette;
    final treat = config.treat;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    final motion = config.motion;

    canvas.save();
    canvas.translate(offset.dx, offset.dy);

    // 打字机：按进度逐字显现
    final typeCut = treat == LyricTreat.none && config.entrance == LyricEntrance.type;
    final shown = typeCut
        ? (layout.glyphs.length * _cl((t - 0.05) / 0.5)).floor()
        : layout.glyphs.length;

    for (int gi = 0; gi < shown; gi++) {
      final g = layout.glyphs[gi];

// 逐字波浪（hold 决定形态）
      double dy = 0, dx = 0, sc = 1.0;
      switch (config.hold) {
        case LyricHold.wave:
          dy = math.sin(t * 7 + g.i * 0.75) * g.fs * 0.07 * amt * motion;
          break;
        case LyricHold.breathe:
          sc = 1 + 0.035 * math.sin(t * math.pi * 1.8) * amt * motion;
          break;
        case LyricHold.jitter:
          final h = _hash(gi * 13 + t.toInt() * 7);
          dx = (h - 0.5) * g.fs * 0.05 * amt * motion;
          dy = (_hash(gi * 29 + t.toInt() * 11) - 0.5) * g.fs * 0.05 * amt * motion;
          break;
        case LyricHold.drift:
          dx = (1 - 0.5) * 0;
          dx = math.sin(t * 0.8) * g.fs * 0.25 * amt * motion;
          sc = 1 + 0.05 * amt * motion;
          break;
        case LyricHold.still:
          break;
      }

      // 高亮特效：已唱部分渐变到强调色（逐字扫过）
      var glyphColor = color;
      if (isMain && treat == LyricTreat.marker) {
        final w = _wordProgressFraction(g);
        glyphColor = Color.lerp(color, pal.accent, w)!;
      }

      // 文本特效
      TextStyle st;
      switch (treat) {
        case LyricTreat.outline:
          st = TextStyle(
            fontSize: g.fs,
            fontWeight: FontWeight.w900,
            height: 1.0,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(1.6, g.fs * 0.028)
              ..strokeJoin = StrokeJoin.round
              ..color = color,
          );
          break;
        case LyricTreat.strokeFill:
          st = TextStyle(
            fontSize: g.fs,
            fontWeight: FontWeight.w900,
            height: 1.0,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(3.0, g.fs * 0.10)
              ..strokeJoin = StrokeJoin.round
              ..color = pal.accent,
            shadows: null,
          );
          // 描边层 + 内部填充层（两次绘制见下方 weightK 分支外的处理）
          break;
        case LyricTreat.neon:
          st = TextStyle(
            fontSize: g.fs,
            fontWeight: FontWeight.w900,
            height: 1.0,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(1.4, g.fs * 0.026)
              ..strokeJoin = StrokeJoin.round
              ..color = Color.lerp(color, Colors.white, 0.4)!,
            shadows: [
              Shadow(color: pal.accent.withValues(alpha: 0.8), blurRadius: 10),
              Shadow(color: pal.accent2.withValues(alpha: 0.6), blurRadius: 24),
            ],
          );
          break;
        case LyricTreat.gradient:
          final top = Color.lerp(color, pal.accent, 0.35)!;
          st = TextStyle(
            fontSize: g.fs,
            fontWeight: FontWeight.w900,
            height: 1.0,
            foreground: Paint()
              ..shader = ui.Gradient.linear(
                Offset(0, -g.fs * 0.5),
                Offset(0, g.fs * 0.5),
                [top, color],
              ),
          );
          break;
        case LyricTreat.glow:
          st = TextStyle(
            fontSize: g.fs,
            fontWeight: FontWeight.w900,
            height: 1.0,
            color: color,
            shadows: isMain
                ? [
                    Shadow(
                      color: pal.accent.withValues(alpha: 0.55 * (0.5 + amt * 0.5)),
                      blurRadius: 16 + weightK * 14,
                    ),
                    Shadow(
                      color: pal.accent2.withValues(alpha: 0.30 * (0.5 + amt * 0.5)),
                      blurRadius: 32 + weightK * 20,
                    ),
                  ]
                : null,
          );
          break;
        case LyricTreat.chroma:
        case LyricTreat.marker:
          st = TextStyle(
            fontSize: g.fs,
            fontWeight: FontWeight.w900,
            height: 1.0,
            color: glyphColor,
            shadows: isMain && treat == LyricTreat.chroma
                ? [Shadow(color: glyphColor.withValues(alpha: 0.5), blurRadius: 0)]
                : null,
          );
          break;
        case LyricTreat.none:
          st = TextStyle(
            fontSize: g.fs,
            fontWeight: FontWeight.w900,
            height: 1.0,
            color: glyphColor,
          );
      }

      // 字重生长：描边加粗（仅主层）
      if (isMain && weightK > 0.02 && treat != LyricTreat.outline && treat != LyricTreat.neon) {
        st = st.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = weightK * g.fs * 0.05
            ..strokeJoin = StrokeJoin.round
            ..color = color,
          color: null,
          shadows: st.shadows,
        );
        tp.text = TextSpan(text: g.ch, style: st);
        tp.layout();
        tp.paint(canvas, Offset(g.x + dx, g.y + dy));
        // 再叠一次实心，得到加粗效果
        final st2 = TextStyle(
          fontSize: g.fs,
          fontWeight: FontWeight.w900,
          height: 1.0,
          color: treat == LyricTreat.gradient ? null : color,
          foreground: treat == LyricTreat.gradient ? st.foreground : null,
          shadows: st.shadows,
        );
        tp.text = TextSpan(text: g.ch, style: st2);
        tp.layout();
        tp.paint(canvas, Offset(g.x + dx, g.y + dy));
        continue;
      }

      final p = Offset(g.x + dx, g.y + dy);

      // 描边填充（强调色粗描边 + 白字填充）需要两层绘制
      if (treat == LyricTreat.strokeFill && isMain) {
        tp.text = TextSpan(text: g.ch, style: st); // st 是 accent 描边层
        tp.layout();
        tp.paint(canvas, p);
        final fillStyle = TextStyle(
          fontSize: g.fs,
          fontWeight: FontWeight.w900,
          height: 1.0,
          color: color,
        );
        tp.text = TextSpan(text: g.ch, style: fillStyle);
        tp.layout();
        tp.paint(canvas, p);
        continue;
      }

      if (sc != 1.0) {
        canvas.save();
        canvas.translate(p.dx + g.w / 2, p.dy);
        canvas.scale(sc, sc);
        canvas.translate(-g.w / 2, 0);
        tp.text = TextSpan(text: g.ch, style: st);
        tp.layout();
        tp.paint(canvas, Offset(-tp.width / 2, 0));
        canvas.restore();
      } else {
        tp.text = TextSpan(text: g.ch, style: st);
        tp.layout();
        tp.paint(canvas, p);
      }
    }

    canvas.restore();
  }

  /// 该字在整句中的横向完成比例（0~1），用于高亮特效
  double _wordProgressFraction(_Glyph g) {
    if (index < 0 || index >= lines.length) return 0;
    final line = lines[index];
    if (!line.hasWords || g.i >= line.words!.length) return 0;
    final w = line.words![g.i];
    final d = w.duration ?? const Duration(milliseconds: 400);
    if (d.inMilliseconds <= 0) return position >= w.time ? 1 : 0;
    return ((position - w.time).inMilliseconds / d.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  void _drawIdle(Canvas canvas, Size size) {
    final tp = TextPainter(textDirection: TextDirection.ltr);
    tp.text = TextSpan(
      text: '暂无歌词',
      style: TextStyle(
        color: config.palette.sub.withValues(alpha: 0.35),
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 4,
      ),
    );
    tp.layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, size.height / 2));
  }

  @override
  bool shouldRepaint(covariant _JizuraPainter old) => true;
}

typedef Style = TextStyle;

class _Glyph {
  final String ch;
  double x, y;
  final double w, fs;
  final int i;
  _Glyph(this.ch, this.x, this.y, this.w, this.fs, this.i);
}

class _Layout {
  final List<_Glyph> glyphs;
  final double size;
  final List<List<_Glyph>> rows;
  _Layout(this.glyphs, this.size, this.rows);
}
