import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/lyric/lyric_parser.dart';
import 'apple_lyrics_view.dart';

/// Apple Music 风格全屏歌词页
///
/// 背景 = 封面大图重度模糊 + 压暗
/// 歌词 = [AppleLyricsView]（单 CustomPainter + 弹簧 + 连续 alpha 播放头）
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

    // 歌词到达 / 切歌时更新
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
            const _BlurredCoverBackground(),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.5),
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.7),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
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
      padding: const EdgeInsets.fromLTRB(4, 2, 20, 8),
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

/// 空状态
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
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                url,
                width: 180,
                height: 180,
                fit: BoxFit.cover,
                cacheWidth: 360,
                errorBuilder: (_, __, ___) => const _CoverPlaceholder(),
              ),
            )
          else
            const _CoverPlaceholder(),
          const SizedBox(height: 26),
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
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.music_note_rounded,
        color: Colors.white24,
        size: 66,
      ),
    );
  }
}

/// 封面模糊背景
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
      imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
      child: Transform.scale(
        scale: 1.35,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          cacheWidth: 240,
          errorBuilder: (_, __, ___) =>
              const ColoredBox(color: Color(0xFF0B0B10)),
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const ColoredBox(color: Color(0xFF0B0B10)),
        ),
      ),
    );
  }
}
