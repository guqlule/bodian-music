import 'dart:async';
import 'dart:math';
import '../core/theme/app_theme.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/audio/audio_analysis_service.dart';

enum VisualizerEffect {
  bars('频谱'),
  wave('波浪'),
  circle('圆环'),
  ring('脉冲'),
  particles('粒子'),
  flame('火焰'),
  aurora('极光'),
  water('水波');

  final String label;
  const VisualizerEffect(this.label);
}

Color _freqColor(int index, int total, double alpha) {
  final t = total > 1 ? index / (total - 1) : 0.5;
  final warm = AppColors.isDark ? const Color(0xFFE8C896) : const Color(0xFFC9A882);
  final cool = AppColors.isDark ? const Color(0xFFC5DDEF) : const Color(0xFF9BB5C9);
  final r = (warm.r * 255 + (cool.r * 255 - warm.r * 255) * t).round();
  final g = (warm.g * 255 + (cool.g * 255 - warm.g * 255) * t).round();
  final b = (warm.b * 255 + (cool.b * 255 - warm.b * 255) * t).round();
  return Color.fromARGB((alpha * 255).round(), r, g, b);
}

Color _beatColor(double alpha) {
  final warm = AppColors.isDark ? const Color(0xFFE8C896) : const Color(0xFFC9A882);
  return Color.fromARGB((alpha * 255).round(), warm.r ~/ 1, warm.g ~/ 1, warm.b ~/ 1);
}

// 共享缓存 Paint 对象，避免每帧 GC 压力
// 注意：以下 _p* 函数全部返回**同一个** Paint 实例，仅修改 color/strokeWidth/strokeCap
// 调用方必须保证不在调用之间持有返回值（Flutter 引擎在 drawXxx 调用前会完成读取）
Paint _p(Color c) => _fillPaintCache..color = c;
Paint _pFill(Color c) => _fillPaintCache..color = c;
Paint _pStroke(Color c, double w) => _strokePaintCache
  ..color = c
  ..strokeWidth = w;
Paint _pStrokeRound(Color c, double w) => _strokeRoundPaintCache
  ..color = c
  ..strokeWidth = w;

final Paint _fillPaintCache = Paint();
final Paint _strokePaintCache = Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = 1.0;
final Paint _strokeRoundPaintCache = Paint()
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeWidth = 1.0;
final Paint _glowPaintCache = Paint()
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
Paint _pGlow(Color c, double w) => _glowPaintCache
  ..color = c
  ..strokeWidth = w;

// aurora 光线 2 级 blur 缓存（18/36），只更新 shader（原 4 级过于昂贵）
final List<Paint> _auroraBlurCaches = List.generate(2, (i) => Paint()
  ..style = PaintingStyle.fill
  ..maskFilter = MaskFilter.blur(BlurStyle.normal, 18.0 + i * 18.0));

void _paintBg(Canvas canvas, Size size, double volume) {
  canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _pFill(AppColors.background));
}

class AudioVisualizer extends StatefulWidget {
  final int barCount;
  final VisualizerEffect effect;
  final Stream<SpectrumData> spectrumStream;
  final bool playing;
  final VoidCallback? onNativeStale;

  /// 原生数据是否"活着"（有帧且非全零）。
  /// 提供时优先生效；否则退回用数据到达时间戳判断。
  final bool Function()? isDataAlive;

  const AudioVisualizer({
    super.key,
    this.barCount = 32,
    this.effect = VisualizerEffect.bars,
    required this.spectrumStream,
    required this.playing,
    this.onNativeStale,
    this.isDataAlive,
  });

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer> {
  SpectrumData _spectrum = SpectrumData.empty;
  StreamSubscription? _sub;
  int _frame = 0;
  Timer? _timer;
  final List<double> _peaks = [];
  final List<_Particle> _particles = [];
  final List<_CosmicStar> _cosmicStars = [];
  final List<_Particle> _flameParticles = [];
  final List<_FlameTongue> _flameTongues = [];
  final List<_Ember> _embers = [];
  final List<_SmokeWisp> _smokeWisps = [];
  final List<_AuroraCurtain> _auroraCurtains = [];
  final List<_AuroraStar> _auroraStars = [];
  final List<_Bubble> _bubbles = [];
  final List<_LightRay> _lightRays = [];
  final List<_Caustic> _caustics = [];
  final List<_WaterDrop> _waterDrops = [];
  final List<_Shockwave> _shockwaves = [];
  final List<_WaterRipple> _ripples = [];
  final Random _random = Random();
  final ChangeNotifier _repaint = ChangeNotifier();

  // 原生数据看门狗 + 模拟兜底
  DateTime _lastNativeData = DateTime.now();
  List<double> _simFreqs = [];
  bool _simActive = false;
  bool _staleNotified = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.spectrumStream.listen((data) {
      if (data.frequencies.isNotEmpty) _lastNativeData = DateTime.now();
      _spectrum = data;
      _dirty = true;
      while (_peaks.length < data.frequencies.length) {
        _peaks.add(0);
      }
      for (int i = 0; i < data.frequencies.length && i < _peaks.length; i++) {
        if (data.frequencies[i] > _peaks[i]) {
          _peaks[i] = data.frequencies[i];
        } else {
          _peaks[i] *= 0.92;
        }
      }
      if (data.beat > 0.6 && _shockwaves.length < 5) {
        _shockwaves.add(_Shockwave(life: 1.0));
      }
    });
    _syncTimer();
  }

  bool _dirty = false;

  void _syncTimer() {
    if (widget.playing && _timer == null) {
      // 30fps：音视频谱不需要 60fps，每帧含全屏重绘 + 模糊绘制，30fps 已足够流畅且显著降低 GPU 压力
      _timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        _tick();
      });
    } else if (!widget.playing && _timer != null) {
      _timer?.cancel();
      _timer = null;
      _spectrum = SpectrumData.empty;
      _simFreqs = [];
      _simActive = false;
      _staleNotified = false;
      _dirty = true;
      _repaint.notifyListeners();
    }
  }

  void _tick() {
    _frame++;
    if (widget.playing) {
      final alive = widget.isDataAlive?.call() ??
          DateTime.now().difference(_lastNativeData).inMilliseconds <= 1500;
      final staleMs = DateTime.now().difference(_lastNativeData).inMilliseconds;
      if (!alive) {
        // 原生数据流中断/全零：通知外部重启捕获 + 切模拟频谱兜底
        if (!_staleNotified) {
          _staleNotified = true;
          _simActive = true;
          widget.onNativeStale?.call();
        }
        _updateSim();
      } else if (_simActive) {
        // 原生数据恢复，模拟退位
        _simActive = false;
        _staleNotified = false;
        _simFreqs = [];
      } else {
        _staleNotified = false;
        if (staleMs > 1500) _lastNativeData = DateTime.now().subtract(const Duration(milliseconds: 100));
      }
    }
    // 仅在 _spectrum 更新时触发重绘，避免无数据时重复绘制
    if (_dirty) {
      _dirty = false;
      _repaint.notifyListeners();
    }
  }

  void _updateSim() {
    final t = _frame * 0.05;
    final vol = 0.55 + 0.45 * sin(t * 0.9) * sin(t * 0.23 + 1.7);
    final pulse = sin(t * 2.2).clamp(0.0, 1.0);
    if (_simFreqs.isEmpty) _simFreqs = List<double>.filled(64, 0);
    for (int i = 0; i < _simFreqs.length; i++) {
      final fi = i / _simFreqs.length;
      final low = sin(fi * 3 + t) * 0.5 + 0.5;
      final mid = sin(fi * 11 + t * 1.7) * 0.5 + 0.5;
      final high = sin(fi * 27 - t * 2.3) * 0.5 + 0.5;
      final v = (low * 0.6 + mid * 0.3 + high * 0.1) * vol;
      final target = fi < 0.2 ? v * (0.8 + pulse * 0.4) : v;
      _simFreqs[i] = _simFreqs[i] * 0.6 + target.clamp(0.0, 1.0) * 0.4;
    }
    final bass = _simFreqs[2] + _simFreqs[3] * 0.5;
    _spectrum = SpectrumData(
      frequencies: _simFreqs,
      bass: bass.clamp(0.0, 1.0),
      mid: _simFreqs[20],
      treble: _simFreqs[50],
      volume: vol * 0.6,
      beat: pulse > 0.95 ? 1.0 : 0,
    );
    _dirty = true;
  }

  @override
  void didUpdateWidget(covariant AudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) _syncTimer();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: RepaintBoundary(child: _buildPainter()),
    );
  }

  Widget _buildPainter() {
    switch (widget.effect) {
      case VisualizerEffect.bars:
        return CustomPaint(painter: _BarsPainter(state: this, count: min(widget.barCount, 64), repaint: _repaint));
      case VisualizerEffect.wave:
        return CustomPaint(painter: _WavePainter(state: this, repaint: _repaint));
      case VisualizerEffect.circle:
        return CustomPaint(painter: _CirclePainter(state: this, repaint: _repaint));
      case VisualizerEffect.ring:
        return CustomPaint(painter: _RingPainter(state: this, repaint: _repaint));
      case VisualizerEffect.particles:
        return CustomPaint(painter: _ParticlePainter(state: this, repaint: _repaint));
      case VisualizerEffect.flame:
        return CustomPaint(painter: _FlamePainter(state: this, repaint: _repaint));
      case VisualizerEffect.aurora:
        return CustomPaint(painter: _AuroraPainter(state: this, repaint: _repaint));
      case VisualizerEffect.water:
        return CustomPaint(painter: _WaterPainter(state: this, repaint: _repaint));
    }
  }
}

