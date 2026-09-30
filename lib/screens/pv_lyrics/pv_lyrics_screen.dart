import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/audio/audio_analysis_service.dart';
import '../../services/lyric/lyric_parser.dart';
import '../../widgets/large_ktv_overlay.dart' show LerpScanText;

class PvLyricsScreen extends ConsumerStatefulWidget {
  const PvLyricsScreen({super.key});
  @override
  ConsumerState<PvLyricsScreen> createState() => _PvLyricsScreenState();
}

class _PvLyricsScreenState extends ConsumerState<PvLyricsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _bgController;
  final List<_Meteor> _meteors = [];
  final _random = Random();
  List<LyricLine> _parsedLyrics = [];
  LyricLine? _currentLine;
  LyricLine? _nextLine;
  int _currentIndex = -1;
  double _currentProgress = 0;
  StreamSubscription<SpectrumData>? _spectrumSub;
  List<double> _frequencies = [];
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(hours: 1),
    )..repeat();
    for (int i = 0; i < 12; i++) {
      _meteors.add(_Meteor.random(_random));
    }
    _spectrumSub = ref.read(audioAnalysisProvider).spectrumStream.listen((data) {
      if (mounted) setState(() => _frequencies = data.frequencies);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLyric();
    });
  }

  void _initLyric() {
    final lyricMap = ref.read(lyricProvider).valueOrNull;
    final lyricText = lyricMap?['lyric'] ?? '';
    if (lyricText.isNotEmpty) {
      _parsedLyrics = LyricParser.parse(lyricText);
    }
  }

  void _updatePosition(Duration position) {
    _position = position;
    if (_parsedLyrics.isEmpty) return;
    int newIdx = -1;
    for (int i = _parsedLyrics.length - 1; i >= 0; i--) {
      if (position >= _parsedLyrics[i].time) {
        newIdx = i;
        break;
      }
    }
    if (newIdx >= 0) {
      _currentLine = _parsedLyrics[newIdx];
      _nextLine = (newIdx + 1 < _parsedLyrics.length) ? _parsedLyrics[newIdx + 1] : null;
      if (newIdx != _currentIndex) {
        _currentIndex = newIdx;
      }
      _calcProgress(position, _parsedLyrics[newIdx]);
    }
  }

  void _calcProgress(Duration position, LyricLine line) {
    final nextTime = _nextLine?.time ?? (line.time + const Duration(seconds: 4));
    final total = nextTime - line.time;
    if (total.inMilliseconds <= 0) {
      _currentProgress = 1.0;
      return;
    }
    final elapsed = position - line.time;
    _currentProgress = (elapsed.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _spectrumSub?.cancel();
    _bgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final isPlaying = ref.watch(isPlayingProvider).valueOrNull ?? false;

    if (position != _position) {
      _updatePosition(position);
    }

    ref.listen(lyricProvider, (prev, next) {
      final lyricText = next.valueOrNull?['lyric'] ?? '';
      if (lyricText.isNotEmpty) {
        _parsedLyrics = LyricParser.parse(lyricText);
        _currentIndex = -1;
        _currentLine = null;
        _nextLine = null;
      }
    });

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: AnimatedBuilder(
          animation: _bgController,
          builder: (context, _) {
            return CustomPaint(
              painter: _BgPainter(
                time: _bgController.value,
                meteors: _meteors,
                isPlaying: isPlaying,
                frequencies: _frequencies,
              ),
              size: Size.infinite,
              child: SafeArea(
                child: Column(
                  children: [
                    _buildTopBar(),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Center(
                          child: _buildLyric(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final music = ref.watch(currentMusicProvider).valueOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 20, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                size: 32, color: Colors.white70),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  music?.name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if ((music?.singer ?? '').isNotEmpty)
                  Text(
                    music!.singer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLyric() {
    if (_currentLine == null) {
      final music = ref.read(currentMusicProvider).valueOrNull;
      final artUrl = music?.imgUrl;
      final hasArt = artUrl != null && artUrl.isNotEmpty;
      // 歌名/歌手已在顶栏显示，这里只放封面 + 状态
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasArt)
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.network(
                artUrl,
                width: 180,
                height: 180,
                fit: BoxFit.cover,
                cacheWidth: 360,
                errorBuilder: (_, __, ___) => _placeholderArt(),
              ),
            )
          else
            _placeholderArt(),
          const SizedBox(height: 24),
          Text(
            '暂无歌词',
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.35),
              letterSpacing: 1,
            ),
          ),
        ],
      );
    }

    return _buildLyricList();
  }

  /// 歌词列表容器。
  ///
  /// 窗口化列表（只渲染当前行附近几行）内容是瞬时替换的，
  /// 这里叠加一层「换行时的轻微上下位移」作为过渡，让行切换有滑动感。
  Widget _buildLyricList() {
    return _LineShiftTransition(
      token: _currentIndex,
      child: _buildLyricRows(),
    );
  }

  Widget _buildLyricRows() {
    final count = _parsedLyrics.length;
    // 当前行固定在列表正中：索引 2
    const centerSlot = 2;
    // 上下各留几行，超出的裁掉
    final start = (_currentIndex - centerSlot).clamp(0, count);
    final end = (start + 5).clamp(0, count);
    final visible = <int>[];
    for (int i = start; i < end; i++) {
      visible.add(i);
    }

    // 主歌词字号随文本长度自适应，长句自动缩小避免溢出
    final cur = _currentLine!;
    final curLen = cur.text.length;
    final mainFontSize = curLen <= 8
        ? 44.0
        : curLen <= 14
            ? 38.0
            : curLen <= 20
                ? 32.0
                : 26.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final i in visible)
          // key 保证行在树中的位置稳定，让 AnimatedSize/Opacity 平滑过渡
          _AnimatedLyricRow(
            key: ValueKey(i),
            index: i,
            line: _parsedLyrics[i],
            isCurrent: i == _currentIndex,
            distance: (i - _currentIndex).abs(),
            mainFontSize: mainFontSize,
            onSeek: (t) => ref.read(playerServiceProvider).seek(t),
            child: i == _currentIndex && _parsedLyrics[i].hasWords
                ? _buildWordByWordText(_parsedLyrics[i], mainFontSize)
                : i == _currentIndex
                    ? LerpScanText(
                        text: _parsedLyrics[i].text,
                        progress: _currentProgress,
                        scannedColor: AppColors.primaryDark,
                        unscannedColor: Colors.white.withValues(alpha: 0.3),
                        fontSize: mainFontSize,
                        fontWeight: FontWeight.w900,
                      )
                    : Text(
                        _parsedLyrics[i].text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: mainFontSize,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
          ),
      ],
    );
  }

  Widget _placeholderArt() {
    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(24),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.music_note_rounded, color: Colors.white24, size: 72),
    );
  }

  Widget _buildWordByWordText(LyricLine line, double fontSize) {
    final words = line.words!;
    final spans = <TextSpan>[];

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final wordEnd = word.duration != null
          ? word.time + word.duration!
          : word.time + const Duration(seconds: 1);

      double wordProgress;
      if (_position < word.time) {
        wordProgress = 0.0;
      } else if (_position >= wordEnd) {
        wordProgress = 1.0;
      } else {
        final total = wordEnd - word.time;
        wordProgress = total.inMilliseconds > 0
            ? ((_position - word.time).inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
            : 1.0;
      }

      // 已唱部分：主题色 + 辉光；未唱部分：淡白
      final sung = Color.lerp(
        AppColors.primaryDark,
        Colors.white,
        wordProgress * 0.15,
      )!;
      final unsung = Colors.white.withValues(alpha: 0.28);
      final color = Color.lerp(unsung, sung, wordProgress)!;

      final shadow = wordProgress > 0.05
          ? [
              Shadow(
                color: AppColors.primaryDark.withValues(alpha: 0.75 * wordProgress),
                blurRadius: 26 * wordProgress,
              ),
              Shadow(
                color: AppColors.primary.withValues(alpha: 0.35 * wordProgress),
                blurRadius: 8 * wordProgress,
                offset: const Offset(0, 2),
              ),
            ]
          : null;

      spans.add(TextSpan(
        text: word.text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          height: 1.3,
          fontWeight: FontWeight.w900,
          shadows: shadow,
        ),
      ));
    }

    return RichText(
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      text: TextSpan(
        children: spans,
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900, height: 1.3),
      ),
    );
  }
}

