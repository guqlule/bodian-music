import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/lyric/lyric_parser.dart';
import 'apple_lyrics_view.dart';

/// Apple Music 风格全屏歌词页
///
/// 背景 = 封面大图重度模糊（带兜底渐变，绝不纯黑）
/// 歌词 = [AppleLyricsView]
class PvLyricsScreen extends ConsumerStatefulWidget {
  const PvLyricsScreen({super.key});

  @override
  ConsumerState<PvLyricsScreen> createState() => _PvLyricsScreenState();
}

class _PvLyricsScreenState extends ConsumerState<PvLyricsScreen> {
  List<LyricLine> _lyrics = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyLyric(ref.read(lyricProvider).valueOrNull?['lyric'] ?? '');
    });
  }

  void _applyLyric(String lyricText) {
    if (lyricText.isEmpty) return;
    final parsed = LyricParser.parse(lyricText);
    if (parsed.isEmpty) return;
    if (!mounted) return;
    setState(() => _lyrics = parsed);
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(positionProvider).valueOrNull ?? Duration.zero;

    ref.listen(lyricProvider, (prev, next) {
      _applyLyric(next.valueOrNull?['lyric'] ?? '');
    });

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF12121A),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _CoverBackdrop(),
            SafeArea(
              child: Column(
                children: [
                  const _TopBar(),
                  Expanded(
                    child: _lyrics.isEmpty
                        ? const _EmptyState()
                        : AppleLyricsView(
                            lines: _lyrics,
                            position: position,
                            onSeek: (t) =>
                                ref.read(playerServiceProvider).seek(t),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部栏
class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final music = ref.watch(currentMusicProvider).valueOrNull;
    final singer = music?.singer ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 20, 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                size: 30, color: Colors.white70),
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
                    shadows: [
                      Shadow(color: Colors.black54, blurRadius: 6),
                    ],
                  ),
                ),
                if (singer.isNotEmpty)
                  Text(
                    singer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
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

/// 空状态
class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final music = ref.watch(currentMusicProvider).valueOrNull;
    final url = _coverUrl(music);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (url != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                url,
                width: 170,
                height: 170,
                fit: BoxFit.cover,
                cacheWidth: 340,
                errorBuilder: (_, __, ___) => const _CoverPlaceholder(),
              ),
            )
          else
            const _CoverPlaceholder(),
          const SizedBox(height: 24),
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
      width: 170,
      height: 170,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.music_note_rounded,
        color: Colors.white24,
        size: 60,
      ),
    );
  }
}

/// 封面 URL（本地歌曲转 file://）
String? _coverUrl(dynamic music) {
  if (music == null) return null;
  final artUrl = music.imgUrl as String?;
  if (artUrl == null || artUrl.isEmpty) return null;
  if (music.source == 'local') {
    try {
      return Uri.file(artUrl).toString();
    } catch (_) {
      return null;
    }
  }
  return artUrl;
}

/// 封面背景层
///
/// 三层结构保证「绝不纯黑」：
///   1. 底层：深色渐变（无封面时也好看）
///   2. 中层：封面重度模糊图（加载失败自动跳过）
///   3. 上层：顶部/底部压暗，保证文字对比度
class _CoverBackdrop extends ConsumerStatefulWidget {
  const _CoverBackdrop();

  @override
  ConsumerState<_CoverBackdrop> createState() => _CoverBackdropState();
}

class _CoverBackdropState extends ConsumerState<_CoverBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 26),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final music = ref.watch(currentMusicProvider).valueOrNull;
    final url = _coverUrl(music);
    final isPlaying = ref.watch(isPlayingProvider).valueOrNull ?? false;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1) 底层渐变（永远存在）
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1E2233),
                Color(0xFF14161F),
                Color(0xFF1A1526),
              ],
            ),
          ),
        ),
        // 2) 封面模糊图
        if (url != null)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _drift,
              builder: (context, _) {
                // 暂停时冻结在中间位置
                final k = isPlaying ? _drift.value : 0.5;
                return ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 46, sigmaY: 46),
                  child: Transform.scale(
                    // 放大 + 位移，避免模糊后边缘露白、且有缓慢漂移感
                    scale: 1.30 + k * 0.06,
                    child: Transform.translate(
                      offset: Offset((k - 0.5) * 20, (k - 0.5) * -14),
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        cacheWidth: 200,
                        // 加载失败/无图时透明，露出底层渐变
                        frameBuilder: (context, child, frame, wasSync) {
                          if (wasSync || frame != null) return child;
                          return const SizedBox.shrink();
                        },
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        // 3) 对比度压暗（只压上下，中间留亮）
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x66000000),
                Color(0x1A000000),
                Color(0x59000000),
              ],
              stops: [0.0, 0.42, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}
