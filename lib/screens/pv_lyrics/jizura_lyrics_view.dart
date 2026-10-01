import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../services/lyric/lyric_parser.dart';

/// JIZURA 风格特效歌词
///
/// 参考 852wa/JIZURA（ScriptUI 歌词特效脚本）的视觉语言重写。
/// 与常规「滚动歌词列表」的根本差异：
///
///   **没有上下句、没有滚动列表。屏幕上只有当前一句，且铺满全屏。**
///
/// 签名特效：
/// 1. 色差错位（chromatic ghost）：同一句话额外画两遍，
///    琥珀色偏移 (+3.2, +1.9)*u、青色偏移 (-3.4, -1.3)*u
/// 2. 逐字波浪：dy = sin(t*7 + i*0.75) * size * 0.07
/// 3. 弹跳入场：缩放 0→1 过冲 2.6，同时倾斜 ±28° 回正
/// 4. 字重生长：前半个 cut 从细到粗（cubic-out）
/// 5. 巨号排版：单行铺满 98% 屏高
class JizuraLyricsView extends StatefulWidget {
  final List<LyricLine> lines;
  final Duration position;
  final ValueChanged<Duration> onSeek;

  const JizuraLyricsView({
    super.key,
    required this.lines,
    required this.position,
    required this.onSeek,
  });

  @override
  State<JizuraLyricsView> createState() => _JizuraLyricsViewState();
}

