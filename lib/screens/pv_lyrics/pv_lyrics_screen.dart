import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/lyric/lyric_parser.dart';

/// Apple Music 风格全屏歌词页
///
/// 视觉要点：
/// 1. 背景 = 封面大图重度模糊 + 压暗（Apple Music 最标志性的观感）
/// 2. 整份歌词连续滚动，当前行落在视口 38% 高度处
/// 3. 当前行大而白，上下行快速缩小变淡并加高斯模糊，形成纵深
/// 4. 换行时平滑滑动（520ms easeOutCubic），不是瞬跳
/// 5. 逐字歌词（KRC/ELRC）按词高亮并轻微放大
class PvLyricsScreen extends ConsumerStatefulWidget {
  const PvLyricsScreen({super.key});

  @override
  ConsumerState<PvLyricsScreen> createState() => _PvLyricsScreenState();
}

class _PvLyricsScreenState extends ConsumerState<PvLyricsScreen>
    with TickerProviderStateMixin {
  /// 歌词滚动动画：把离散的当前行索引插值成连续滚动位置
  late final AnimationController _scrollAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  List<LyricLine> _parsedLyrics = [];
  int _currentIndex = -1;
  Duration _position = Duration.zero;

  // 滚动偏移插值状态
  double _scrollFrom = 0;
  double _scrollTo = 0;
  double _currentScroll = 0;
  bool _pendingScroll = true;
  double? _lastViewportHeight;

  static const double _rowHeight = 54.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLyric();
    });
  }

  void _initLyric() {
    _applyLyric(ref.read(lyricProvider).valueOrNull?['lyric'] ?? '');
  }

  void _applyLyric(String lyricText) {
    if (lyricText.isEmpty) return;
    setState(() {
      _parsedLyrics = LyricParser.parse(lyricText);
      _currentIndex = -1;
      _pendingScroll = true;
      _scrollFrom = 0;
      _scrollTo = 0;
      _currentScroll = 0;
    });
  }

  @override
  void dispose() {
    _scrollAnim.dispose();
    super.dispose();
  }

  /// 依据播放位置找当前行
  void _syncPosition(Duration position) {
    _position = position;
    if (_parsedLyrics.isEmpty) return;
    var idx = -1;
    for (int i = _parsedLyrics.length - 1; i >= 0; i--) {
      if (position >= _parsedLyrics[i].time) {
        idx = i;
        break;
      }
    }
    if (idx >= 0 && idx != _currentIndex) {
      setState(() {
        _currentIndex = idx;
        _pendingScroll = true;
      });
    } else {
      _position = position;
    }
  }

  /// 目标滚动偏移：让当前行落在视口 38% 高度处
  double _targetScroll(double viewportHeight) {
    if (_currentIndex < 0) return 0;
    final total = _parsedLyrics.length * _rowHeight;
    final maxScroll = (total + viewportHeight * 0.5).clamp(0.0, double.infinity);
    final target =
        _currentIndex * _rowHeight - viewportHeight * 0.38 + _rowHeight * 0.5;
    return target.clamp(0.0, maxScroll);
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    _syncPosition(position);

    // 歌词到达/切歌时更新
    ref.listen(lyricProvider, (prev, next) {
      _applyLyric(next.valueOrNull?['lyric'] ?? '');
    });

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 背景：封面大图重度模糊
            const _BlurredCoverBackground(),
            // 压暗层，保证歌词对比度
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.42),
                    Colors.black.withValues(alpha: 0.52),
                    Colors.black.withValues(alpha: 0.72),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  const _TopBar(),
                  Expanded(child: _buildLyricArea()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLyricArea() {
    if (_parsedLyrics.isEmpty) {
      return const _EmptyState();
    }
    return _buildAppleLyrics();
  }

  /// Apple Music 风格歌词：整份连续滚动 + 平滑跟随
  Widget _buildAppleLyrics() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = constraints.maxHeight;
        final fontSize = _adaptiveFontSize(constraints.maxWidth);

        if (_pendingScroll || _lastViewportHeight != viewportHeight) {
          _lastViewportHeight = viewportHeight;
          _pendingScroll = false;
          final target = _targetScroll(viewportHeight);
          if ((target - _scrollTo).abs() >= 0.5) {
            _scrollFrom = _currentScroll;
            _scrollTo = target;
            _scrollAnim.forward(from: 0);
          }
        }

        return ClipRect(
          child: AnimatedBuilder(
            animation: _scrollAnim,
            builder: (context, _) {
              final t = Curves.easeOutCubic.transform(_scrollAnim.value);
              final offset = _scrollFrom + (_scrollTo - _scrollFrom) * t;
              return Transform.translate(
                offset: Offset(0, offset),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < _parsedLyrics.length; i++)
                      _AppleLyricRow(
                        key: ValueKey(i),
                        line: _parsedLyrics[i],
                        isCurrent: i == _currentIndex,
                        fontSize: fontSize,
                        position: _position,
                        onSeek: (t) => ref.read(playerServiceProvider).seek(t),
                      ),
                    // 顶部/底部留白，保证首末行也能滚到视觉中线
                    SizedBox(height: viewportHeight * 0.5),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// 逐字歌词字号略小以容纳多行
  double _adaptiveFontSize(double width) {
    if (width < 360) return 21;
    if (width < 400) return 23;
    return 25;
  }
}

/// 顶部栏：返回 + 歌名歌手
class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final music = ref.watch(currentMusicProvider).valueOrNull;
    final singer = music?.singer ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 20, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                size: 32, color: Colors.white70),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 6),
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
                if (singer.isNotEmpty)
                  Text(
                    singer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 空状态：封面 + 暂无歌词
class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final music = ref.watch(currentMusicProvider).valueOrNull;
    final artUrl = music?.imgUrl;
    final url = (music?.source == 'local' && artUrl != null)
        ? Uri.file(artUrl).toString()
        : artUrl;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (url != null && url.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                url,
                width: 190,
                height: 190,
                fit: BoxFit.cover,
                cacheWidth: 380,
                errorBuilder: (_, __, ___) => const _CoverPlaceholder(),
              ),
            )
          else
            const _CoverPlaceholder(),
          const SizedBox(height: 28),
          const Text(
            '暂无歌词',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      height: 190,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.music_note_rounded,
        color: Colors.white24,
        size: 70,
      ),
    );
  }
}