class _Particle {
  double x, y, vx, vy, size, life, maxLife, hue;
  _Particle({
    required this.x, required this.y,
    required this.vx, required this.vy,
    required this.size, required this.life,
    this.maxLife = 1.0, this.hue = 0,
  });
}

class _CosmicStar {
  double orbitRadius, angle, speed, size, brightness, trail;
  int ring;
  _CosmicStar({
    required this.orbitRadius, required this.angle, required this.speed,
    required this.size, required this.brightness, this.trail = 0, this.ring = 0,
  });
}

class _FlameTongue {
  double x, baseY, width, height, sway, swaySpeed, swayAmp, life;
  int layer;
  _FlameTongue({
    required this.x, required this.baseY, required this.width, required this.height,
    required this.sway, required this.swaySpeed, required this.swayAmp,
    required this.life, this.layer = 0,
  });
}

class _Ember {
  double x, y, vx, vy, size, life, maxLife;
  _Ember({required this.x, required this.y, required this.vx, required this.vy,
    required this.size, required this.life, this.maxLife = 1.0});
}

class _SmokeWisp {
  double x, y, vx, vy, size, life, opacity;
  _SmokeWisp({required this.x, required this.y, required this.vx, required this.vy,
    required this.size, required this.life, required this.opacity});
}

class _AuroraCurtain {
  double x, width, swayPhase, swaySpeed, swayAmp, hueShift;
  int ribbonCount;
  _AuroraCurtain({
    required this.x, required this.width, required this.swayPhase,
    required this.swaySpeed, required this.swayAmp, required this.hueShift,
    this.ribbonCount = 3,
  });
}

class _AuroraStar {
  double x, y, size, twinklePhase, twinkleSpeed;
  _AuroraStar({required this.x, required this.y, required this.size,
    required this.twinklePhase, required this.twinkleSpeed});
}

class _Bubble {
  double x, y, vx, vy, radius, life, wobble;
  _Bubble({required this.x, required this.y, required this.vx, required this.vy,
    required this.radius, required this.life, this.wobble = 0});
}

class _LightRay {
  double x, width, angle, intensity, speed;
  _LightRay({required this.x, required this.width, required this.angle,
    required this.intensity, required this.speed});
}

class _Caustic {
  double x, y, size, life, phase;
  _Caustic({required this.x, required this.y, required this.size,
    required this.life, required this.phase});
}

class _WaterDrop {
  double x, y, vx, vy, size, life;
  _WaterDrop({required this.x, required this.y, required this.vx, required this.vy,
    required this.size, required this.life});
}

class _Shockwave {
  double life;
  _Shockwave({required this.life});
}

class _WaterRipple {
  double x, y, radius = 0, maxRadius, life;
  _WaterRipple({required this.x, required this.y, required this.maxRadius, required this.life});
}

// ==================== 频谱柱体（霓虹渐变风格）====================

// Bars painter 缓存 Paint 对象，避免每帧 GC
final Paint _barsGlowPaint = Paint()..style = PaintingStyle.fill;
final Paint _barsBarPaint = Paint()..style = PaintingStyle.fill;
final Paint _barsReflectionPaint = Paint()..style = PaintingStyle.fill;
final Paint _barsLinePaint = Paint()..style = PaintingStyle.fill;

class _BarsPainter extends CustomPainter {
  final _AudioVisualizerState state;
  final int count;
  _BarsPainter({required this.state, required this.count, required super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    _paintBg(canvas, size, state._spectrum.volume);
    final w = size.width;
    final h = size.height;
    final freqs = state._spectrum.frequencies;
    if (freqs.isEmpty) return;

    final gap = w / (count + 1);
    final barW = gap * 0.58;
    final startX = gap;
    final baseY = h * 0.88;
    final maxBarH = h * 0.72;
    final vol = state._spectrum.volume;
    final bass = state._spectrum.bass;

    // 底部辉光（随低音脉动）
    final glowR = w * 0.45 + bass * w * 0.1;
    final glowA = 0.06 + vol * 0.10;
    _barsGlowPaint.shader = ui.Gradient.radial(
      Offset(w * 0.5, baseY + 4), glowR,
      [AppColors.primaryDark.withValues(alpha: glowA), AppColors.primaryDark.withValues(alpha: 0)],
    );
    canvas.drawCircle(Offset(w * 0.5, baseY + 4), glowR, _barsGlowPaint);

    for (int i = 0; i < count; i++) {
      final fi = (i * freqs.length / count).floor().clamp(0, freqs.length - 1);
      final value = freqs[fi];
      final x = startX + i * gap;
      final barH = max(2.0, maxBarH * value);

      // 渐变色：底部深色 → 顶部亮色
      final t = i / max(1, count - 1);
      final warm = AppColors.isDark ? const Color(0xFFE8A04C) : const Color(0xFFC9884A);
      final cool = AppColors.isDark ? const Color(0xFF64B5F6) : const Color(0xFF5B9BD5);
      final baseColor = Color.lerp(warm, cool, t)!;
      final barColor = baseColor.withValues(alpha: 0.6 + value * 0.4);

      // 柱体（渐变填充）
      final barRect = Rect.fromLTWH(x, baseY - barH, barW, barH);
      _barsBarPaint.shader = ui.Gradient.linear(
        Offset(0, baseY), Offset(0, baseY - barH),
        [
          barColor.withValues(alpha: 0.4),
          barColor,
          barColor.withValues(alpha: 0.9),
        ],
        [0.0, 0.6, 1.0],
      );
      final barPath = Path()
        ..addRRect(RRect.fromRectAndCorners(
          barRect,
          topLeft: Radius.circular(barW / 3),
          topRight: Radius.circular(barW / 3),
        ));
      canvas.drawPath(barPath, _barsBarPaint);

      // 柱体辉光（外层，无 blur 以避免 GPU 重绘）
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x - 2, baseY - barH - 2, barW + 4, barH + 4),
          topLeft: Radius.circular(barW / 3 + 2),
          topRight: Radius.circular(barW / 3 + 2),
        ),
        _pFill(barColor.withValues(alpha: 0.12 + value * 0.10)),
      );

