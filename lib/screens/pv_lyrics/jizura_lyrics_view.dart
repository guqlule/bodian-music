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

  /// 当前正在绘制的那一句（_paintLine 入口写入）。
  /// 扫字与高亮需要知道「现在画的是哪句」，因为交接时会被调用多次。
  int _curLine = -1;

  /// 当前正在绘制的那一句的虚拟播放位置。
  Duration _curAt = Duration.zero;

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
    if (lines.isEmpty || index < 0 || index >= lines.length) {
      _drawIdle(canvas, size);
      return;
    }

    final dur = _lineDuration(index);
    final t = ((position - lines[index].time).inMilliseconds / 1000.0)
        .clamp(0.0, dur);

    // 转场是否启用要先于时长计算——它决定用哪套时长（规矩 5）
    final useTransition =
        config.transition != LyricTransition.none && !config.fly;

    // 规矩 5：转场时长由行时长决定，并带下限。
    final inDur = useTransition
        ? (dur * 0.30).clamp(0.15, 0.45)
        : (dur * 0.36).clamp(0.12, 0.6);
    final outDur = useTransition
        ? (dur * 0.26).clamp(0.12, 0.40)
        : (config.exit == LyricExit.none
            ? 0.0
            : (dur * 0.3).clamp(0.14, 0.55));

    final enter = _cl(t / inDur);
    final exit = outDur > 0.002 ? _cl((t - (dur - outDur)) / outDur) : 0.0;

    // ---- 交接窗口：邻句一并在场 ----
    //
    // 只画一句时，旧句淡出与新句淡入之间必然空屏，alphaFloor 只能缓解。
    // 两句同时在场才是真正的叠化交接：旧句冻在出场末态，新句冻在进场初态，
    // 中间由当前句的进度把它们接起来。
    if (enter < 1 && index - 1 >= 0) {
      _paintLine(canvas, size, index - 1,
          enter: 1, exitIn: 1, at: position);
    }
    if (exit > 0 && index + 1 < lines.length) {
      _paintLine(canvas, size, index + 1,
          enter: 0, exitIn: 0, at: lines[index + 1].time);
    }

    _paintLine(canvas, size, index,
        enter: enter, exitIn: exit, at: position);
  }

  /// 画一句歌词。[enter]/[exit] 由调用方给��（冻结在 0 或 1 即为邻句定格），
  /// [at] 是这句的「虚拟播放位置」，用来解算扫字播放头。
  ///
  /// 原先这些都直接读 `index` / `position`，只能画当前句；
  /// 拆出来后交接时才能两句同场。
  void _paintLine(Canvas canvas, Size size, int i,
      {required double enter,
      required double exitIn,
      required Duration at}) {
    if (i < 0 || i >= lines.length) return;
    final line = lines[i];
    if (line.text.trim().isEmpty || line.text == '\u00A0') return;

    final pal = config.palette;

    // 供 _computeSweep / _wordProgressFraction 使用
    _curLine = i;
    _curAt = at;

    final dur = _lineDuration(i);
    final t = ((at - line.time).inMilliseconds / 1000.0).clamp(0.0, dur);

    final trans = config.transition;
    final fly = config.fly;
    final useTransition = trans != LyricTransition.none && !fly;

    // 规矩 5 的时长公式在这里要再用一次（amt 的爬升窗口依赖它）
    final inDur = useTransition
        ? (dur * 0.30).clamp(0.15, 0.45)
        : (dur * 0.36).clamp(0.12, 0.6);

    // ---- 镜头追踪参数 ----
    final rel = dur > 0 ? _cl(t / dur) : 0.0;
    final flyZ = _currentDepth(rel);
    final flyW = _depthW(flyZ);
    // 越过镜头后淡出，避免巨字糊屏
    final flyFade = flyZ < 0 ? (1 + flyZ / 0.55).clamp(0.0, 1.0) : 1.0;

    // 镜头追踪用整句时长驱动出��，而非固定秒数
    final exit = fly
        ? (rel > 0.62 ? _cl((rel - 0.62) / 0.38) : 0.0)
        : exitIn;
    // hold 强度：入场 85% 后 0.25s 升到 1，出场衰减
    final amt = _cl((t - inDur * 0.85) / 0.25) * (1 - exit);

    final seed = _hash(i * 37 + 11);
    final u = size.height / 1080.0;

    // 字重生长：前半段 cubic-out
    final weightK = 1 - math.pow(1 - _cl(t / (dur * 0.5)), 3).toDouble();

    final layout = _layout(line.text, size);

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);

    // ---- 邻句：画在主句变换之外，避免跟着一起缩放 ----
    if (fly) {
      // 上一句已越过镜头（worldY -1 → 向上冲出画面）
      if (i - 1 >= 0) {
        _drawDepthLine(canvas, size, lines[i - 1].text, -0.34, 0.26, -1);
      }
      // 下一句仍在远处（worldY +1 → 位于下方远处）
      if (i + 1 < lines.length) {
        _drawDepthLine(canvas, size, lines[i + 1].text, 1.7, 0.34, 1);
      }
      // 当前句在 worldY 0，只有缩放没有纵向偏移
      canvas.scale(flyW, flyW);
    } else if (config.layout == LyricLayout.marquee) {
      // ---- 跑马灯：横向滑入滑出 ----
      // 进：从右侧滑到中央（enter 0→1 对应 +W→0）
      // 出：继续向左滑出（exit 0→1 对应 0→-W）
      final slide = (1 - enter) * size.width * 1.15 - exit * size.width * 1.15;
      canvas.translate(slide, 0);
    }