class _JizuraLyricsViewState extends State<JizuraLyricsView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  // JIZURA noir 配色
  static const _bg = Color(0xFF060607);
  static const _fg = Color(0xFFF5EEEA);
  static const _accent = Color(0xFFF5A50C); // 琥珀 ghost
  static const _accent2 = Color(0xFF16F4D4); // 青 ghost
  static const _sub = Color(0xFFBDB6B2);

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
      _index = _findIndex(pos);
    }
    _frame.value++;
  }

  int _findIndex(Duration pos) {
    for (int i = widget.lines.length - 1; i >= 0; i--) {
      if (pos >= widget.lines[i].time) return i;
    }
    return -1;
  }

  /// 当前行的时间进度 0~1，以及距该行开始的秒数
  double _progressOf(int i) {
    final lines = widget.lines;
    final line = lines[i];
    final end = (i + 1 < lines.length)
        ? lines[i + 1].time
        : line.time + const Duration(seconds: 4);
    final total = end - line.time;
    if (total.inMilliseconds <= 0) return 1.0;
    final e = widget.position - line.time;
    if (e.isNegative) return 0.0;
    return (e.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_index >= 0) widget.onSeek(widget.lines[_index].time);
      },
      child: ColoredBox(
        color: _bg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 极淡的中心径向提亮，避免纯黑死板
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.1),
                  radius: 1.1,
                  colors: [Color(0x0DFFFFFF), Color(0x00000000)],
                ),
              ),
            ),
            ValueListenableBuilder<int>(
              valueListenable: _frame,
              builder: (context, _, __) => CustomPaint(
                painter: _JizuraPainter(
                  lines: widget.lines,
                  index: _index,
                  progressOf: _progressOf,
                  fg: _fg,
                  accent: _accent,
                  accent2: _accent2,
                  sub: _sub,
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
  final double Function(int) progressOf;
  final Color fg, accent, accent2, sub;

  _JizuraPainter({
    required this.lines,
    required this.index,
    required this.progressOf,
    required this.fg,
    required this.accent,
    required this.accent2,
    required this.sub,
  });

  // ---- JIZURA 缓动函数 ----
  static double _cl(double x) => x.clamp(0.0, 1.0);
  static double _oc(double x) {
    final v = _cl(x);
    return 1 - math.pow(1 - v, 3).toDouble();
  }
  static double _ocubic(double x) => x * x * x;
  static double _outBack(double x, double s) {
    final v = _cl(x);
    final c = s + 1;
    return 1 + c * math.pow(v - 1, 3) + s * math.pow(v - 1, 2).toDouble();
  }
  /// JIZURA 的确定性哈希，用于每行随机种子
  static double _hash(int n) {
    final x = math.sin(n * 127.1 + 311.7) * 43758.5453;
    return x - x.floor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (lines.isEmpty || index < 0 || index >= lines.length) {
      _drawIdle(canvas, size);
      return;
    }

    final line = lines[index];
    if (line.text.trim().isEmpty || line.text == '\u00A0') {
      _drawIdle(canvas, size);
      return;
    }

    final p = progressOf(index); // 0~1
    // 时长估计：取进度反推（用于入场/出场时长）
    final dur = _lineDuration(index);
    final t = p * dur; // 当前行已过秒数

    // JIZURA 时长公式：inDur = clamp(dur*0.36, 0.12, 0.6)
    final inDur = (dur * 0.36).clamp(0.12, 0.6);
    final outDur = (dur * 0.3).clamp(0.14, 0.55);
    final outStart = dur - outDur;

    final enter = _cl(t / inDur);
    final exit = outDur > 0.002 ? _cl((t - outStart) / outDur) : 0.0;
    // hold 强度：入场结束后 0.25s 内升到 1，出场时衰减
    final amt = _cl((t - inDur * 0.85) / 0.25) * (1 - exit);

    // 每行种子（决定倾斜方向、色差强度等）
    final seed = _hash(index * 37 + 11);
    final u = size.height / 1080.0; // 设计尺寸缩放

    // 布局
    final layout = _layout(line.text, size);
    final fontSize = layout.size;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);

    // 出场：缩小 + 淡出
    final exitScale = 1.0 - _ocubic(exit) * 0.55;
    canvas.scale(exitScale, exitScale);
    final globalAlpha = (1 - _oc(exit)).clamp(0.0, 1.0);
    if (globalAlpha <= 0.002) {
      canvas.restore();
      return;
    }

    // 入场：弹跳缩放 + 倾斜
    final popScale = _outBack(enter, 2.6);
    final tiltDeg = (seed > 0.5 ? 1 : -1) * (1 - _oc(enter)) * 28.0;
    final rot = tiltDeg * math.pi / 180.0;

    // 字重生长：前半段 cubic-out，用描边宽度模拟「变粗」
    final weightK = 1 - math.pow(1 - _cl(t / (dur * 0.5)), 3).toDouble();

    // ---- 色差错位：先画两个 ghost，再画主层 ----
    // ghost A（琥珀）偏移 (+3.2, +1.9)*u
    // ghost B（青）   偏移 (-3.4, -1.3)*u
    final chroma = 0.7 * (1.0 + amt * 0.25);
    _drawPhrase(
      canvas: canvas,
      glyphs: layout.glyphs,
      fontSize: fontSize,
      scale: popScale,
      rot: rot,
      color: accent.withValues(alpha: globalAlpha * 0.85),
      offset: Offset(3.2 * chroma * u, 1.9 * chroma * u),
      amt: amt,
      time: t,
      index: index,
      weightK: weightK,
      blurPx: 0,
    );
    _drawPhrase(
      canvas: canvas,
      glyphs: layout.glyphs,
      fontSize: fontSize,
      scale: popScale,
      rot: rot,
      color: accent2.withValues(alpha: globalAlpha * 0.85),
      offset: Offset(-3.4 * chroma * u, -1.3 * chroma * u),
      amt: amt,
      time: t,
      index: index,
      weightK: weightK,
      blurPx: 0,
    );

    // 主层
    _drawPhrase(
      canvas: canvas,
      glyphs: layout.glyphs,
      fontSize: fontSize,
      scale: popScale,
      rot: rot,
      color: fg.withValues(alpha: globalAlpha),
      offset: Offset.zero,
      amt: amt,
      time: t,
      index: index,
      weightK: weightK,
      blurPx: 0,
      glow: true,
    );

    canvas.restore();

    // 翻译行：小字，挂在主句下方
    final tr = line.translation;
    if (tr != null && tr.isNotEmpty && exit < 0.5) {
      final trAlpha = (1 - exit) * (0.35 + amt * 0.35);
      final tp = TextPainter(textDirection: TextDirection.ltr);
      tp.text = TextSpan(
        text: tr,
        style: TextStyle(
          color: sub.withValues(alpha: trAlpha),
          fontSize: (fontSize * 0.18).clamp(12.0, 22.0),
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
      );
      tp.layout(maxWidth: size.width * 0.8);
      tp.paint(canvas, Offset((size.width - tp.width) / 2,
          size.height / 2 + fontSize * 0.62));
    }
  }

  double _lineDuration(int i) {
    final lines = this.lines;
    final end = (i + 1 < lines.length)
        ? lines[i + 1].time
        : lines[i].time + const Duration(seconds: 4);
    final d = end - lines[i].time;
    return d.inMilliseconds / 1000.0 <= 0 ? 4.0 : d.inMilliseconds / 1000.0;
  }

  /// 巨号排版：单行铺满，按屏宽/字数自适应，超长自动换行
  _Layout _layout(String text, Size size) {
    final clean = text.replaceAll('\u00A0', '').trim();
    final W = size.width;
    final H = size.height;
    final u = H / 1080.0;

    // 先按单行算：min(H*0.98, W*1.3/(n*0.96))
    final n = clean.characters.length;
    var fs = n <= 0 ? 48.0 : math.min(H * 0.98, W * 1.3 / (n * 0.96));
    fs = fs.clamp(20.0, 200.0);

    // 测量总宽，超出则缩小 / 换行
    final tp = TextPainter(textDirection: TextDirection.ltr);
    final style = TextStyle(
      color: fg,
      fontSize: fs,
      fontWeight: FontWeight.w900,
      height: 1.05,
      letterSpacing: -0.02 * fs, // JIZURA huge 用负字距，紧凑
    );

    var lines = <String>[clean];
    tp.text = TextSpan(text: clean, style: style);
    tp.layout();
    if (tp.width > W * 0.88) {
      // 缩字号
      final k = (W * 0.88) / tp.width;
      fs *= k;
      // 极长的句子按字符均分成两行
      if (clean.length > 8 && fs < 34 * u * 2) {
        final mid = (clean.length / 2).ceil();
        lines = [clean.substring(0, mid), clean.substring(mid)];
      }
    }

    // 逐字排版（用于波浪 + 色差需要逐字定位）
    final glyphs = <_Glyph>[];
    double y = 0;
    for (int gi = 0; gi < lines.length; gi++) {
      final ln = lines[gi];
      final lineStyle = style.copyWith(fontSize: fs);
      tp.text = TextSpan(text: ln, style: lineStyle);
      tp.layout();
      final lineW = tp.width;

      // 逐字测宽
      double x = -lineW / 2;
      for (final ch in ln.characters) {
        tp.text = TextSpan(text: ch, style: lineStyle);
        tp.layout();
        final w = tp.width;
        glyphs.add(_Glyph(ch, x, y, w, fs, gi));
        x += w;
      }
      y += fs * 1.08;
    }
    // 垂直居中
    final totalH = y - fs * 0.08;
    for (final g in glyphs) {
      g.y += -totalH / 2;
    }

    return _Layout(glyphs, fs);
  }

  /// 逐字绘制：波浪 + 字重模拟
  void _drawPhrase({
    required Canvas canvas,
    required List<_Glyph> glyphs,
    required double fontSize,
    required double scale,
    required double rot,
    required Color color,
    required Offset offset,
    required double amt,
    required double time,
    required int index,
    required double weightK,
    required double blurPx,
    bool glow = false,
  }) {
    if (glyphs.isEmpty) return;
    final tp = TextPainter(textDirection: TextDirection.ltr);

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale, scale);
    if (rot != 0) canvas.rotate(rot);

    // 辉光：主层先画一圈模糊同色光晕（用 shadows，随字重生长增强）
    final shadow = glow
        ? [
            Shadow(
              color: accent.withValues(alpha: 0.55 * (0.5 + amt * 0.5)),
              blurRadius: 22 + weightK * 16,
            ),
            Shadow(
              color: accent2.withValues(alpha: 0.30 * (0.5 + amt * 0.5)),
              blurRadius: 38 + weightK * 22,
            ),
          ]
        : null;

    for (final g in glyphs) {
      final dy = _wave(g.i, time, fontSize, amt);
      final style = TextStyle(
        color: color,
        fontSize: g.fs,
        fontWeight: FontWeight.w900,
        height: 1.0,
        shadows: shadow,
      );
      // 字重生长：描边随 weightK 加粗，模拟可变字重从细到粗
      if (weightK > 0.02 && glow) {
        tp.text = TextSpan(
          text: g.ch,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = weightK * g.fs * 0.05
              ..strokeJoin = StrokeJoin.round
              ..color = color,
            color: null,
          ),
        );
      } else {
        tp.text = TextSpan(text: g.ch, style: style);
      }
      tp.layout();
      tp.paint(canvas,
          Offset(g.x + g.w / 2, g.y + dy) - Offset(tp.width / 2, tp.height / 2));
    }

    canvas.restore();
  }

  /// JIZURA 逐字波浪：dy = sin(t*7 + i*0.75) * size * 0.07 * AMT
  double _wave(int i, double time, double fontSize, double amt) {
    return math.sin(time * 7 + i * 0.75) * fontSize * 0.07 * amt;
  }

  void _drawIdle(Canvas canvas, Size size) {
    final tp = TextPainter(textDirection: TextDirection.ltr);
    tp.text = TextSpan(
      text: '暂无歌词',
      style: TextStyle(
        color: sub.withValues(alpha: 0.35),
        fontSize: 17,
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
  _Layout(this.glyphs, this.size);
}