class _BgPainter extends CustomPainter {
  final double time;
  final List<_Meteor> meteors;
  final bool isPlaying;
  final List<double> frequencies;

  _BgPainter({required this.time, required this.meteors, required this.isPlaying, this.frequencies = const []});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final hue = (220 + time * 60) % 360;

    // 背景
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()
      ..shader = ui.Gradient.linear(Offset(0, 0), Offset(0, h), [
        HSLColor.fromAHSL(1.0, hue, 0.3, 0.04).toColor(),
        HSLColor.fromAHSL(1.0, (hue + 30) % 360, 0.35, 0.03).toColor(),
        HSLColor.fromAHSL(1.0, (hue + 60) % 360, 0.3, 0.06).toColor(),
      ], [0.0, 0.5, 1.0]));

    // 星空
    _drawStars(canvas, w, h, hue);

    // 流星
    _drawMeteors(canvas, w, h, hue);

    // 频谱
    _drawAurora(canvas, w, h, hue);

    // 底部渐隐
    canvas.drawRect(Rect.fromLTWH(0, h * 0.85, w, h * 0.15), Paint()
      ..shader = ui.Gradient.linear(Offset(0, h * 0.85), Offset(0, h), [
        Colors.transparent,
        HSLColor.fromAHSL(1.0, hue, 0.3, 0.06).toColor().withValues(alpha: 0.8),
      ]));
  }

  void _drawStars(Canvas canvas, double w, double h, double hue) {
    final starPaint = Paint();
    final starPositions = [
      Offset(0.1, 0.15), Offset(0.25, 0.08), Offset(0.4, 0.2), Offset(0.55, 0.12),
      Offset(0.7, 0.18), Offset(0.85, 0.1), Offset(0.15, 0.35), Offset(0.35, 0.3),
      Offset(0.5, 0.38), Offset(0.65, 0.28), Offset(0.8, 0.35), Offset(0.9, 0.25),
      Offset(0.05, 0.55), Offset(0.2, 0.5), Offset(0.45, 0.55), Offset(0.6, 0.48),
      Offset(0.75, 0.52), Offset(0.95, 0.45), Offset(0.1, 0.7), Offset(0.3, 0.65),
      Offset(0.5, 0.72), Offset(0.7, 0.68), Offset(0.88, 0.72),
    ];
    for (int i = 0; i < starPositions.length; i++) {
      final pos = starPositions[i];
      final twinkle = sin(time * (1.5 + i * 0.3) + i * 2.1) * 0.4 + 0.6;
      final size = 1.0 + (i % 3) * 0.5;
      starPaint.color = HSLColor.fromAHSL(1.0, (hue + i * 15) % 360, 0.2, 0.8)
          .toColor().withValues(alpha: twinkle * 0.6);
      canvas.drawCircle(Offset(pos.dx * w, pos.dy * h), size, starPaint);
    }
  }

  void _drawMeteors(Canvas canvas, double w, double h, double hue) {
    final meteorPaint = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    for (int i = 0; i < meteors.length; i++) {
      final m = meteors[i];
      final cycleDuration = m.speed;
      final t = (time * cycleDuration + m.delay) % 1.0;
      if (t > 0.8) continue;
      final progress = t / 0.8;
      final mx = m.startX * w + progress * m.dx * w;
      final my = m.startY * h + progress * m.dy * h;
      final tailLen = 40.0 + m.size * 20;
      final alpha = sin(progress * pi) * m.brightness;
      if (alpha < 0.01) continue;
      final meteorHue = (hue + i * 30) % 360;
      final color = HSLColor.fromAHSL(1.0, meteorHue, 0.6, 0.7).toColor();
      final tailX = mx - m.dx * tailLen / w;
      final tailY = my - m.dy * tailLen / h;
      meteorPaint.shader = ui.Gradient.linear(
        Offset(mx, my), Offset(tailX * w, tailY * h),
        [
          color.withValues(alpha: alpha),
          color.withValues(alpha: alpha * 0.3),
          Colors.transparent,
        ],
        [0.0, 0.4, 1.0],
      );
      canvas.drawLine(Offset(mx, my), Offset(tailX * w, tailY * h), meteorPaint);
      // 头部发光
      meteorPaint.shader = null;
      meteorPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      meteorPaint.color = color.withValues(alpha: alpha * 0.8);
      canvas.drawCircle(Offset(mx, my), m.size * 2, meteorPaint);
      meteorPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    }
  }

  void _drawAurora(Canvas canvas, double w, double h, double hue) {
    final auroraPaint = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
    for (int i = 0; i < 4; i++) {
      final path = Path();
      final baseY = h * 0.55 + i * h * 0.08;
      final amplitude = h * 0.08 * (1 + sin(time * 0.3 + i) * 0.4);
      final frequency = 0.003 + i * 0.001;
      final phaseShift = time * 0.4 + i * 1.2;
      path.moveTo(0, baseY);
      for (double x = 0; x <= w; x += 3) {
        final y = baseY + sin(x * frequency + phaseShift) * amplitude
            + cos(x * frequency * 1.5 + phaseShift * 0.7) * amplitude * 0.4;
        path.lineTo(x, y);
      }
      path.lineTo(w, h);
      path.lineTo(0, h);
      path.close();
      final auroraHue = (hue + i * 40 + 120) % 360;
      final alpha = 0.08 + sin(time * 0.5 + i * 0.8) * 0.04;
      auroraPaint.shader = ui.Gradient.linear(
        Offset(0, baseY - amplitude), Offset(0, h),
        [
          HSLColor.fromAHSL(1.0, auroraHue, 0.7, 0.45).toColor().withValues(alpha: alpha),
          HSLColor.fromAHSL(1.0, (auroraHue + 20) % 360, 0.6, 0.35).toColor().withValues(alpha: alpha * 0.5),
          Colors.transparent,
        ],
        [0.0, 0.6, 1.0],
      );
      canvas.drawPath(path, auroraPaint);
    }
    // 顶部光晕
    final glowPaint = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50);
    final glowY = h * 0.6 + sin(time * 0.2) * h * 0.05;
    glowPaint.shader = ui.Gradient.radial(
      Offset(w * 0.5, glowY), w * 0.5, [
        HSLColor.fromAHSL(1.0, (hue + 150) % 360, 0.6, 0.4).toColor().withValues(alpha: 0.08),
        Colors.transparent,
      ], [0.0, 1.0],
    );
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), glowPaint);
  }

  @override
  bool shouldRepaint(covariant _BgPainter old) =>
      old.time != time || old.isPlaying != isPlaying || old.frequencies != frequencies;
}

