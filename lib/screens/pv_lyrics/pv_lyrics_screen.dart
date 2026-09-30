import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
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
  List<LyricLine> _parsedLyrics = [];
  LyricLine? _currentLine;
  LyricLine? _nextLine;
  int _currentIndex = -1;
  double _currentProgress = 0;
  StreamSubscription<SpectrumData>? _spectrumSub;
  List<double> _frequencies = [];
  Duration _position = Duration.zero;

  // 音乐能量（用于背景呼吸与光带）
  double _bass = 0;
  double _mid = 0;
  double _treble = 0;
  double _beat = 0;

  // 封面主色（HSL 色相 0~1），用于背景配色
  double? _coverHue;
  double _coverSaturation = 0.5;
  String _coverUrl = '';
  String? _lastMusicId;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(hours: 1),
    )..repeat();
    _spectrumSub = ref.read(audioAnalysisProvider).spectrumStream.listen((data) {
      if (mounted) {
        setState(() {
          _frequencies = data.frequencies;
          _bass = data.bass;
          _mid = data.mid;
          _treble = data.treble;
          _beat = data.beat;
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLyric();
      _syncCoverColor();
    });
  }

  void _initLyric() {
    final lyricMap = ref.read(lyricProvider).valueOrNull;
    final lyricText = lyricMap?['lyric'] ?? '';
    if (lyricText.isNotEmpty) {
      _parsedLyrics = LyricParser.parse(lyricText);
    }
  }

  /// 从封面图取主色，作为背景配色，让背景跟歌曲对应而不是随机变色。
  /// 用 dart:ui 的 instantiateImageCodec 解码（无需额外依赖），
  /// 降采样后统计高饱和像素的色相分布，取众数。
  Future<void> _syncCoverColor() async {
    final music = ref.read(currentMusicProvider).valueOrNull;
    var url = music?.imgUrl;
    if (music?.source == 'local' && url != null) url = Uri.file(url).toString();
    if (url == null || url.isEmpty || url == _coverUrl) return;
    _coverUrl = url;

    try {
      final hue = await _extractDominantHue(url);
      if (!mounted || hue == null) return;
      setState(() {
        _coverHue = hue.hue;
        _coverSaturation = hue.saturation.clamp(0.25, 0.75);
      });
    } catch (_) {
      // 封面加载失败则保持默认配色
    }
  }

  /// 采样封面像素，返回主色相与平均饱和度
  Future<({double hue, double saturation})?> _extractDominantHue(String url) async {
    final data = await _loadBytes(url);
    if (data == null) return null;

    final codec = await ui.instantiateImageCodec(data, targetWidth: 32);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return null;
      final bytes = byteData.buffer.asUint8List();

      // 色相直方图（36 个桶）
      const buckets = 36;
      final hist = List<int>.filled(buckets, 0);
      final satSum = List<double>.filled(buckets, 0);
      final count = List<int>.filled(buckets, 0);

      for (int i = 0; i + 3 < bytes.length; i += 4) {
        final r = bytes[i] / 255.0;
        final g = bytes[i + 1] / 255.0;
        final b = bytes[i + 2] / 255.0;
        // 跳过过暗/过亮的像素（黑底、白底封面无主色意义）
        final maxC = [r, g, b].reduce((a, b) => a > b ? a : b);
        final minC = [r, g, b].reduce((a, b) => a < b ? a : b);
        if (maxC < 0.12 || maxC > 0.97) continue;
        final sat = maxC == 0 ? 0.0 : (maxC - minC) / maxC;
        if (sat < 0.12) continue;

        // RGB → HSV 色相
        final d = maxC - minC;
        if (d == 0) continue;
        var h = 0.0;
        if (maxC == r) {
          h = 60 * (((g - b) / d) % 6);
        } else if (maxC == g) {
          h = 60 * (((b - r) / d) + 2);
        } else {
          h = 60 * (((r - g) / d) + 4);
        }
        if (h < 0) h += 360;

        final bucket = (h / 10).floor().clamp(0, buckets - 1);
        // 按饱和度加权，鲜艳的颜色更可能是主色
        hist[bucket] += 1;
        satSum[bucket] += sat;
        count[bucket] += 1;
      }

      var best = -1;
      var bestScore = 0;
      for (int i = 0; i < buckets; i++) {
        if (hist[i] == 0) continue;
        // 相邻桶合并投票，避免色相分界处被切开
        final prev = hist[(i - 1 + buckets) % buckets];
        final next = hist[(i + 1) % buckets];
        final score = hist[i] * 2 + prev + next;
        if (score > bestScore) {
          bestScore = score;
          best = i;
        }
      }
      if (best < 0) return null;

      return (
        hue: (best * 10 + 5) / 360.0,
        saturation: satSum[best] / count[best],
      );
    } finally {
      image.dispose();
      codec.dispose();
    }
  }

  Future<Uint8List?> _loadBytes(String url) async {
    try {
      if (url.startsWith('http')) {
        final resp = await http.get(Uri.parse(url));
        if (resp.statusCode == 200) return resp.bodyBytes;
        return null;
      }
      if (url.startsWith('file://')) {
        final f = File.fromUri(Uri.parse(url));
        if (await f.exists()) return f.readAsBytes();
      }
      return null;
    } catch (_) {
      return null;
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

    // 切歌时重新提取封面主色，背景跟着换歌换色
    final musicId = ref.watch(currentMusicProvider).valueOrNull?.id;
    if (musicId != _lastMusicId) {
      _lastMusicId = musicId;
      _coverUrl = ''; // 强制重新取色
      unawaited(_syncCoverColor());
    }

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
                isPlaying: isPlaying,
                bass: _bass,
                mid: _mid,
                treble: _treble,
                beat: _beat,
                frequencies: _frequencies,
                coverHue: _coverHue,
                coverSaturation: _coverSaturation,
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
  final bool isPlaying;
  final double bass;
  final double mid;
  final double treble;
  final double beat;
  final List<double> frequencies;
  /// 封面主色（HSL 色相 0~1），无封面时用默认值
  final double? coverHue;
  final double coverSaturation;

  _BgPainter({
    required this.time,
    required this.isPlaying,
    this.bass = 0,
    this.mid = 0,
    this.treble = 0,
    this.beat = 0,
    this.frequencies = const [],
    this.coverHue,
    this.coverSaturation = 0.45,
  });

  /// 主色相：优先取封面主色，缓慢跟随音乐轻微呼吸（不随时间乱转色相）
  double get _hue {
    final base = coverHue ?? 0.62;
    return (base + sin(time * 0.08) * 0.02) % 1.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final hue = _hue;
    final energy = (bass * 0.6 + mid * 0.3 + treble * 0.1).clamp(0.0, 1.0);

    // 1) 底层：从封面色派生的深色渐变，越靠近歌词区越暗，保证文字可读
    final light = 0.045 + energy * 0.02;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, h),
          [
            HSLColor.fromAHSL(1.0, (hue + 0.03) % 1.0, coverSaturation * 0.5, light + 0.03).toColor(),
            HSLColor.fromAHSL(1.0, hue, coverSaturation * 0.6, light).toColor(),
            HSLColor.fromAHSL(1.0, (hue - 0.03 + 1) % 1.0, coverSaturation * 0.7, light * 0.8).toColor(),
          ],
          const [0.0, 0.45, 1.0],
        ),
    );

    // 2) 封面色的柔光晕（居中偏上），营造氛围但不抢文字
    _drawCoverGlow(canvas, w, h, hue, energy);

    // 3) 音乐驱动的极光带（用真实频谱数据形状，不是纯装饰正弦）
    if (isPlaying) {
      _drawSpectrumAurora(canvas, w, h, hue, energy);
    }

    // 4) 节拍时的柔和脉冲光环
    if (beat > 0.01) {
      _drawBeatPulse(canvas, w, h, hue, beat);
    }

    // 5) 底部压暗，保证播放控件区域与歌词底部可读
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.72, w, h * 0.28),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, h * 0.72),
          Offset(0, h),
          [
            Colors.transparent,
            HSLColor.fromAHSL(1.0, hue, coverSaturation * 0.5, 0.02).toColor(),
          ],
        ),
    );
  }

  /// 封面主色柔光：两团大范围高斯光，颜色取自封面
  void _drawCoverGlow(Canvas canvas, double w, double h, double hue, double energy) {
    final glow = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60)
      ..shader = ui.Gradient.radial(
        Offset(w * 0.5, h * 0.42),
        w * 0.75,
        [
          HSLColor.fromAHSL(1.0, hue, 0.65, 0.5)
              .toColor()
              .withValues(alpha: 0.10 + energy * 0.06),
          Colors.transparent,
        ],
        const [0.0, 1.0],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), glow);

    // 侧向副色光斑，增加层次
    final side = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 70)
      ..shader = ui.Gradient.radial(
        Offset(w * 0.15, h * 0.68),
        w * 0.6,
        [
          HSLColor.fromAHSL(1.0, (hue + 0.12) % 1.0, 0.6, 0.45)
              .toColor()
              .withValues(alpha: 0.07),
          Colors.transparent,
        ],
        const [0.0, 1.0],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), side);
  }

  /// 频谱极光：用真实 frequencies 数据的包络画柔和光带。
  void _drawSpectrumAurora(Canvas canvas, double w, double h, double hue, double energy) {
    if (frequencies.length < 8) return;
    final bands = 28;
    final path = Path();
    final baseY = h * 0.80;

    // 低频决定高度，高频叠加细碎起伏
    double yAt(double x) {
      final t = (x / w).clamp(0.0, 1.0);
      final idx = (t * (bands - 1)).round();
      final amp = frequencies.length > idx ? frequencies[idx] : 0.0;
      return baseY - (amp.clamp(0.0, 1.0) * h * 0.22) - bass * h * 0.05;
    }

    path.moveTo(0, yAt(0));
    for (double x = 0; x <= w; x += 4) {
      path.lineTo(x, yAt(x) + sin(x * 0.01 + time * 0.6) * 2.5);
    }
    path.lineTo(w, h);
    path.lineTo(0, h);
    path.close();

    final paint = Paint()
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 18 + energy * 22)
      ..shader = ui.Gradient.linear(
        Offset(0, baseY - h * 0.2),
        Offset(0, h),
        [
          HSLColor.fromAHSL(1.0, hue, 0.7, 0.5)
              .toColor()
              .withValues(alpha: 0.10 + energy * 0.10),
          Colors.transparent,
        ],
        const [0.0, 1.0],
      );
    canvas.drawPath(path, paint);
  }

  /// 节拍脉冲：中心一圈扩散光环
  void _drawBeatPulse(Canvas canvas, double w, double h, double hue, double beat) {
    final t = 1.0 - beat.clamp(0.0, 1.0); // beat 刚触发时为 0 → 扩散最大
    final radius = w * (0.18 + t * 0.35);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = HSLColor.fromAHSL(1.0, hue, 0.6, 0.6)
          .toColor()
          .withValues(alpha: beat * 0.12 * (1 - t));
    canvas.drawCircle(Offset(w * 0.5, h * 0.5), radius, paint);
  }

  @override
  bool shouldRepaint(covariant _BgPainter old) =>
      old.time != time ||
      old.isPlaying != isPlaying ||
      old.coverHue != coverHue ||
      old.bass != bass ||
      old.mid != mid ||
      old.beat != beat ||
      old.frequencies != frequencies;
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