/// 封面模糊背景：铺满 + 放大裁切 + 重度高斯模糊
class _BlurredCoverBackground extends ConsumerWidget {
  const _BlurredCoverBackground();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final music = ref.watch(currentMusicProvider).valueOrNull;
    final artUrl = music?.imgUrl;
    final url = (music?.source == 'local' && artUrl != null)
        ? Uri.file(artUrl).toString()
        : artUrl;

    if (url == null || url.isEmpty) {
      return const ColoredBox(color: Color(0xFF0B0B10));
    }

    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: 42, sigmaY: 42),
      child: Transform.scale(
        // 放大避免模糊后边缘露白
        scale: 1.35,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          cacheWidth: 240,
          errorBuilder: (_, __, ___) =>
              const ColoredBox(color: Color(0xFF0B0B10)),
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : const ColoredBox(color: Color(0xFF0B0B10)),
        ),
      ),
    );
  }
}

/// Apple Music 风格单行歌词
///
/// - 当前行：全白、加粗、带主题色辉光
/// - 上下文行：按距离缩小变淡，并叠加高斯模糊形成纵深
/// - 逐字歌词：按词进度高亮 + 辉光
class _AppleLyricRow extends StatelessWidget {
  final LyricLine line;
  final bool isCurrent;
  final double fontSize;
  final Duration position;
  final ValueChanged<Duration> onSeek;

  const _AppleLyricRow({
    super.key,
    required this.line,
    required this.isCurrent,
    required this.fontSize,
    required this.position,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onSeek(line.time),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: _PvLyricsScreenState._rowHeight,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: isCurrent
                ? _buildCurrent()
                // 上下文行加轻微高斯模糊，形成 Apple Music 的纵深
                : ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 1.1, sigmaY: 1.1),
                    child: _buildContext(),
                  ),
          ),
        ),
      ),
    );
  }

  /// 当前行：全白 + 主题色辉光
  Widget _buildCurrent() {
    final hasTranslation =
        line.translation != null && line.translation!.isNotEmpty;

    final main = line.hasWords
        ? _buildWordByWord(line, fontSize)
        : Text(
            line.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              height: 1.25,
              shadows: [
                Shadow(
                  color: AppColors.primaryDark.withValues(alpha: 0.55),
                  blurRadius: 18,
                ),
              ],
            ),
          );

    if (!hasTranslation) return main;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(child: main),
        Text(
          line.translation!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: fontSize * 0.56,
            fontWeight: FontWeight.w500,
            height: 1.2,
          ),
        ),
      ],
    );
  }

  /// 上下文行：缩小 + 变淡 + 模糊
  Widget _buildContext() {
    final hasTranslation =
        line.translation != null && line.translation!.isNotEmpty;

    final main = Text(
      line.text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.45),
        fontSize: fontSize * 0.82,
        fontWeight: FontWeight.w500,
        height: 1.2,
      ),
    );

    if (!hasTranslation) return main;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(child: main),
        Text(
          line.translation!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.28),
            fontSize: fontSize * 0.46,
            fontWeight: FontWeight.w400,
            height: 1.2,
          ),
        ),
      ],
    );
  }

  /// 逐字歌词：按词进度高亮
  Widget _buildWordByWord(LyricLine line, double size) {
    final words = line.words!;
    final spans = <TextSpan>[];

    for (final word in words) {
      final wordEnd = word.duration != null
          ? word.time + word.duration!
          : word.time + const Duration(seconds: 1);

      double p;
      if (position < word.time) {
        p = 0;
      } else if (position >= wordEnd) {
        p = 1;
      } else {
        final total = wordEnd - word.time;
        p = total.inMilliseconds > 0
            ? ((position - word.time).inMilliseconds / total.inMilliseconds)
                .clamp(0.0, 1.0)
            : 1.0;
      }

      // 未唱：半透明白；已唱：纯白 + 辉光
      final color = Color.lerp(
        Colors.white.withValues(alpha: 0.45),
        Colors.white,
        p,
      )!;

      spans.add(TextSpan(
        text: word.text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w700,
          height: 1.25,
          shadows: p > 0.05
              ? [
                  Shadow(
                    color: AppColors.primaryDark.withValues(alpha: 0.6 * p),
                    blurRadius: 16 * p,
                  ),
                ]
              : null,
        ),
      ));
    }

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      text: TextSpan(
        children: spans,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      ),
    );
  }
}