// 出场变换只算一次：镜头追踪时只用它的 alpha 做淡出
    final xo = _exitTransform(config.exit, exit, seed);

    // ---- 转场：接管入场/出场的位移与淡出 ----
    // 方向全曲统一（见 _flowAngle），所以交接前后运动方向不变。
    var trBlur = 0.0;
    var trAlpha = 1.0;

    if (useTransition) {
      // 规矩 3：位移单位取本行自己的尺度（不小于字号的行宽），
      // 「刚好移出画面」即可，与屏幕大小无关。
      final lineW = layout.glyphs.isEmpty
          ? layout.size
          : math.max(layout.glyphs.last.x + layout.glyphs.last.w
              - layout.glyphs.first.x, layout.size);
      final unit = lineW * 0.5 + size.width * 0.5;

      final fEnter = _transitionFrame(trans, 'enter', enter, unit);
      final fExit = _transitionFrame(trans, 'exit', exit, unit);

      // 两段位移相加：出场继续沿向量推进，进场从上游抵达
      final dx = fExit.dx + fEnter.dx;
      final dy = fExit.dy + fEnter.dy;
      canvas.translate(dx, dy);
      canvas.scale(fExit.scale * fEnter.scale, fExit.scale * fEnter.scale);

      trAlpha = fExit.alpha * fEnter.alpha;
      trBlur = math.max(fEnter.blur, fExit.blur);
    } else if (!fly) {
      final xf = _entranceTransform(config.entrance, enter, seed, layout.size);
      canvas.translate(xf.dx, xf.dy);
      if (xf.rot != 0) canvas.rotate(xf.rot);
      canvas.scale(xf.scale, xf.scaleY);

      // ---- 出场变换 ----
      canvas.translate(xo.dx, xo.dy);
      canvas.scale(xo.scale, xo.scale);
      if (xo.rot != 0) canvas.rotate(xo.rot);
    }

    final globalAlpha =
        ((useTransition ? trAlpha : (fly ? 1.0 : xo.alpha)) * flyFade)
            .clamp(0.0, 1.0);
    if (globalAlpha <= 0.003) {
      canvas.restore();
      return;
    }

    // ---- 转场模糊：用 saveLayer 整体虚化 ----
    // 只在确实需要时才开：全屏 blur 每帧一次 saveLayer，
    // 在车机/低端机上开销明显，所以 sigma 有下限门槛并封顶。
    var blurLayer = false;
    if (trBlur > 0.4) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: trBlur,
            sigmaY: trBlur,
            tileMode: TileMode.decal,
          ),
      );
      blurLayer = true;
    }

