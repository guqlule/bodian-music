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
  radial('放射'),
  mirror('镜像'),
  line('线条'),
  dot('点阵'),
  spiral('螺旋');

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

void _paintBg(Canvas canvas, Size size, double volume) {
  canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _pFill(AppColors.background));
}

class AudioVisualizer extends StatefulWidget {
  final int barCount;
  final VisualizerEffect effect;
  final Stream<SpectrumData> spectrumStream;
  final bool playing;
  final bool loading;
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
    this.loading = false,
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
  final List<_Shockwave> _shockwaves = [];
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

  void _syncTimer() {
    _timer ??= Timer.periodic(const Duration(milliseconds: 33), (_) {
      _tick();
    });
  }

  void _tick() {
    _frame++;
    if (widget.playing) {
      final alive = widget.isDataAlive?.call() ??
          DateTime.now().difference(_lastNativeData).inMilliseconds <= 1500;
      final staleMs = DateTime.now().difference(_lastNativeData).inMilliseconds;
      if (!alive) {
        if (!_staleNotified) {
          _staleNotified = true;
          _simActive = true;
          widget.onNativeStale?.call();
        }
        _updateSim();
      } else if (_simActive) {
        _simActive = false;
        _staleNotified = false;
        _simFreqs = [];
      } else {
        _staleNotified = false;
        if (staleMs > 1500) _lastNativeData = DateTime.now().subtract(const Duration(milliseconds: 100));
      }
    } else if (widget.loading) {
      if (!_simActive) {
        _simActive = true;
        _staleNotified = false;
      }
      _updateSimLoading();
    } else {
      _simActive = false;
      _staleNotified = false;
      _simFreqs = [];
    }
    _repaint.notifyListeners();
  }

  /// 加载中模拟：比正常模拟更柔和，振幅更低
  void _updateSimLoading() {
    final t = _frame * 0.03;
    final vol = 0.3 + 0.15 * sin(t * 0.7);
    if (_simFreqs.isEmpty) _simFreqs = List<double>.filled(64, 0);
    for (int i = 0; i < _simFreqs.length; i++) {
      final fi = i / _simFreqs.length;
      final low = sin(fi * 2.5 + t) * 0.5 + 0.5;
      final mid = sin(fi * 8 + t * 1.3) * 0.5 + 0.5;
      final v = (low * 0.7 + mid * 0.3) * vol;
      _simFreqs[i] = _simFreqs[i] * 0.7 + v.clamp(0.0, 1.0) * 0.3;
    }
    final bass = _simFreqs[2] + _simFreqs[3] * 0.5;
    _spectrum = SpectrumData(
      frequencies: _simFreqs,
      bass: bass.clamp(0.0, 1.0),
      mid: _simFreqs[20],
      treble: _simFreqs[50],
      volume: vol * 0.4,
      beat: 0,
    );
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
  }

  @override
  void didUpdateWidget(covariant AudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing || oldWidget.loading != widget.loading) {
      _syncTimer();
    }
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
      case VisualizerEffect.radial:
        return CustomPaint(painter: _RadialPainter(state: this, repaint: _repaint));
      case VisualizerEffect.mirror:
        return CustomPaint(painter: _MirrorPainter(state: this, count: min(widget.barCount, 64), repaint: _repaint));
      case VisualizerEffect.line:
        return CustomPaint(painter: _LinePainter(state: this, repaint: _repaint));
      case VisualizerEffect.dot:
        return CustomPaint(painter: _DotPainter(state: this, repaint: _repaint));
      case VisualizerEffect.spiral:
        return CustomPaint(painter: _SpiralPainter(state: this, repaint: _repaint));
    }
  }
}

class _Shockwave {
  double life;
  _Shockwave({required this.life});
}