      // 倒影（镜像，渐变消隐）
      final refH = barH * 0.55;
      final refRect = Rect.fromLTWH(x, baseY + 3, barW, refH);
      _barsReflectionPaint.shader = ui.Gradient.linear(
        Offset(0, baseY + 3), Offset(0, baseY + 3 + refH),
        [barColor.withValues(alpha: 0.18), barColor.withValues(alpha: 0)],
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          refRect,
          bottomLeft: Radius.circular(barW / 3),
          bottomRight: Radius.circular(barW / 3),
        ),
        _barsReflectionPaint,
      );

      // 峰值发光点
      final peak = state._peaks.length > fi ? state._peaks[fi] : value;
      final peakY = baseY - max(2.0, maxBarH * peak) - 6;
      final peakColor = baseColor.withValues(alpha: 0.9);
      // 辉光（无 blur）
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 3, peakY - 2, barW + 6, 7),
          const Radius.circular(3.5),
        ),
        _pFill(peakColor.withValues(alpha: 0.30)),
      );
      // 实心点
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, peakY, barW, 3),
          const Radius.circular(1.5),
        ),
        _pFill(peakColor),
      );
    }

    // 底部基线（渐变消隐）
    _barsLinePaint.shader = ui.Gradient.linear(
      Offset(w * 0.04, 0), Offset(w * 0.96, 0),
      [
        AppColors.primaryDark.withValues(alpha: 0),
        AppColors.primaryDark.withValues(alpha: 0.2),
        AppColors.primaryDark.withValues(alpha: 0),
      ],
      [0.0, 0.5, 1.0],
    );
    canvas.drawRect(Rect.fromLTWH(w * 0.04, baseY - 0.5, w * 0.92, 1), _barsLinePaint);
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) => true;
}

// ==================== 波浪（平滑流动风格）====================

final Paint _waveFillPaint = Paint()..style = PaintingStyle.fill;
final Paint _waveStrokePaint = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
// 复用的 Path 缓存：4 层波浪 × (1 主路径 + 1 填充路径) = 8 次 Path() 分配 → 0
final Path _wavePath = Path();
final Path _waveFillPath = Path();

