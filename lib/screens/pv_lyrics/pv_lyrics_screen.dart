import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/lyric/lyric_parser.dart';
import 'jizura_lyrics_view.dart';

/// 全屏特效歌词页（JIZURA 风格）
///
/// 参考 852wa/JIZURA 的视觉语言：
/// 屏幕上只有当前一句，巨号铺满，色差错位 + 逐字波浪 + 弹跳入场。
/// 没有上下句滚动列表。
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
        backgroundColor: const Color(0xFF060607),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 封面底纹：重度模糊 + 极低透明度，只做氛围不抢歌词
            const _CoverTexture(),
            SafeArea(
              child: Column(
                children: [
                  const _TopBar(),
                  Expanded(
                    child: _lyrics.isEmpty
                        ? const SizedBox.shrink()
                        : JizuraLyricsView(
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
      padding: const EdgeInsets.fromLTRB(4, 4, 20, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                size: 28, color: Colors.white54),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 10),
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
                    color: Color(0xFFF5EEEA),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                if (singer.isNotEmpty)
                  Text(
                    singer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFBDB6B2),
                      fontSize: 11,
                      letterSpacing: 0.3,
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

/// 封面底纹：模糊封面 + 极低透明度
class _CoverTexture extends ConsumerWidget {
  const _CoverTexture();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final music = ref.watch(currentMusicProvider).valueOrNull;
    final url = _coverUrl(music);
    if (url == null) return const SizedBox.shrink();

    return Opacity(
      opacity: 0.16,
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60),
        child: Transform.scale(
          scale: 1.3,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            cacheWidth: 180,
            frameBuilder: (context, child, frame, wasSync) {
              if (wasSync || frame != null) return child;
              return const SizedBox.shrink();
            },
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

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