// ==================== 频谱柱体（霓虹渐变风格）====================

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
    final baseY = h * 0.88;
    final vol = state._spectrum.volume;
    final bass = state._spectrum.bass;
    final maxBarH = h * 0.72;

    final useSim = freqs.isEmpty;
    final simPhase = state._frame * 0.06;

    final gap = w / (count + 1);
    final barW = gap * 0.58;
    final startX = gap;

    for (int i = 0; i < count; i++) {
      int fi = 0;
      double value;
      if (useSim) {
        final ti = i / (count - 1);
        value = (0.4 + 0.5 * sin(ti * 6 + simPhase) + 0.1 * sin(ti * 13 - simPhase * 2))
            .clamp(0.15, 1.0);
      } else {
        fi = (i * freqs.length / count).floor().clamp(0, freqs.length - 1);
        value = freqs[fi];
      }
      final x = startX + i * gap;
      final barH = max(2.0, maxBarH * value);

      final t = i / max(1, count - 1);
      final warm = AppColors.isDark ? const Color(0xFFE8A04C) : const Color(0xFFC9884A);
      final cool = AppColors.isDark ? const Color(0xFF64B5F6) : const Color(0xFF5B9BD5);
      final wr = (warm.r * 255).round();
      final wg = (warm.g * 255).round();
      final wb = (warm.b * 255).round();
      final cr = (cool.r * 255).round();
      final cg = (cool.g * 255).round();
      final cb = (cool.b * 255).round();
      final br = (wr + (cr - wr) * t).round();
      final bg = (wg + (cg - wg) * t).round();
      final bb = (wb + (cb - wb) * t).round();
      final barColor = Color.fromARGB(
        ((0.6 + value * 0.4) * 255).round(), br, bg, bb,
      );

      final barRect = Rect.fromLTWH(x, baseY - barH, barW, barH);
      _barsBarPaint.shader = ui.Gradient.linear(
        Offset(0, baseY), Offset(0, baseY - barH),
        [
          Color.fromARGB(((0.6 + value * 0.4) * 0.4 * 255).round(), br, bg, bb),
          Color.fromARGB(((0.6 + value * 0.4) * 255).round(), br, bg, bb),
          Color.fromARGB(((0.6 + value * 0.4) * 0.9 * 255).round(), br, bg, bb),
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

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x - 2, baseY - barH - 2, barW + 4, barH + 4),
          topLeft: Radius.circular(barW / 3 + 2),
          topRight: Radius.circular(barW / 3 + 2),
        ),
        _pFill(barColor.withValues(alpha: 0.12 + value * 0.10)),
      );

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

      final peak = useSim ? value : (state._peaks.length > fi ? state._peaks[fi] : value);
      final peakY = baseY - max(2.0, maxBarH * peak) - 6;
      final peakA = ((0.6 + value * 0.4) * 0.9 * 255).round();
      final peakColor = Color.fromARGB(peakA, br, bg, bb);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 3, peakY - 2, barW + 6, 7),
          const Radius.circular(3.5),
        ),
        _pFill(Color.fromARGB(((0.6 + value * 0.4) * 0.30 * 255).round(), br, bg, bb)),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, peakY, barW, 3),
          const Radius.circular(1.5),
        ),
        _pFill(peakColor),
      );
    }

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
    final t = state._frame * 0.025 + bass * 0.8;

    for (int layer = 0; layer < 4; layer++) {
      final path = _wavePath..reset();
      final yBase = h * (0.30 + layer * 0.15);
      final baseAmp = h * 0.10 * (1 - layer * 0.10);
      final amp = baseAmp * (0.4 + vol * 0.6);
      final tColor = _freqColor(layer, 4, 0.28 - layer * 0.03);

      path.moveTo(0, yBase);
      for (double x = 0; x <= w; x += 6) {
        final p = x / w;
        final y = yBase +
            sin(p * 3.0 * pi + t * (0.8 + layer * 0.15) + layer * 1.2) * amp * 0.7 +
            sin(p * 1.8 * pi + t * 0.4 + layer * 0.6) * amp * 0.3;
        path.lineTo(x, y);
      }

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

    _circleInnerGlowPaint.shader = ui.Gradient.radial(
      center, baseRadius * 0.6,
      [AppColors.primaryDark.withValues(alpha: 0.15 + state._spectrum.bass * 0.1), AppColors.primaryDark.withValues(alpha: 0)],
    );
    canvas.drawCircle(center, baseRadius * 0.6, _circleInnerGlowPaint);

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

    final outerR = baseRadius * 1.2 + beatFlash * baseRadius * 0.1;
    canvas.drawCircle(center, outerR, _pStroke(AppColors.primaryDark.withValues(alpha: 0.4 + beatFlash * 0.3), 2.2));
    canvas.drawCircle(center, baseRadius * 0.38, _pStroke(AppColors.primaryDark.withValues(alpha: 0.25), 1.5));

    final coreR = 5 + state._spectrum.bass * 10;
    canvas.drawCircle(center, coreR + 3, _pGlow(AppColors.primaryDark.withValues(alpha: 0.4), 8));
    canvas.drawCircle(center, coreR, _pFill(AppColors.primaryDark.withValues(alpha: 0.85)));
  }

  @override
  bool shouldRepaint(covariant _CirclePainter old) => true;
}