class _WavePainter extends CustomPainter {
  final _AudioVisualizerState state;
  _WavePainter({required this.state, required super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    _paintBg(canvas, size, state._spectrum.volume);
    final w = size.width;
    final h = size.height;
    final bass = state._spectrum.bass;
    final vol = state._spectrum.volume;
    // 缓慢流动的时间基准（低频驱动）
    final t = state._frame * 0.025 + bass * 0.8;

    for (int layer = 0; layer < 4; layer++) {
      final path = _wavePath..reset();
      final yBase = h * (0.30 + layer * 0.15);
      // 振幅：随音量缓动，层间递减
      final baseAmp = h * 0.10 * (1 - layer * 0.10);
      final amp = baseAmp * (0.4 + vol * 0.6);
      final tColor = _freqColor(layer, 4, 0.28 - layer * 0.03);

      path.moveTo(0, yBase);
      for (double x = 0; x <= w; x += 6) {
        final p = x / w;
        // 主波：慢速平滑
        final y = yBase +
            sin(p * 3.0 * pi + t * (0.8 + layer * 0.15) + layer * 1.2) * amp * 0.7 +
            // 副波：更慢，增加层次
            sin(p * 1.8 * pi + t * 0.4 + layer * 0.6) * amp * 0.3;
        path.lineTo(x, y);
      }

      // 渐变填充到底部（复用 _waveFillPath）
      _waveFillPath
        ..reset()
        ..addPath(path, Offset.zero)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      _waveFillPaint.shader = ui.Gradient.linear(
        Offset(0, yBase - amp), Offset(0, h),
        [tColor, tColor.withValues(alpha: 0)],
      );
      canvas.drawPath(_waveFillPath, _waveFillPaint);
      // 描边
      _waveStrokePaint
        ..color = tColor.withValues(alpha: 0.65)
        ..strokeWidth = 2.0 - layer * 0.15;
      canvas.drawPath(path, _waveStrokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => true;
}

// ==================== 圆环 ====================

final Paint _circleInnerGlowPaint = Paint()..style = PaintingStyle.fill;
final Paint _circleRayPaint = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
final Paint _circleRayGlowPaint = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round
  ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

class _CirclePainter extends CustomPainter {
  final _AudioVisualizerState state;
  _CirclePainter({required this.state, required super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    _paintBg(canvas, size, state._spectrum.volume);
    final values = state._spectrum.frequencies;
    if (values.isEmpty) return;
    final center = Offset(size.width / 2, size.height * 0.50);
    final baseRadius = min(size.width, size.height) * 0.38;
    final rotation = state._frame * 0.015;
    final beatFlash = state._spectrum.beat;

    // 内圈辉光
    _circleInnerGlowPaint.shader = ui.Gradient.radial(
      center, baseRadius * 0.6,
      [AppColors.primaryDark.withValues(alpha: 0.15 + state._spectrum.bass * 0.1), AppColors.primaryDark.withValues(alpha: 0)],
    );
    canvas.drawCircle(center, baseRadius * 0.6, _circleInnerGlowPaint);

    // 频率射线
    final count = min(values.length, 64);
    for (int i = 0; i < count; i++) {
      final angle = (2 * pi / count) * i - pi / 2 + rotation;
      final v = values[i];
      final innerR = baseRadius * 0.42;
      final outerR = innerR + (baseRadius * 0.7) * v;
      final color = _freqColor(i, count, 0.4 + v * 0.6);

      _circleRayGlowPaint
        ..color = color.withValues(alpha: 0.4)
        ..strokeWidth = 3.5;
      canvas.drawLine(
        center + Offset(cos(angle), sin(angle)) * innerR,
        center + Offset(cos(angle), sin(angle)) * outerR,
        _circleRayGlowPaint,
      );
      _circleRayPaint
        ..color = color
        ..strokeWidth = 2.2;
      canvas.drawLine(
        center + Offset(cos(angle), sin(angle)) * innerR,
        center + Offset(cos(angle), sin(angle)) * outerR,
        _circleRayPaint,
      );
      if (v > 0.3) {
        final tip = center + Offset(cos(angle), sin(angle)) * outerR;
        canvas.drawCircle(tip, 1.0 + v * 1.2, _pFill(color.withValues(alpha: 0.9)));
      }
    }

    // 外圈
    final outerR = baseRadius * 1.2 + beatFlash * baseRadius * 0.1;
    canvas.drawCircle(center, outerR, _pStroke(AppColors.primaryDark.withValues(alpha: 0.4 + beatFlash * 0.3), 2.2));
    canvas.drawCircle(center, baseRadius * 0.38, _pStroke(AppColors.primaryDark.withValues(alpha: 0.25), 1.5));

    // 核心
    final coreR = 5 + state._spectrum.bass * 10;
    canvas.drawCircle(center, coreR + 3, _pGlow(AppColors.primaryDark.withValues(alpha: 0.4), 8));
    canvas.drawCircle(center, coreR, _pFill(AppColors.primaryDark.withValues(alpha: 0.85)));
  }

  @override
  bool shouldRepaint(covariant _CirclePainter old) => true;
}

// ==================== 脉冲（节拍驱动同心圆 + 冲击波）====================

final Paint _ringCorePaint = Paint()..style = PaintingStyle.fill;
final Paint _ringGlowPaint = Paint()..style = PaintingStyle.fill;
final Paint _ringStrokePaint = Paint()..style = PaintingStyle.stroke;
final Paint _ringLinePaint = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;

class _RingPainter extends CustomPainter {
  final _AudioVisualizerState state;
  _RingPainter({required this.state, required super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    _paintBg(canvas, size, state._spectrum.volume);
    final center = Offset(size.width / 2, size.height * 0.50);
    final maxR = min(size.width, size.height) * 0.42;
    final values = state._spectrum.frequencies;
    if (values.isEmpty) return;
    final bass = state._spectrum.bass;
    final beat = state._spectrum.beat;
    final vol = state._spectrum.volume;
    final t = state._frame * 0.02;

    // 核心辉光（随低音呼吸）
    final coreR = 6 + bass * 10;
    final coreGlowR = coreR + 8 + bass * 6;
    _ringGlowPaint.color = AppColors.primaryDark.withValues(alpha: 0.25 + bass * 0.15);
    canvas.drawCircle(center, coreGlowR, _ringGlowPaint);
    _ringCorePaint.color = AppColors.primaryDark.withValues(alpha: 0.8 + beat * 0.2);
    canvas.drawCircle(center, coreR, _ringCorePaint);

    // 同心频率环（6 层，每层对应一个频段）
    for (int i = 0; i < 6; i++) {
      final idx = (i * values.length / 6).floor().clamp(0, values.length - 1);
      final v = values[idx];
      // 缓慢呼吸 + 频率响应
      final breathe = 0.5 + 0.5 * sin(t * 0.8 + i * 1.1);
      final r = maxR * (0.15 + v * 0.50 + breathe * 0.08);
      final alpha = (0.55 - i * 0.06).clamp(0.2, 1.0);
      final color = _freqColor(i, 6, alpha);
      final strokeW = max(1.0, 2.5 + v * 2.0 - i * 0.15);

      // 辉光
      _ringGlowPaint.color = color.withValues(alpha: 0.25);
      canvas.drawCircle(center, r, _ringGlowPaint);
      // 实线
      _ringStrokePaint
        ..color = color
        ..strokeWidth = strokeW;
      canvas.drawCircle(center, r, _ringStrokePaint);
    }

    // 节拍冲击波（向外扩散）
    for (final wave in state._shockwaves) {
      final progress = 1.0 - wave.life;
      final r = maxR * (0.15 + progress * 1.3);
      final alpha = wave.life.clamp(0.0, 1.0);
      if (alpha > 0.02 && r > 0) {
        _ringGlowPaint.color = AppColors.primaryDark.withValues(alpha: alpha * 0.4);
        canvas.drawCircle(center, r, _ringGlowPaint);
        _ringStrokePaint
          ..color = AppColors.primaryDark.withValues(alpha: alpha * 0.7)
          ..strokeWidth = 2.0 * wave.life;
        canvas.drawCircle(center, r, _ringStrokePaint);
      }
      wave.life -= 0.016;
    }
    // 反向遍历就地移除死亡元素（避免 removeWhere 闭包分配）
    final sw = state._shockwaves;
    for (int i = sw.length - 1; i >= 0; i--) {
      if (sw[i].life <= 0) sw.removeAt(i);
    }

    // 外圈频率刻度（更细、更密）
    for (int i = 0; i < 48; i++) {
      final angle = (2 * pi / 48) * i + t * 0.15;
      final idx = (i * values.length / 48).floor().clamp(0, values.length - 1);
      final v = values[idx];
      final innerR = maxR * 0.85;
      final outerR = innerR + maxR * 0.12 * v;
      final color = _freqColor(i, 48, 0.2 + v * 0.55);
      _ringLinePaint
        ..color = color
        ..strokeWidth = 1.5;
      canvas.drawLine(
        center + Offset(cos(angle), sin(angle)) * innerR,
        center + Offset(cos(angle), sin(angle)) * outerR,
        _ringLinePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => true;
}

// ==================== 星尘宇宙 ====================

final Paint _particleCoreGlowPaint = Paint()..style = PaintingStyle.fill;
final Paint _particleFlarePaint = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
final Paint _particleConPaint = Paint()..style = PaintingStyle.stroke;

class _ParticlePainter extends CustomPainter {
  final _AudioVisualizerState state;
  _ParticlePainter({required this.state, required super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    _paintBg(canvas, size, state._spectrum.volume);
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final cy = h * 0.5;
    final spectrum = state._spectrum;
    final random = state._random;
    final frame = state._frame;

    // 中心天体脉冲
    final coreR = 8 + spectrum.bass * 22 + spectrum.volume * 8;
    _particleCoreGlowPaint.shader = ui.Gradient.radial(
      Offset(cx, cy), coreR * 2.5,
      [
        AppColors.primaryDark.withValues(alpha: 0.35 + spectrum.bass * 0.25),
        AppColors.primaryDark.withValues(alpha: 0.08),
        AppColors.primaryDark.withValues(alpha: 0),
      ],
      [0.0, 0.4, 1.0],
    );
    canvas.drawCircle(Offset(cx, cy), coreR * 2.5, _particleCoreGlowPaint);
    canvas.drawCircle(Offset(cx, cy), coreR, _pFill(AppColors.primaryDark.withValues(alpha: 0.6 + spectrum.bass * 0.3)));
    canvas.drawCircle(Offset(cx, cy), coreR * 0.45, _pFill(Colors.white.withValues(alpha: 0.7)));

    // 初始化恒星轨道（3圈，每圈 8 颗星）
    if (state._cosmicStars.isEmpty) {
      for (int ring = 0; ring < 3; ring++) {
        for (int i = 0; i < 8; i++) {
          state._cosmicStars.add(_CosmicStar(
            orbitRadius: 50 + ring * 55.0,
            angle: i * 2 * pi / 8 + ring * 0.3,
            speed: (0.015 - ring * 0.003) * (random.nextDouble() > 0.5 ? 1 : -1),
            size: 2.5 - ring * 0.5 + random.nextDouble() * 1.5,
            brightness: 0.7 - ring * 0.15,
            ring: ring,
          ));
        }
      }
    }

    // 更新 & 绘制恒星
    final freqs = spectrum.frequencies;
    for (final star in state._cosmicStars) {
      final freqIndex = freqs.isEmpty ? 0
          : (star.orbitRadius / 180 * (freqs.length - 1)).round().clamp(0, freqs.length - 1);
      final freqVal = freqs.isNotEmpty ? freqs[freqIndex] : 0.0;
      star.angle += star.speed + freqVal * 0.008;
      final breathe = 1.0 + spectrum.bass * 0.15;
      final px = cx + cos(star.angle) * star.orbitRadius * breathe;
      final py = cy + sin(star.angle) * star.orbitRadius * breathe;

      // 尾迹
      final trailLen = max(0.0, (sqrt(star.speed * star.speed) * 18 + freqVal * 8));
      if (trailLen > 2) {
        final trailPath = _cosmicTrailPath..reset();
        trailPath.moveTo(px, py);
        for (int t = 1; t <= 12; t++) {
          final ta = star.angle - star.speed * t * 1.5;
          final tr = star.orbitRadius * breathe - t * 0.8;
          trailPath.lineTo(cx + cos(ta) * tr, cy + sin(ta) * tr);
        }
        canvas.drawPath(trailPath, _pStroke(
          _freqColor(star.ring, 3, star.brightness * 0.3),
          star.size * 0.6,
        ));
      }

      // 星体
      final alpha = (star.brightness * (0.6 + freqVal * 0.4)).clamp(0.0, 1.0);
      final color = _freqColor(star.ring, 3, alpha);
      canvas.drawCircle(Offset(px, py), star.size * (1 + freqVal * 0.3), _pFill(color));

      // 十字星芒
      if (star.size > 2.5 && alpha > 0.5) {
        final flareLen = star.size * 3 * alpha;
        _particleFlarePaint
          ..color = color.withValues(alpha: alpha * 0.4)
          ..strokeWidth = 0.8;
        canvas.drawLine(Offset(px - flareLen, py), Offset(px + flareLen, py), _particleFlarePaint);
        canvas.drawLine(Offset(px, py - flareLen), Offset(px, py + flareLen), _particleFlarePaint);
      }
    }

    // 节拍爆发粒子
    if (spectrum.beat > 0.55 && state._particles.length < 120) {
      for (int i = 0; i < 30; i++) {
        final angle = random.nextDouble() * 2 * pi;
        final speed = 3.0 + random.nextDouble() * 5;
        state._particles.add(_Particle(
          x: cx, y: cy,
          vx: cos(angle) * speed, vy: sin(angle) * speed,
          size: 1.5 + random.nextDouble() * 3,
          life: 1.0, maxLife: 0.6 + random.nextDouble() * 0.5,
          hue: random.nextDouble(),
        ));
      }
    }

    // 更新爆发粒子
    for (final p in state._particles) {
      p.x += p.vx;
      p.y += p.vy;
      p.vx *= 0.965;
      p.vy *= 0.965;
      p.life -= 0.016 / p.maxLife;
    }
    final ps = state._particles;
    for (int i = ps.length - 1; i >= 0; i--) {
      if (ps[i].life <= 0) ps.removeAt(i);
    }

    // 绘制爆发粒子
    for (final p in state._particles) {
      final alpha = p.life.clamp(0.0, 1.0);
      final color = _freqColor((p.hue * 6).floor(), 6, alpha * 0.85);
      final radius = p.size * p.life;
      // 外晕
      canvas.drawCircle(Offset(p.x, p.y), radius * 3, _pFill(color.withValues(alpha: alpha * 0.08)));
      // 内核
      canvas.drawCircle(Offset(p.x, p.y), radius, _pFill(color));
    }

    // 恒星间连线（星座）
    final starPositions = state._cosmicStars.map((s) {
      final breathe = 1.0 + spectrum.bass * 0.15;
      return Offset(cx + cos(s.angle) * s.orbitRadius * breathe, cy + sin(s.angle) * s.orbitRadius * breathe);
    }).toList();
    for (int i = 0; i < starPositions.length; i++) {
      for (int j = i + 1; j < starPositions.length; j++) {
        final d = (starPositions[i] - starPositions[j]).distance;
        if (d < 90) {
          final alpha = (1.0 - d / 90) * 0.12;
          _particleConPaint
            ..color = AppColors.primaryDark.withValues(alpha: alpha)
            ..strokeWidth = 0.6;
          canvas.drawLine(starPositions[i], starPositions[j], _particleConPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) => true;
}

// ==================== 烈焰风暴 ====================

final Paint _flameBaseGlowPaint = Paint()..style = PaintingStyle.fill;
final Paint _flamePaint = Paint()..style = PaintingStyle.fill;
final Paint _flameTonguePaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.0;
final Paint _flameEmberPaint = Paint()..style = PaintingStyle.fill;
final Paint _flameSmokePaint = Paint()..style = PaintingStyle.fill;
final Paint _flameWavePaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.0;
// 复用的 Path 缓存：每帧 3 层 × 5 舌 = 15 次 Path() 分配 → 改为 reset()
final Path _flamePath1 = Path();
final Path _flamePath2 = Path();
final Path _flamePath3 = Path();
final Path _flameWavePath = Path(); // 复用：6 次/帧热浪 Path() 分配
final Path _cosmicTrailPath = Path(); // 复用：24 次/帧恒星尾迹 Path() 分配

// 静态常量配置：避免每帧分配 List<Map>
class _FlameLayerCfg {
  final Color colorInner;
  final Color colorOuter;
  final double baseHeight;
  final double baseWidth;
  final double speed;
  final double amp;
  const _FlameLayerCfg(this.colorInner, this.colorOuter, this.baseHeight, this.baseWidth, this.speed, this.amp);
}

const List<_FlameLayerCfg> _flameLayerConfigs = [
  _FlameLayerCfg(Colors.white, Color(0xFFFFCC44), 0.35, 0.06, 0.18, 0.02),
  _FlameLayerCfg(Color(0xFFFF8800), Color(0xFFCC3300), 0.28, 0.12, 0.12, 0.035),
  _FlameLayerCfg(Color(0xFFCC2200), Color(0xFF661100), 0.20, 0.20, 0.08, 0.04),
];

class _FlamePainter extends CustomPainter {
  final _AudioVisualizerState state;
  _FlamePainter({required this.state, required super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    _paintBg(canvas, size, state._spectrum.volume);
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final spectrum = state._spectrum;
    final random = state._random;
    final frame = state._frame;

    // ---- 底部辉光 ----
    final glowIntensity = 0.22 + spectrum.volume * 0.25 + spectrum.bass * 0.15;
    _flameBaseGlowPaint.shader = ui.Gradient.radial(
      Offset(cx, h * 0.95), w * 0.5,
      [
        AppColors.primaryDark.withValues(alpha: glowIntensity),
        AppColors.primaryDark.withValues(alpha: glowIntensity * 0.3),
        AppColors.primaryDark.withValues(alpha: 0),
      ],
      [0.0, 0.4, 1.0],
    );
    canvas.drawCircle(Offset(cx, h * 0.95), w * 0.5, _flameBaseGlowPaint);

    // ---- 火舌层 ----
    // 三层：内核(白金) → 中层(橙) → 外层(暗红)
    // 配置改用静态 const List（避免每帧分配 Map）

    for (int li = 0; li < _flameLayerConfigs.length; li++) {
      final cfg = _flameLayerConfigs[li];
      final colorInner = cfg.colorInner;
      final colorOuter = cfg.colorOuter;
      final baseH = cfg.baseHeight;
      final baseW = cfg.baseWidth;
      final spd = cfg.speed;
      final amp = cfg.amp;

      // 每层 5 条火舌
      for (int t = 0; t < 5; t++) {
        final tFrac = t / 4.0;
        final tongueX = cx + (tFrac - 0.5) * w * baseW * 2;
        final tongueBaseY = h * 0.88;
        final freqMult = 1.0 + spectrum.bass * 0.8 + spectrum.volume * 0.5;
        final tongueH = h * baseH * freqMult * (0.6 + random.nextDouble() * 0.4);
        final tongueW = w * baseW * (0.5 + random.nextDouble() * 0.5);
        final sway = sin(frame * spd + t * 1.7 + li * 0.8) * amp * w;

        final path = _flamePath1;
        path.reset();
        path.moveTo(tongueX - tongueW * 0.5, tongueBaseY);

        // 左侧贝塞尔
        path.cubicTo(
          tongueX - tongueW * 0.8, tongueBaseY - tongueH * 0.3,
          tongueX - tongueW * 0.3 + sway, tongueBaseY - tongueH * 0.7,
          tongueX + sway * 0.6, tongueBaseY - tongueH,
        );
        // 右侧贝塞尔
        path.cubicTo(
          tongueX + tongueW * 0.3 + sway, tongueBaseY - tongueH * 0.7,
          tongueX + tongueW * 0.8, tongueBaseY - tongueH * 0.3,
          tongueX + tongueW * 0.5, tongueBaseY,
        );
        path.close();

        // 渐变填充
        _flamePaint.shader = ui.Gradient.linear(
          Offset(tongueX, tongueBaseY),
          Offset(tongueX + sway * 0.6, tongueBaseY - tongueH),
          [
            colorInner.withValues(alpha: 0.0),
            colorInner.withValues(alpha: 0.35 + spectrum.bass * 0.15),
            colorOuter.withValues(alpha: 0.5 + spectrum.volume * 0.2),
            colorOuter.withValues(alpha: 0.0),
          ],
          [0.0, 0.3, 0.7, 1.0],
        );
        canvas.drawPath(path, _flamePaint);

        // 火舌轮廓（微弱光晕）
        _flameTonguePaint.color = colorInner.withValues(alpha: 0.12);
        canvas.drawPath(path, _flameTonguePaint);
      }
    }

    // ---- 飞火星 ----
    if (spectrum.beat > 0.45 && state._embers.length < 80) {
      for (int i = 0; i < 12; i++) {
        state._embers.add(_Ember(
          x: cx + (random.nextDouble() - 0.5) * w * 0.3,
          y: h * (0.75 + random.nextDouble() * 0.1),
          vx: (random.nextDouble() - 0.5) * 2.5,
          vy: -(3 + random.nextDouble() * 6 + spectrum.volume * 4),
          size: 1 + random.nextDouble() * 2.5,
          life: 1.0,
          maxLife: 0.5 + random.nextDouble() * 0.5,
        ));
      }
    }
    for (final e in state._embers) {
      e.x += e.vx + sin(frame * 0.15 + e.y * 0.02) * 0.8;
      e.y += e.vy;
      e.vy *= 0.985;
      e.vx *= 0.99;
      e.life -= 0.02 / e.maxLife;
    }
    final em = state._embers;
    for (int i = em.length - 1; i >= 0; i--) {
      if (em[i].life <= 0) em.removeAt(i);
    }

    for (final e in state._embers) {
      final alpha = e.life.clamp(0.0, 1.0);
      // 火星：白 → 黄 → 橙
      final color = Color.lerp(
        Colors.white,
        const Color(0xFFFFAA22),
        1.0 - alpha,
      )!;
      // 外晕
      _flameEmberPaint.color = color.withValues(alpha: alpha * 0.06);
      canvas.drawCircle(Offset(e.x, e.y), e.size * 4 * alpha, _flameEmberPaint);
      // 内核
      _flameEmberPaint.color = color.withValues(alpha: alpha * 0.9);
      canvas.drawCircle(Offset(e.x, e.y), e.size * alpha, _flameEmberPaint);
    }

    // ---- 烟雾 ----
    if (spectrum.volume > 0.05 && state._smokeWisps.length < 25) {
      state._smokeWisps.add(_SmokeWisp(
        x: cx + (random.nextDouble() - 0.5) * w * 0.15,
        y: h * (0.35 + random.nextDouble() * 0.1),
        vx: (random.nextDouble() - 0.5) * 0.6,
        vy: -(0.5 + random.nextDouble() * 1.2),
        size: 15 + random.nextDouble() * 25,
        life: 1.0,
        opacity: 0.08 + random.nextDouble() * 0.06,
      ));
    }
    for (final s in state._smokeWisps) {
      s.x += s.vx;
      s.y += s.vy;
      s.size += 0.6;
      s.life -= 0.008;
      s.opacity *= 0.995;
    }
    final sm = state._smokeWisps;
    for (int i = sm.length - 1; i >= 0; i--) {
      if (sm[i].life <= 0) sm.removeAt(i);
    }

    for (final s in state._smokeWisps) {
      final alpha = s.life.clamp(0.0, 1.0) * s.opacity;
      _flameSmokePaint.color = AppColors.isDark
          ? const Color(0xFF333333).withValues(alpha: alpha)
          : const Color(0xFF888888).withValues(alpha: alpha);
      canvas.drawCircle(Offset(s.x, s.y), s.size, _flameSmokePaint);
    }

    // ---- 热浪扭曲（底部水平波纹线）----
    _flameWavePaint.color = AppColors.primaryDark.withValues(alpha: 0.06 + spectrum.volume * 0.04);
    for (int i = 0; i < 6; i++) {
      final waveY = h * (0.82 + i * 0.025);
      final wavePath = _flameWavePath..reset();
      wavePath.moveTo(0, waveY);
      for (double x = 0; x <= w; x += 3) {
        final y = waveY + sin(x * 0.04 + frame * 0.12 + i * 0.8) * (3 + spectrum.bass * 4);
        wavePath.lineTo(x, y);
      }
      canvas.drawPath(wavePath, _flameWavePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FlamePainter old) => true;
}

// ==================== 极光（模糊光线）====================

final Paint _auroraPulsePaint = Paint()..style = PaintingStyle.fill;
final Paint _auroraBgGlowPaint = Paint(); // 缓存避免每帧分配
final Path _auroraRayPath = Path(); // 缓存：避免每帧 ~16 次 Path() 分配

class _AuroraPainter extends CustomPainter {
  final _AudioVisualizerState state;
  _AuroraPainter({required this.state, required super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    _paintBg(canvas, size, state._spectrum.volume);
    final w = size.width;
    final h = size.height;
    final spectrum = state._spectrum;
    final random = state._random;
    final frame = state._frame;
    final t = frame * 0.025;

    // 初始化模糊光线
    if (state._auroraCurtains.isEmpty) {
      for (int i = 0; i < 8; i++) {
        state._auroraCurtains.add(_AuroraCurtain(
          x: w * (0.05 + i * 0.12),
          width: w * (0.06 + random.nextDouble() * 0.1),
          swayPhase: random.nextDouble() * 2 * pi,
          swaySpeed: 0.04 + random.nextDouble() * 0.04,
          swayAmp: 25 + random.nextDouble() * 30,
          hueShift: i * 0.12,
          ribbonCount: 1,
        ));
      }
    }

    // 初始化星尘
    if (state._auroraStars.isEmpty) {
      for (int i = 0; i < 50; i++) {
        state._auroraStars.add(_AuroraStar(
          x: random.nextDouble() * w,
          y: random.nextDouble() * h,
          size: 0.5 + random.nextDouble() * 1.5,
          twinklePhase: random.nextDouble() * 2 * pi,
          twinkleSpeed: 0.03 + random.nextDouble() * 0.08,
        ));
      }
    }

// 背景微光（重用缓存 Paint，仅每帧更新 shader）
    _auroraBgGlowPaint.shader = ui.Gradient.radial(
      Offset(w * 0.5, h * 0.35), w * 0.8,
      [
        AppColors.primaryDark.withValues(alpha: 0.06 + spectrum.volume * 0.05),
        AppColors.primaryDark.withValues(alpha: 0),
      ],
    );
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), _auroraBgGlowPaint);

    // 绘制星尘
    for (final star in state._auroraStars) {
      final twinkle = 0.2 + 0.8 * ((sin(frame * star.twinkleSpeed + star.twinklePhase) + 1) / 2);
      final alpha = twinkle * (0.25 + spectrum.volume * 0.2);
      canvas.drawCircle(Offset(star.x, star.y), star.size * twinkle,
          _pFill(Colors.white.withValues(alpha: alpha)));
    }

    // 绘制模糊光线
    for (final ray in state._auroraCurtains) {
      final sway = sin(t * ray.swaySpeed * 12 + ray.swayPhase) * ray.swayAmp;
      final hueBase = (ray.hueShift + t * 0.015) % 1.0;
      final freqMult = 0.4 + spectrum.volume * 0.6 + spectrum.bass * 0.4;

      // 每条光线画多次，不同模糊度叠加出柔光效果（2 层，原 4 层过于昂贵）
      for (int layer = 0; layer < 2; layer++) {
        final layerFrac = layer / 1.0;
        final alpha = (0.15 - layerFrac * 0.04) * freqMult;
        final spread = ray.width * (1.0 + layerFrac * 1.5);

        final hue = (hueBase + layerFrac * 0.08) % 1.0;
        final color = HSVColor.fromAHSV(1.0, hue * 360, 0.65, 0.9).toColor();

        // 光线：从顶部到底部的垂直渐变矩形，带横向摆动
        final topX = ray.x + sway * 0.8;
        final botX = ray.x + sway * 0.3 + sin(t * ray.swaySpeed * 6 + layer) * spread * 0.3;
        final topY = h * (0.05 + layerFrac * 0.08);
        final botY = h * (0.65 + layerFrac * 0.1);

        final path = _auroraRayPath..reset();
        path.moveTo(topX - spread * 0.5, topY);
        path.lineTo(topX + spread * 0.5, topY);
        path.lineTo(botX + spread * 0.7, botY);
        path.lineTo(botX - spread * 0.7, botY);
        path.close();

        final paint = _auroraBlurCaches[layer]
          ..shader = ui.Gradient.linear(
            Offset(topX, topY), Offset(botX, botY),
            [
              color.withValues(alpha: 0.0),
              color.withValues(alpha: alpha),
              color.withValues(alpha: alpha * 0.8),
              color.withValues(alpha: alpha * 0.3),
              color.withValues(alpha: 0.0),
            ],
            [0.0, 0.15, 0.45, 0.8, 1.0],
          );
        canvas.drawPath(path, paint);
      }
    }

    // 节拍增亮脉冲
    if (spectrum.beat > 0.45) {
      final beatAlpha = (spectrum.beat - 0.45) * 0.5;
      _auroraPulsePaint.shader = ui.Gradient.radial(
        Offset(w * 0.5, h * 0.3), w * 0.6,
        [
          AppColors.primaryDark.withValues(alpha: beatAlpha * 0.25),
          AppColors.primaryDark.withValues(alpha: 0),
        ],
      );
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), _auroraPulsePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) => true;
}

// ==================== 深海涟漪 ====================

final Paint _waterDepthPaint = Paint()..style = PaintingStyle.fill;
final Paint _waterRayPaint = Paint()..style = PaintingStyle.fill;
final Paint _waterCausticPaint = Paint()..style = PaintingStyle.fill;
final Paint _waterWaveFillPaint = Paint()..style = PaintingStyle.fill;
final Paint _waterBubblePaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.0;
final Paint _waterDropPaint = Paint()..style = PaintingStyle.fill;
final Paint _waterDropTrailPaint = Paint()..style = PaintingStyle.stroke;
// 复用的 Path 缓存：避免每帧 5 次 Path() 分配（水波）+ 每次光线 Path() 分配
final Path _waterWavePath = Path();
final Path _waterWaveFillPath = Path();
final Path _waterRayPath = Path();

class _WaterPainter extends CustomPainter {
  final _AudioVisualizerState state;
  _WaterPainter({required this.state, required super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    _paintBg(canvas, size, state._spectrum.volume);
    final w = size.width;
    final h = size.height;
    final spectrum = state._spectrum;
    final random = state._random;
    final frame = state._frame;
    final t = frame * 0.04;

    // ---- 深海背景渐变 ----
    _waterDepthPaint.shader = ui.Gradient.linear(
      Offset(0, 0), Offset(0, h),
      [
        const Color(0xFF0A1628).withValues(alpha: 0.0),
        const Color(0xFF0A1628).withValues(alpha: 0.5),
        const Color(0xFF061020).withValues(alpha: 0.7),
      ],
      [0.0, 0.3, 1.0],
    );
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), _waterDepthPaint);

    // ---- 体积光（从顶部射入水中）----
    if (state._lightRays.isEmpty) {
      for (int i = 0; i < 6; i++) {
        state._lightRays.add(_LightRay(
          x: w * (0.1 + i * 0.15 + random.nextDouble() * 0.08),
          width: 8 + random.nextDouble() * 20,
          angle: -0.15 + random.nextDouble() * 0.3,
          intensity: 0.06 + random.nextDouble() * 0.06,
          speed: 0.02 + random.nextDouble() * 0.03,
        ));
      }
    }
    for (final ray in state._lightRays) {
      final sway = sin(t * ray.speed * 10 + ray.x * 0.01) * 15;
      final flicker = 0.7 + 0.3 * sin(frame * ray.speed + ray.x);
      final alpha = ray.intensity * flicker * (0.6 + spectrum.volume * 0.4);

      _waterRayPaint.shader = ui.Gradient.linear(
        Offset(ray.x + sway, 0),
        Offset(ray.x + sway + ray.angle * h, h),
        [
          AppColors.primaryDark.withValues(alpha: alpha * 1.5),
          AppColors.primaryDark.withValues(alpha: alpha * 0.6),
          AppColors.primaryDark.withValues(alpha: 0),
        ],
        [0.0, 0.4, 1.0],
      );
      final path = _waterRayPath..reset();
      path.moveTo(ray.x + sway - ray.width * 0.5, 0);
      path.lineTo(ray.x + sway + ray.width * 0.5, 0);
      path.lineTo(ray.x + sway + ray.angle * h + ray.width * 1.2, h);
      path.lineTo(ray.x + sway + ray.angle * h - ray.width * 0.3, h);
      path.close();
      canvas.drawPath(path, _waterRayPaint);
    }

    // ---- 焦散光斑（水底）----
    if (state._caustics.isEmpty) {
      for (int i = 0; i < 12; i++) {
        state._caustics.add(_Caustic(
          x: random.nextDouble() * w,
          y: h * (0.7 + random.nextDouble() * 0.25),
          size: 15 + random.nextDouble() * 35,
          life: 1.0,
          phase: random.nextDouble() * 2 * pi,
        ));
      }
    }
    for (final c in state._caustics) {
      c.life -= 0.005;
      c.x += sin(frame * 0.02 + c.phase) * 0.5;
      if (c.life <= 0) {
        c.x = random.nextDouble() * w;
        c.y = h * (0.7 + random.nextDouble() * 0.25);
        c.size = 15 + random.nextDouble() * 35;
        c.life = 1.0;
        c.phase = random.nextDouble() * 2 * pi;
      }
    }
    for (final c in state._caustics) {
      final alpha = c.life.clamp(0.0, 1.0) * (0.08 + spectrum.volume * 0.06);
      final pulse = 0.8 + 0.2 * sin(frame * 0.08 + c.phase);
      final s = c.size * pulse;

      // 焦散图案（交叉椭圆）
      _waterCausticPaint.color = AppColors.primaryDark.withValues(alpha: alpha);
      canvas.drawOval(Rect.fromCenter(center: Offset(c.x, c.y), width: s, height: s * 0.6), _waterCausticPaint);
      _waterCausticPaint.color = AppColors.primaryDark.withValues(alpha: alpha * 0.7);
      canvas.drawOval(Rect.fromCenter(center: Offset(c.x, c.y), width: s * 0.6, height: s), _waterCausticPaint);
    }

    // ---- 涟漪（节拍触发）----
    if (spectrum.beat > 0.35 && state._ripples.length < 12) {
      final count = (spectrum.beat * 2).ceil();
      for (int i = 0; i < count; i++) {
        state._ripples.add(_WaterRipple(
          x: w * 0.1 + random.nextDouble() * w * 0.8,
          y: h * (0.2 + random.nextDouble() * 0.3),
          maxRadius: 30 + random.nextDouble() * 100,
          life: 1.0,
        ));
      }
    }
    for (final r in state._ripples) {
      r.radius += 1.5 + spectrum.bass * 1.0;
      r.life -= 0.01;
    }
    final rp = state._ripples;
    for (int i = rp.length - 1; i >= 0; i--) {
      if (rp[i].life <= 0) rp.removeAt(i);
    }

    for (final r in state._ripples) {
      final alpha = r.life.clamp(0.0, 1.0);
      // 多层同心圆
      for (int ring = 0; ring < 3; ring++) {
        final ringFrac = ring / 2.0;
        final ringR = r.radius * (1.0 - ringFrac * 0.25);
        final ringAlpha = alpha * (0.4 - ringFrac * 0.12);
        final hue = (0.55 + ringFrac * 0.1) % 1.0;
        final color = HSVColor.fromAHSV(1.0, hue * 360, 0.5, 0.8).toColor();
        _waterBubblePaint
          ..color = color.withValues(alpha: ringAlpha)
          ..strokeWidth = 1.5 - ringFrac * 0.5;
        canvas.drawCircle(Offset(r.x, r.y), ringR, _waterBubblePaint);
      }
      _waterCausticPaint.color = AppColors.primaryDark.withValues(alpha: alpha * 0.6);
      canvas.drawCircle(Offset(r.x, r.y), 2, _waterCausticPaint);
    }

    // ---- 水面波浪（多层有机波）----
    final surfaceY = h * 0.18;
    for (int layer = 0; layer < 5; layer++) {
      final lFrac = layer / 4.0;
      final path = _waterWavePath..reset();
      final yBase = surfaceY + layer * h * 0.04;
      final amp = (6 + spectrum.volume * 14) * (1 - lFrac * 0.4);
      final freq1 = 3.0 + lFrac * 1.5;
      final freq2 = 7.0 + lFrac * 2;
      final speed1 = 0.8 + lFrac * 0.2;
      final speed2 = 1.5 + lFrac * 0.3;

      path.moveTo(0, yBase);
      for (double x = 0; x <= w; x += 2) {
        final p = x / w;
        final y = yBase +
            sin(p * freq1 + t * speed1 + layer * 0.6) * amp * (1 + spectrum.bass * 0.35) +
            sin(p * freq2 + t * speed2) * amp * 0.3 +
            sin(p * 12 + t * 2.2 + layer) * amp * 0.12;
        path.lineTo(x, y);
      }

      final waveHue = (0.5 + lFrac * 0.15) % 1.0;
      final color = HSVColor.fromAHSV(1.0, waveHue * 360, 0.5, 0.75).toColor();
      _waterWaveFillPaint.shader = ui.Gradient.linear(
        Offset(0, yBase - amp), Offset(0, yBase + h * 0.15),
        [color.withValues(alpha: 0.12 - lFrac * 0.02), color.withValues(alpha: 0)],
      );
      // 复用 _waterWaveFillPath：通过 addPath 复制主轨迹，然后追加底部封闭
      _waterWaveFillPath
        ..reset()
        ..addPath(path, Offset.zero)
        ..lineTo(w, yBase + h * 0.15)
        ..lineTo(0, yBase + h * 0.15)
        ..close();
      canvas.drawPath(_waterWaveFillPath, _waterWaveFillPaint);

      _waterBubblePaint
        ..color = color.withValues(alpha: 0.5 - lFrac * 0.08)
        ..strokeWidth = 1.8 - layer * 0.2
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, _waterBubblePaint);
    }

    // ---- 气泡 ----
    if (spectrum.volume > 0.05 && state._bubbles.length < 30) {
      state._bubbles.add(_Bubble(
        x: w * 0.1 + random.nextDouble() * w * 0.8,
        y: h * (0.85 + random.nextDouble() * 0.1),
        vx: (random.nextDouble() - 0.5) * 0.3,
        vy: -(0.4 + random.nextDouble() * 1.0 + spectrum.bass * 0.8),
        radius: 2 + random.nextDouble() * 5,
        life: 1.0,
      ));
    }
    for (final b in state._bubbles) {
      b.x += b.vx + sin(frame * 0.06 + b.y * 0.03) * 0.4;
      b.y += b.vy;
      b.vy *= 0.998;
      b.wobble = sin(frame * 0.1 + b.x * 0.05) * 2;
      b.life -= 0.004;
    }
    final bb = state._bubbles;
    for (int i = bb.length - 1; i >= 0; i--) {
      if (bb[i].life <= 0 || bb[i].y < 0) bb.removeAt(i);
    }

    for (final b in state._bubbles) {
      final alpha = b.life.clamp(0.0, 1.0);
      final bx = b.x + b.wobble;
      // 气泡外圈
      _waterBubblePaint
        ..color = AppColors.primaryDark.withValues(alpha: alpha * 0.35)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(Offset(bx, b.y), b.radius, _waterBubblePaint);
      // 高光点
      _waterCausticPaint.color = Colors.white.withValues(alpha: alpha * 0.45);
      canvas.drawCircle(Offset(bx - b.radius * 0.3, b.y - b.radius * 0.3), b.radius * 0.25, _waterCausticPaint);
    }

    // ---- 浮游粒子 ----
    _waterCausticPaint.color = AppColors.primaryDark.withValues(alpha: 0.15 + spectrum.volume * 0.1);
    for (int i = 0; i < 8; i++) {
      final px = (w * 0.5 + sin(frame * 0.01 + i * 1.3) * w * 0.35);
      final py = h * (0.3 + i * 0.07) + sin(frame * 0.02 + i * 0.8) * 8;
      canvas.drawCircle(Offset(px, py), 1.2, _waterCausticPaint);
    }

    // ---- 节拍水花 ----
    if (spectrum.beat > 0.6 && state._waterDrops.length < 40) {
      for (int i = 0; i < 15; i++) {
        state._waterDrops.add(_WaterDrop(
          x: w * 0.2 + random.nextDouble() * w * 0.6,
          y: surfaceY + 5,
          vx: (random.nextDouble() - 0.5) * 3,
          vy: -(4 + random.nextDouble() * 7),
          size: 1.5 + random.nextDouble() * 2.5,
          life: 1.0,
        ));
      }
    }
    for (final d in state._waterDrops) {
      d.x += d.vx;
      d.y += d.vy;
      d.vy += 0.15; // 重力
      d.life -= 0.025;
    }
    final wd = state._waterDrops;
    for (int i = wd.length - 1; i >= 0; i--) {
      if (wd[i].life <= 0) wd.removeAt(i);
    }

    final dropColor = HSVColor.fromAHSV(1.0, 200, 0.4, 0.85).toColor();
    for (final d in state._waterDrops) {
      final alpha = d.life.clamp(0.0, 1.0);
      _waterDropPaint.color = dropColor.withValues(alpha: alpha * 0.7);
      canvas.drawCircle(Offset(d.x, d.y), d.size * alpha, _waterDropPaint);
      // 拖尾
      if (d.vy.abs() > 1) {
        _waterDropTrailPaint
          ..color = dropColor.withValues(alpha: alpha * 0.3)
          ..strokeWidth = d.size * 0.5;
        canvas.drawLine(
          Offset(d.x, d.y),
          Offset(d.x - d.vx * 1.5, d.y - d.vy * 0.8),
          _waterDropTrailPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WaterPainter old) => true;
}