class _Meteor {
  final double startX, startY, dx, dy, speed, delay, size, brightness;
  _Meteor(this.startX, this.startY, this.dx, this.dy, this.speed, this.delay, this.size, this.brightness);
  factory _Meteor.random(Random r) => _Meteor(
    r.nextDouble() * 0.6,
    r.nextDouble() * 0.3,
    0.3 + r.nextDouble() * 0.5,
    0.6 + r.nextDouble() * 0.3,
    0.15 + r.nextDouble() * 0.25,
    r.nextDouble(),
    1.0 + r.nextDouble() * 2.0,
    0.4 + r.nextDouble() * 0.4,
  );
}

/// 歌词换行时的轻微上下位移过渡。
///
/// 窗口化列表是瞬时替换内容的，这里在换行瞬间给一个短促的位移回弹，
/// 补足「滑动」感知（逐行缩放淡入淡出由 [_AnimatedLyricRow] 负责）。
class _LineShiftTransition extends StatefulWidget {
  final int token;
  final Widget child;
  const _LineShiftTransition({required this.token, required this.child});

  @override
  State<_LineShiftTransition> createState() => _LineShiftTransitionState();
}

class _LineShiftTransitionState extends State<_LineShiftTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(covariant _LineShiftTransition old) {
    super.didUpdateWidget(old);
    if (old.token != widget.token) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 从轻微下方/上方滑入，落定后归位
    final anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        final t = anim.value;
        final offset = (1 - t) * 14.0;
        return Transform.translate(
          offset: Offset(0, offset),
          child: Opacity(opacity: 0.35 + 0.65 * t, child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// 单行歌词的动画容器。
///
/// 逐行做「缩放 + 透明度 + 垂直位移」的补间，行切换时不是瞬变，
/// 而是平滑过渡。当前行放大满亮并带辉光，上下文行缩小淡出。
class _AnimatedLyricRow extends StatelessWidget {
  final int index;
  final LyricLine line;
  final bool isCurrent;
  final int distance;
  final double mainFontSize;
  final ValueChanged<Duration> onSeek;
  final Widget child;

  const _AnimatedLyricRow({
    super.key,
    required this.index,
    required this.line,
    required this.isCurrent,
    required this.distance,
    required this.mainFontSize,
    required this.onSeek,
    required this.child,
  });

  /// 与当前行的距离 → (缩放, 透明度)
  (double, double) _emphasis() {
    if (isCurrent) return (1.0, 1.0);
    if (distance <= 1) return (0.78, 0.5);
    if (distance == 2) return (0.66, 0.28);
    return (0.58, 0.15);
  }

  @override
  Widget build(BuildContext context) {
    final (scale, alpha) = _emphasis();
    final hasTranslation = line.translation != null && line.translation!.isNotEmpty;

    return GestureDetector(
      onTap: () => onSeek(line.time),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          vertical: isCurrent ? 8 : 3,
          horizontal: 24,
        ),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOut,
          opacity: alpha,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 480),
            curve: Curves.easeOutBack,
            scale: scale,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 逐字/扫光文本自带颜色，这里只给非当前行统一上色
                isCurrent
                    ? child
                    : DefaultTextStyle.merge(
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: mainFontSize,
                        ),
                        child: child,
                      ),
                if (hasTranslation)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      line.translation!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isCurrent ? mainFontSize * 0.32 : 11,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                        color: Colors.white.withValues(alpha: isCurrent ? 0.55 : 0.4),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