// ==================== 放射（圆形频谱柱体）====================

final Paint _radialBarPaint = Paint()..style = PaintingStyle.fill;
final Paint _radialGlowPaint = Paint()..style = PaintingStyle.fill;
final Paint _radialCorePaint = Paint()..style = PaintingStyle.fill;
final Paint _radialLinePaint = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;

class _RadialPainter extends CustomPainter {
  final _AudioVisualizerState state;
  _RadialPainter({required this.state, required super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    _paintBg(canvas, size, state._spectrum.volume);
    final center = Offset(size.width / 2, size.height * 0.50);
    final maxR = min(size.width, size.height) * 0.40;
    final values = state._spectrum.frequencies;
    final bass = state._spectrum.bass;
    final vol = state._spectrum.volume;
    final t = state._frame * 0.012;

    _radialGlowPaint.shader = ui.Gradient.radial(
      center, maxR * 0.35,
      [AppColors.primaryDark.withValues(alpha: 0.12 + bass * 0.08), AppColors.primaryDark.withValues(alpha: 0)],
    );
    canvas.drawCircle(center, maxR * 0.35, _radialGlowPaint);

    final coreR = 5 + bass * 8;
    canvas.drawCircle(center, coreR + 4, _pGlow(AppColors.primaryDark.withValues(alpha: 0.3), 6));
    canvas.drawCircle(center, coreR, _pFill(AppColors.primaryDark.withValues(alpha: 0.7)));

    if (values.isEmpty) {
      canvas.drawCircle(center, maxR * 0.82, _pStroke(AppColors.primaryDark.withValues(alpha: 0.1), 1));
      return;
    }

    final barCount = min(values.length, 64);
    final innerR = maxR * 0.28;
    final maxBarH = maxR * 0.55;

    for (int i = 0; i < barCount; i++) {
      final angle = (2 * pi / barCount) * i - pi / 2 + t;
      final v = values[i];
      final barH = max(1.5, maxBarH * v);

      final color = _freqColor(i, barCount, 0.45 + v * 0.55);

      final p1 = center + Offset(cos(angle), sin(angle)) * innerR;
      final p2 = center + Offset(cos(angle), sin(angle)) * (innerR + barH);

      _radialGlowPaint.color = color.withValues(alpha: 0.2);
      canvas.drawLine(p1, center + Offset(cos(angle), sin(angle)) * (innerR + barH + 3), _radialGlowPaint);
      _radialLinePaint
        ..color = color
        ..strokeWidth = max(1.5, (2 * pi * (innerR + barH * 0.5) / barCount) * 0.35);
      canvas.drawLine(p1, p2, _radialLinePaint);
    }

    final outerR = maxR * 0.82 + vol * maxR * 0.05;
    canvas.drawCircle(center, outerR, _pStroke(AppColors.primaryDark.withValues(alpha: 0.2 + vol * 0.15), 1.2));
  }

  @override
  bool shouldRepaint(covariant _RadialPainter old) => true;
}

// ==================== 镜像（对称频谱柱体）====================

final Paint _mirrorBarPaint = Paint()..style = PaintingStyle.fill;
final Paint _mirrorGlowPaint = Paint()..style = PaintingStyle.fill;

class _MirrorPainter extends CustomPainter {
  final _AudioVisualizerState state;
  final int count;
  _MirrorPainter({required this.state, required this.count, required super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    _paintBg(canvas, size, state._spectrum.volume);
    final w = size.width;
    final h = size.height;
    final freqs = state._spectrum.frequencies;
    final cy = h * 0.50;
    final vol = state._spectrum.volume;
    final maxBarH = h * 0.40;

    final useSim = freqs.isEmpty;
    final simPhase = state._frame * 0.06;

    final gap = w / (count + 1);
    final barW = gap * 0.50;
    final startX = gap;

    for (int i = 0; i < count; i++) {
      int fi = 0;
      double value;
      if (useSim) {
        final ti = i / (count - 1);
        value = (0.3 + 0.5 * sin(ti * 5 + simPhase) + 0.2 * sin(ti * 11 - simPhase * 1.5))
            .clamp(0.1, 1.0);
      } else {
        fi = (i * freqs.length / count).floor().clamp(0, freqs.length - 1);
        value = freqs[fi];
      }
      final x = startX + i * gap;
      final barH = max(1.5, maxBarH * value);

      final t = i / max(1, count - 1);
      final color = _freqColor(i, count, 0.5 + value * 0.5);

      // 上半柱体
      final topRect = Rect.fromLTWH(x, cy - barH, barW, barH);
      _mirrorBarPaint.shader = ui.Gradient.linear(
        Offset(0, cy), Offset(0, cy - barH),
        [color.withValues(alpha: 0.3), color],
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(topRect, topLeft: Radius.circular(barW / 3), topRight: Radius.circular(barW / 3)),
        _mirrorBarPaint,
      );
      // 下半镜像
      final botRect = Rect.fromLTWH(x, cy + 2, barW, barH);
      _mirrorBarPaint.shader = ui.Gradient.linear(
        Offset(0, cy + 2), Offset(0, cy + 2 + barH),
        [color, color.withValues(alpha: 0.15)],
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(botRect, bottomLeft: Radius.circular(barW / 3), bottomRight: Radius.circular(barW / 3)),
        _mirrorBarPaint,
      );
      // 辉光
      if (value > 0.5) {
        _mirrorGlowPaint.color = color.withValues(alpha: (value - 0.5) * 0.15);
        canvas.drawRect(Rect.fromLTWH(x - 2, cy - barH - 2, barW + 4, barH * 2 + 6), _mirrorGlowPaint);
      }
    }

    // 中线
    canvas.drawLine(Offset(w * 0.04, cy), Offset(w * 0.96, cy),
        _pStroke(AppColors.primaryDark.withValues(alpha: 0.15), 0.8));
  }

  @override
  bool shouldRepaint(covariant _MirrorPainter old) => true;
}

// ==================== 线条（连续波形线）====================

final Paint _lineWavePaint = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
final Paint _lineGlowPaint = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
final Path _linePath = Path();
final Path _lineFillPath = Path();

class _LinePainter extends CustomPainter {
  final _AudioVisualizerState state;
  _LinePainter({required this.state, required super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    _paintBg(canvas, size, state._spectrum.volume);
    final w = size.width;
    final h = size.height;
    final freqs = state._spectrum.frequencies;
    final cy = h * 0.50;
    final vol = state._spectrum.volume;
    final t = state._frame * 0.03;

    // 绘制两条线：主线 + 影子线
    for (int pass = 0; pass < 2; pass++) {
      final path = _linePath..reset();
      final amplitude = h * 0.30 * (0.3 + vol * 0.7);
      final yBase = cy + (pass == 1 ? 8 : 0);

      path.moveTo(0, yBase);
      for (double x = 0; x <= w; x += 3) {
        final p = x / w;
        double y;
        if (freqs.isEmpty) {
          // 模拟：柔和正弦波
          y = yBase + sin(p * 4 * pi + t * 1.2) * amplitude * 0.3 * (pass == 0 ? 1.0 : 0.6);
        } else {
          // 用频率数据驱动波形
          final fi = (p * (freqs.length - 1)).round().clamp(0, freqs.length - 1);
          final v = freqs[fi];
          final wave = sin(p * 3 * pi + t) * amplitude * 0.3;
          final freq = v * amplitude * 0.7;
          y = yBase + wave + (p < 0.5 ? -freq : freq);
        }
        path.lineTo(x, y);
      }

      if (pass == 0) {
        // 主线：渐变色
        _lineWavePaint
          ..color = _freqColor(0, 1, 0.7)
          ..strokeWidth = 2.5;
        // 辉光
        _lineGlowPaint
          ..color = _freqColor(0, 1, 0.2)
          ..strokeWidth = 8;
        canvas.drawPath(path, _lineGlowPaint);
        canvas.drawPath(path, _lineWavePaint);
      } else {
        // 影子线：更淡
        _lineWavePaint
          ..color = _freqColor(2, 4, 0.25)
          ..strokeWidth = 1.2;
        canvas.drawPath(path, _lineWavePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => true;
}

// ==================== 点阵（网格脉动）====================

final Paint _dotPaint = Paint()..style = PaintingStyle.fill;

class _DotPainter extends CustomPainter {
  final _AudioVisualizerState state;
  _DotPainter({required this.state, required super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    _paintBg(canvas, size, state._spectrum.volume);
    final w = size.width;
    final h = size.height;
    final freqs = state._spectrum.frequencies;
    final vol = state._spectrum.volume;
    final t = state._frame * 0.04;

    const cols = 16;
    const rows = 24;
    final dotSpacingX = w / (cols + 1);
    final dotSpacingY = h / (rows + 1);
    final maxRadius = min(dotSpacingX, dotSpacingY) * 0.35;

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final cx = dotSpacingX * (col + 1);
        final cy = dotSpacingY * (row + 1);
        final nx = col / (cols - 1);
        final ny = row / (rows - 1);

        double intensity;
        if (freqs.isEmpty) {
          // 模拟：圆形扩散波
          final dist = sqrt((nx - 0.5) * (nx - 0.5) + (ny - 0.5) * (ny - 0.5));
          final wave = sin(dist * 12 - t * 2) * 0.5 + 0.5;
          intensity = wave * vol * 0.8;
        } else {
          // 用频率数据驱动：行→频段，列→位置衰减
          final fi = (ny * (freqs.length - 1)).round().clamp(0, freqs.length - 1);
          final fv = freqs[fi];
          final edgeFade = 1.0 - (nx - 0.5).abs() * 1.2;
          intensity = fv * edgeFade.clamp(0.0, 1.0);
        }

        final radius = max(0.8, maxRadius * (0.15 + intensity * 0.85));
        final alpha = (0.2 + intensity * 0.8).clamp(0.0, 1.0);
        final color = _freqColor(col + row, cols + rows, alpha);

        // 外晕
        if (intensity > 0.3) {
          _dotPaint.color = color.withValues(alpha: alpha * 0.1);
          canvas.drawCircle(Offset(cx, cy), radius * 2.5, _dotPaint);
        }
        // 实心点
        _dotPaint.color = color;
        canvas.drawCircle(Offset(cx, cy), radius, _dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotPainter old) => true;
}

// ==================== 螺旋（旋转频率螺旋）====================

final Paint _spiralLinePaint = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;

class _SpiralPainter extends CustomPainter {
  final _AudioVisualizerState state;
  _SpiralPainter({required this.state, required super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    _paintBg(canvas, size, state._spectrum.volume);
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final cy = h * 0.50;
    final freqs = state._spectrum.frequencies;
    final vol = state._spectrum.volume;
    final bass = state._spectrum.bass;
    final t = state._frame * 0.015;
    final maxR = min(w, h) * 0.42;

    // 绘制 3 条螺旋线（相位偏移 120°）
    for (int arm = 0; arm < 3; arm++) {
      final armOffset = arm * 2 * pi / 3;
      final points = <Offset>[];

      for (double a = 0; a < 4 * pi; a += 0.08) {
        final progress = a / (4 * pi); // 0→1 从中心到外围
        final radius = maxR * 0.15 + maxR * 0.80 * progress;

        double freqVal;
        if (freqs.isEmpty) {
          freqVal = (sin(a * 2 + t * 3 + arm) * 0.5 + 0.5) * vol * 0.7;
        } else {
          final fi = (progress * (freqs.length - 1)).round().clamp(0, freqs.length - 1);
          freqVal = freqs[fi];
        }

        final wobble = freqVal * maxR * 0.08 * sin(a * 6 + t * 4 + arm);
        final angle = a + t + armOffset;
        final r = radius + wobble;
        points.add(Offset(cx + cos(angle) * r, cy + sin(angle) * r));
      }

      if (points.length < 2) continue;

      // 绘制螺旋线
      final alpha = 0.45 + vol * 0.35;
      final color = _freqColor(arm, 3, alpha);
      _spiralLinePaint
        ..color = color
        ..strokeWidth = 1.8 + bass * 1.2;
      final path = Path()..moveTo(points[0].dx, points[0].dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, _spiralLinePaint);

      // 辉光
      _spiralLinePaint
        ..color = color.withValues(alpha: 0.15)
        ..strokeWidth = 5.0;
      canvas.drawPath(path, _spiralLinePaint);
    }

    // 中心点
    final coreR = 3 + bass * 6;
    canvas.drawCircle(Offset(cx, cy), coreR + 3, _pGlow(AppColors.primaryDark.withValues(alpha: 0.25), 5));
    canvas.drawCircle(Offset(cx, cy), coreR, _pFill(AppColors.primaryDark.withValues(alpha: 0.6)));
  }

  @override
  bool shouldRepaint(covariant _SpiralPainter old) => true;
}