// ---- 满屏铺贴：整句缩小后平铺成背景墙（画在主句之下）----
    if (config.layout == LyricLayout.tile) {
      _drawTiledWall(canvas, size, layout);
    }

    // ---- 残像堆叠：主句下方的递减残影（画在主句之下）----
    if (config.layout == LyricLayout.stack) {
      _drawStackGhosts(canvas, layout, pal, globalAlpha, weightK, amt, t);
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

    // ---- 扫字：两层结构（暗底 + 亮层遮罩）----
    //
    // 参考 folia-major 的 PendoloActiveLyricSweep：
    // 逐字 lerp 颜色只能让「一个字」内部有渐变，字与字之间仍是硬边，
    // 视觉上像色块跳变而非扫过。
    // 正确做法是整句画两遍——底层压暗，上层用横向渐变遮罩
    // 只露出播放头左侧，这样软边可以横跨整行、跨过字的接缝。
    final sweep = _computeSweep(line, layout, t, dur);
    final baseInk = pal.fg.withValues(alpha: globalAlpha);

    if (sweep != null) {
      // 底层：整句统一压暗（参考用 0.52，这里同量级）
      final dim = baseInk.withValues(alpha: baseInk.a * 0.52);
      _pass(canvas, layout, dim, Offset.zero, weightK, amt, t, false);

      // 上层：横向渐变遮罩，播放头左侧为亮色
      final brightInk = Color.lerp(baseInk, pal.accent, 0.92)!;
      final shader = _sweepShader(layout, sweep.maskX, sweep.halfBand, brightInk);
      if (shader != null) {
        _pass(canvas, layout, Colors.white, Offset.zero, weightK, amt, t, true,
            shader: shader);
      }
    } else {
      // ---- 主层 ----
      _pass(canvas, layout, baseInk, Offset.zero, weightK, amt, t, true);
    }

// 先关闭转场模糊层（若开启），再关闭主 save
    if (blurLayer) canvas.restore();
    canvas.restore();

    // ---- 翻译行 ----
    final trans2 = line.translation;
    if (trans2 != null && trans2.isNotEmpty && exit < 0.4) {
      final trAlpha = (1 - exit) * (0.4 + amt * 0.3);
      final tp = TextPainter(textDirection: TextDirection.ltr);
      tp.text = TextSpan(
        text: trans2,
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

// ---------------- 满屏铺贴：背景墙 ----------------
  ///
  /// 把当前句整体缩到 ~24% 后在屏幕上平铺，形成半透明文字墙。
  /// 在中心坐标系里工作：先平移到中心再 scale(k)，
  /// 此时可见范围放大为 size/k，所以需要铺 (size/(k*totalW)) 份。
  ///
  /// 绘制量有硬上限（[_tileMaxGlyphs]）：这是车机/低端机场景，
  /// CustomPaint 每帧重绘，逐字 TextPainter.layout 开销必须封顶。
  static const int _tileMaxGlyphs = 48;

  void _drawTiledWall(Canvas canvas, Size size, _Layout layout) {
    if (layout.glyphs.isEmpty) return;
    final pal = config.palette;
    final totalW = layout.glyphs.last.x + layout.glyphs.last.w;
    final rowH = layout.size * 1.12;
    if (totalW <= 1 || rowH <= 1) return;

    const k = 0.24;
    final visW = size.width / k;
    final visH = size.height / k;
    final cols = (visW / totalW).ceil() + 1;
    final rowCount = (visH / rowH).ceil() + 1;
    if (cols <= 0 || rowCount <= 0) return;

    final tp = TextPainter(textDirection: TextDirection.ltr);
    final st = TextStyle(
      fontSize: layout.size,
      fontWeight: FontWeight.w900,
      height: 1.0,
      letterSpacing: -0.02 * layout.size,
      color: pal.fg.withValues(alpha: 0.055),
    );

    var drawn = 0;
    canvas.save();
    // 注意：调用处已把画布平移到屏幕中心，这里不能再平移一次，
    // 否则整面墙会偏移 (W/2, H/2)。
    canvas.scale(k, k);
    for (int r = -rowCount; r <= rowCount; r++) {
      // 奇数行错开半格，避免出现明显的竖向对齐纹
      final rowShift = r.isOdd ? totalW * 0.5 : 0.0;
      for (int c = -cols; c <= cols; c++) {
        canvas.save();
        canvas.translate(c * totalW + rowShift, r * rowH);
        for (final g in layout.glyphs) {
          if (drawn >= _tileMaxGlyphs) {
            canvas.restore();
            canvas.restore();
            return;
          }
          drawn++;
          tp.text = TextSpan(text: g.ch, style: st);
          tp.layout();
          tp.paint(canvas, Offset(g.x, g.y));
        }
        canvas.restore();
      }
    }
    canvas.restore();
  }

  // ---------------- 残像堆叠 ----------------
  ///
  /// 主句下方叠 N 层残影：每层向下偏移、缩小、透明度递减，
  /// 形成向下的纵深衰减。
  void _drawStackGhosts(Canvas canvas, _Layout layout, LyricPalette pal,
      double globalAlpha, double weightK, double amt, double t) {
    final step = layout.size * 0.30;
    for (int k = 1; k <= 3; k++) {
      final fade = (1 - k * 0.26) * globalAlpha;
      if (fade <= 0.01) break;
      canvas.save();
      canvas.translate(0, step * k);
      final s = 1 - k * 0.085;
      canvas.scale(s, s);
      _pass(canvas, layout, pal.fg.withValues(alpha: fade), Offset.zero,
          weightK, amt, t, false);
      canvas.restore();
    }
  }

  /// 扫字亮层的横向渐变遮罩。
  ///
  /// 参考 folia-major：`linear-gradient(90deg, #000 …#000, rgba(0,0,0,.84), transparent)`，
  /// 即播放头左侧完全不透明，到播放头处用一段软边淡出。
  /// 软边宽度跟字号挂钩（`fontPx * 0.42`，夹在 8~16px），
  /// 这样大字号有足够过渡、小字号又不会糊成一片。
  ///
  /// 返回 null 表示此刻不该有任何亮层（还没开始唱 / 已唱完）。
  ui.Gradient? _sweepShader(
      _Layout layout, double maskX, double halfBand, Color bright) {
    if (layout.glyphs.isEmpty) return null;
    final left = layout.glyphs.first.x;
    final right = layout.glyphs.last.x + layout.glyphs.last.w;
    final totalW = right - left;
    if (totalW <= 1) return null;

    // 尚未开唱
    if (maskX < 0) return null;

    final edge = (layout.size * 0.42).clamp(8.0, 16.0);

    // 唱完整句后播放头是 infinity：应保持整句常亮，而不是把亮层撤掉。
    // 参考实现同样在时间超出末字后返回 fullWidth（整行填满）。
    final mx = maskX.isInfinite ? right + edge : maskX;

    // 归一化播放头与软边到 [0,1]
    double p(double x) => ((x - left) / totalW).clamp(0.0, 1.0);

    final s0 = p(mx - edge);
    final s1 = p(mx + edge);

    final transparent = bright.withValues(alpha: 0.0);
    final stops = <double>[0.0, s0, s1, 1.0];
    final colors = <Color>[bright, bright, transparent, transparent];

    // 渐变 stop 必须严格递增且落在 [0,1]，否则 Flutter 会抛断言。
    // s0 <= s1 由 edge > 0 保证，这里只处理边界重合导致的重复 stop。
    final cleanStops = <double>[];
    final cleanColors = <Color>[];
    for (int i = 0; i < stops.length; i++) {
      if (i > 0 && stops[i] <= cleanStops.last) continue;
      cleanStops.add(stops[i]);
      cleanColors.add(colors[i]);
    }
    if (cleanStops.length < 2) return null;

    return ui.Gradient.linear(
      Offset(left, 0),
      Offset(right, 0),
      cleanColors,
      cleanStops,
    );
  }

  // ---------------- 句间转场 ----------------
  //
  // 移植自 folia-major：
  //   temperaTransitions.ts  (block-wipe / camera-pan / shape-carry)
  //   lumiereTransitions.ts   (lights-out / flare-cut / focus-pull)
  //
  // 核心约定：**出场与进场走同一条 flowAngle 向量**。
  // 参考注释写得很清楚：
  //   "exit moves the outgoing composition further along the flow;
  //    enter starts the incoming one upstream and lets it arrive on
  //    the same vector, so across the swap the on-screen motion
  //    never changes direction."
  // 也就是说交接在屏幕上读起来是一段连续的移动，
  // 而不是「退回去再推进去」——后者正是转场显得生硬的原因。
  static double _smooth01(double v) {
    final t = v.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  /// 全曲统一的流向量。
  ///
  /// 规矩 1：方向属于整首歌，不属于单句。
  /// 早先版本用 `_hash(lineIndex)` 给每句一个随机角度，
  /// 于是第 3 句往右上退场、第 4 句从左下进场 —— 参考项目要的恰恰相反。
  /// 相邻边界方向不一致会让人晕车，所以这里固定成一个常量：
  /// 略微向下的水平流向，读起来像文字在流，而不是在乱窜。
  static const double _flowAngle = -0.21;

  /// 不许空屏：淡出时的 alpha 下限。
  ///
  /// 规矩 2。我们只画一句，旧句淡到 0、新句还没淡进来时屏幕是纯黑的。
  /// 留一个地板让交接读起来是「快速溶解」而不是「灭屏再点亮」。
  static const double _alphaFloor = 0.16;

  /// 解算转场在某一侧的画面帧。
  ///
  /// [phase] = exit 表示旧句走向边界，enter 表示新句离开边界。
  /// [progress] 为 0→1。返回的 dx/dy 已按画布尺寸归一化。
  static ({double dx, double dy, double scale, double alpha, double blur})
      _transitionFrame(LyricTransition kind, String phase, double progress,
          double unit) {
    final linear = progress.clamp(0.0, 1.0);
    final eased = _inOutExpo(linear);
    // 越靠近边界 near 越大
    final near = phase == 'exit' ? _smooth01(linear) : 1 - _smooth01(linear);
    final flowX = math.cos(_flowAngle);
    final flowY = math.sin(_flowAngle);

    double travelFactor = 0.0; // 沿向量走了多远（以本行大小为单位）
    var scale = 1.0;
    var alpha = 1.0;
    var blur = 0.0;

    // 规矩 4：一个转场只做一件事。
    // 早先版本位移+缩放+模糊+透明度一起上，必然显乱。
    // 现在每种只允许一个主轴：
    //   熄灯/闪白 -> alpha    拉焦 -> blur
    //   推移/擦除 -> position  溶入 -> scale
    switch (kind) {
      case LyricTransition.lightsOut:
        // 只做透明度，且不低于地板
        alpha = _alphaFloor + (1 - _alphaFloor) * (1 - near);
        break;
      case LyricTransition.flareCut:
        // 只做透明度：边界处快速压暗再回弹，像一次闪光
        alpha = 1 - 0.85 * (near * near * (3 - 2 * near));
        break;
      case LyricTransition.focusPull:
        // 只做模糊，峰值落在边界上
        blur = 11 * near;
        break;
      case LyricTransition.cameraPan:
        // 只做位移：刚好把这一行推出画面
        travelFactor = phase == 'exit' ? eased : -(1 - eased);
        alpha = _alphaFloor + (1 - _alphaFloor) *
            (phase == 'exit' ? 1 - _cl((linear - 0.78) / 0.22) : _cl(linear / 0.22));
        break;
      case LyricTransition.blockWipe:
        // 只做位移，行程更长：整句横穿
        travelFactor = phase == 'exit' ? eased * 1.35 : -(1 - eased) * 1.35;
        alpha = _alphaFloor + (1 - _alphaFloor) *
            (phase == 'exit' ? 1 - _cl((linear - 0.84) / 0.16) : _cl(linear / 0.18));
        break;
      case LyricTransition.shapeCarry:
        // 只做缩放：向镜头推近 / 退远
        scale = 1 + (phase == 'exit' ? eased : 1 - eased) * 0.12;
        alpha = _alphaFloor + (1 - _alphaFloor) *
            (phase == 'exit' ? 1 - _cl((linear - 0.70) / 0.30) : _cl(linear / 0.30));
        break;
      case LyricTransition.none:
        break;
    }

    return (
      // 规矩 3：位移以本行大小为单位，不是屏幕对角线。
      // 巨字（0.98H）整句横穿对角线时，大部分时间它是半截挂在
      // 屏幕上被裁切的巨字，观感很差。
      dx: flowX * travelFactor * unit,
      dy: flowY * travelFactor * unit,
      scale: scale,
      alpha: alpha.clamp(0.0, 1.0),
      blur: blur.clamp(0.0, 14.0),
    );
  }

  // ---------------- Z 轴穿越（镜头追踪）----------------
  //
  /// 投影用单个透视因子 w = 1 / (1 + z)：
  ///   z > 0（远处）→ w < 1，缩小并向消失点（屏幕中心）收拢
  ///   z = 0（焦点）→ w = 1，居中满幅
  ///   z < 0（越过镜头）→ w > 1，放大并反向冲出画面
  /// 缩放与纵向偏移都用 w，所以远处句子会自然向中心聚拢，
  /// 形成纵深隧道感。
  static double _depthW(double z) => 1.0 / (1.0 + z);

  /// 当前句的深度：前半程从远处逼近焦点，后半程掠过镜头。
  ///
  /// 用**线性**而非缓动：等速飞行才有「镜头在推进」的感觉，
  /// outCubic 会把大部分位移挤在前 20%，剩下的时间几乎不动。
  double _currentDepth(double rel) {
    if (rel < 0.55) return 1.0 - rel / 0.55; // 1 → 0
    return -((rel - 0.55) / 0.45) * 0.55; // 0 → -0.55
  }

  /// 在给定深度画一句歌词（邻句用，不走完整特效链，保证性能）
  ///
  /// [worldY] 是该句在世界坐标里的纵向槽位：0=当前句（居中），
  /// +1=下一句（屏幕下方），-1=上一句（屏幕上方，已冲向镜头外）。
  /// 屏幕偏移 = worldY × 间距 × w，所以远处句子会向中心收拢、
  /// 越过镜头的句子会向上方冲出画面。
  void _drawDepthLine(Canvas canvas, Size size, String text, double z,
      double alpha, double worldY) {
    final clean = text.replaceAll('\u00A0', '').trim();
    if (clean.isEmpty || alpha <= 0.02) return;
    final pal = config.palette;

    final w = _depthW(z);
    if (w <= 0.04 || w > 6.0) return; // 太远或已完全掠过镜头

    final fs = (math.min(size.height * 0.42, size.width * 0.86) * w)
        .clamp(10.0, 400.0);
    if (fs < 10.5) return;

    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 3,
      ellipsis: '…',
    )..text = TextSpan(
        text: clean,
        style: TextStyle(
          fontSize: fs,
          fontWeight: FontWeight.w800,
          height: 1.1,
          letterSpacing: -0.02 * fs,
          color: pal.fg.withValues(alpha: alpha),
        ),
      );
    tp.layout(maxWidth: size.width * 0.9);

    final dy = size.height * 0.30 * w * worldY;
    tp.paint(
      canvas,
      Offset((size.width - tp.width) / 2, size.height / 2 + dy - tp.height / 2),
    );
  }

  // ---------------- 时长 ----------------
  double _lineDuration(int i) {
    final end = (i + 1 < lines.length)
        ? lines[i + 1].time
        : lines[i].time + const Duration(seconds: 4);
    final d = end - lines[i].time;
    return d.inMilliseconds <= 0 ? 4.0 : d.inMilliseconds / 1000.0;
  }

  // ---------------- 扫字播放头 ----------------
  ///
  /// 返回 (播放头像素位置, 软带半宽)；未启用时 second 为 null。
  ///
  /// 优先用逐字时间戳（KRC/QRC）：
  ///   maskX = 已完成字的累计宽度 + 当前字内进度 × 当前字宽
  /// 软带半宽固定为「行内平均字宽」——若用当前字宽，
  /// 字切换瞬间半宽突变会让边缘 alpha 断崖闪烁。
  ///
  /// 无逐字时间戳时退化为行级进度（按本行已唱比例扫过整行）。
  ({double maskX, double halfBand})? _computeSweep(
      LyricLine line, _Layout layout, double t, double dur) {
    if (!config.sweep) return null;
    if (layout.glyphs.isEmpty) return null;
    if (line.hasWords && line.words!.isNotEmpty) {
      final words = line.words!;
      final n = words.length < layout.glyphs.length
          ? words.length
          : layout.glyphs.length;

      double maskX;
      var curIdx = -1;
      var intra = 0.0;
      for (int i = 0; i < n; i++) {
        final w = words[i];
        final wEnd = w.duration != null
            ? w.time + w.duration!
            : w.time + const Duration(seconds: 1);
        if (_curAt >= wEnd) {
          curIdx = i + 1;
        } else if (_curAt >= w.time) {
          curIdx = i;
          final total = wEnd - w.time;
          intra = total.inMilliseconds > 0
              ? ((_curAt - w.time).inMilliseconds / total.inMilliseconds)
                  .clamp(0.0, 1.0)
              : 1.0;
          break;
        } else {
          curIdx = i;
          intra = 0.0;
          break;
        }
      }

      if (curIdx >= n) {
        maskX = double.infinity;
      } else if (curIdx < 0) {
        maskX = -1.0;
      } else {
        final w = layout.glyphs[curIdx];
        maskX = w.x + w.w * intra;
      }

      // 行内平均字宽
      final totalW = layout.glyphs.isEmpty
          ? 0.0
          : layout.glyphs.last.x + layout.glyphs.last.w;
      final meanW = layout.glyphs.isEmpty
          ? 0.0
          : (totalW / layout.glyphs.length);
      return (maskX: maskX, halfBand: meanW);
    }

    // 行级退化：按本行进度扫过整行
    final p = _cl(t / math.max(dur, 0.01));
    final totalW =
        layout.glyphs.isEmpty ? 0.0 : layout.glyphs.last.x + layout.glyphs.last.w;
    return (maskX: totalW * p, halfBand: totalW * 0.18);
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
    final isMarquee = config.layout == LyricLayout.marquee;

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
        // 主句下方要叠残影，故留出下方空间
        baseFs = math.min(H * 0.34, W * 0.80 / (n * 0.72));
        break;
      case LyricLayout.tile:
        // 背景墙用小字平铺，主句反而要大，形成对比
        baseFs = math.min(H * 0.42, W * 0.86 / (n * 0.76));
        break;
      case LyricLayout.marquee:
        // 跑马灯：单行不折行，允许比屏幕宽（横向滑入滑出）
        baseFs = math.min(H * 0.17, W * 2.2 / n);
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

// 决定是否折行（跑马灯保持单行）
    var segs = <String>[clean];
    if (!isMarquee) {
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
  bool _isStrokeTreat(LyricTreat t) =>
      t == LyricTreat.outline || t == LyricTreat.neon;

  void _pass(
    Canvas canvas,
    _Layout layout,
    Color color,
    Offset offset,
    double weightK,
    double amt,
    double t,
    bool isMain, {
    ui.Gradient? shader,
  }) {
    if (layout.glyphs.isEmpty) return;
    final pal = config.palette;
    final treat = config.treat;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    final motion = config.motion;

    canvas.save();
    canvas.translate(offset.dx, offset.dy);

// 打字机：按进度逐字显现。
    // 不再要求 treat == none —— 否则选了默认的辉光时打字机整个失效。
    final typeCut = config.entrance == LyricEntrance.type;
    final shown = typeCut
        ? (layout.glyphs.length * _cl((t - 0.05) / 0.5)).floor()
        : layout.glyphs.length;

    for (int gi = 0; gi < shown; gi++) {
      final g = layout.glyphs[gi];

// 保持动效：目前只有抖动，低频位置随机偏移
      final h = _hash(gi * 13 + t.toInt() * 7);
      final h2 = _hash(gi * 29 + t.toInt() * 11);
      final dx = (h - 0.5) * g.fs * 0.05 * amt * motion;
      final dy = (h2 - 0.5) * g.fs * 0.05 * amt * motion;

// 高亮特效：已唱部分按整句比例渐变到强调色
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
              ..color = glyphColor,
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
              ..color = Color.lerp(glyphColor, Colors.white, 0.4)!,
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
                [top, glyphColor],
              ),
          );
          break;
        case LyricTreat.glow:
          st = TextStyle(
            fontSize: g.fs,
            fontWeight: FontWeight.w900,
            height: 1.0,
            color: glyphColor,
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

// 扫字亮层用的 shader 画笔（描边类特效不参与遮罩）。
      // 必须在字重生长分支**之前**算好：那个分支会 continue，
      // 遮罩若只在其后应用，整句绝大部分时间都走不到（这正是之前
      // 「完全看不到扫字」的原因——weightK 一过 0.02 就提前 continue）。
      final sweepPaint =
          (shader != null && !_isStrokeTreat(treat)) ? (Paint()..shader = shader) : null;

      // 字重生长：描边加粗（仅主层）
      if (isMain && weightK > 0.02 && treat != LyricTreat.outline && treat != LyricTreat.neon) {
        st = st.copyWith(
          foreground: sweepPaint ??
              (Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = weightK * g.fs * 0.05
                ..strokeJoin = StrokeJoin.round
                ..color = glyphColor),
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
          color: (treat == LyricTreat.gradient || sweepPaint != null)
              ? null
              : glyphColor,
          foreground: sweepPaint ??
              (treat == LyricTreat.gradient ? st.foreground : null),
          shadows: st.shadows,
        );
        tp.text = TextSpan(text: g.ch, style: st2);
        tp.layout();
        tp.paint(canvas, Offset(g.x + dx, g.y + dy));
        continue;
      }

final p = Offset(g.x + dx, g.y + dy);

      // 扫字亮层：整句用横向渐变遮罩绘制。
      // 遮罩跨整行，所以软边能横跨字的接缝——这正是逐字上色的做不到的。
      if (sweepPaint != null) {
        st = st.copyWith(foreground: sweepPaint, color: null);
        tp.text = TextSpan(text: g.ch, style: st);
        tp.layout();
        tp.paint(canvas, p);
        continue;
      }

      // 描边填充（强调色粗描边 + 白字填充）需要两层绘制
      if (treat == LyricTreat.strokeFill && isMain) {
        tp.text = TextSpan(text: g.ch, style: st); // st 是 accent 描边层
        tp.layout();
        tp.paint(canvas, p);
        final fillStyle = TextStyle(
          fontSize: g.fs,
          fontWeight: FontWeight.w900,
          height: 1.0,
          foreground: sweepPaint,
          color: sweepPaint != null ? null : glyphColor,
        );
        tp.text = TextSpan(text: g.ch, style: fillStyle);
        tp.layout();
        tp.paint(canvas, p);
        continue;
      }

tp.text = TextSpan(text: g.ch, style: st);
      tp.layout();
      tp.paint(canvas, p);
    }

    canvas.restore();
  }

  /// 该字在整句中的横向完成比例（0~1），用于高亮特效
double _wordProgressFraction(_Glyph g) {
    if (_curLine < 0 || _curLine >= lines.length) return 0;
    final line = lines[_curLine];
    if (!line.hasWords || g.i >= line.words!.length) return 0;
    final w = line.words![g.i];
    final d = w.duration ?? const Duration(milliseconds: 400);
    if (d.inMilliseconds <= 0) return _curAt >= w.time ? 1 : 0;
    return ((_curAt - w.time).inMilliseconds / d.inMilliseconds)
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
