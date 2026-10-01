import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../services/lyric/lyric_parser.dart';
import 'jizura_lyrics_view.dart';
import 'lyric_effect_config.dart';

/// 全屏特效歌词页（JIZURA 风格）
///
/// 屏幕上只有当前一句，巨号铺满，色差错位 / 逐字波浪 / 弹跳入场等特效。
/// 右上角菜单可切换版式、入场、保持、出场、文本特效、配色与动效强度。
class PvLyricsScreen extends ConsumerStatefulWidget {
  const PvLyricsScreen({super.key});

  @override
  ConsumerState<PvLyricsScreen> createState() => _PvLyricsScreenState();
}

class _PvLyricsScreenState extends ConsumerState<PvLyricsScreen> {
  List<LyricLine> _lyrics = [];
  LyricEffectConfig _config = const LyricEffectConfig();
  /// 随机模式下当前使用的特效（每首歌一套）
  LyricEffectConfig _active = const LyricEffectConfig();
  String _randomSeedKey = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _applyLyric(ref.read(lyricProvider).valueOrNull?['lyric'] ?? '');
      final cfg = await LyricEffectConfig.load();
      if (mounted) setState(() => _config = cfg);
    });
  }

  /// 随机模式：按歌曲 id 生成稳定的一套特效（同一首歌内不跳变）
  void _syncRandom(String musicId) {
    if (!_config.random) {
      if (_randomSeedKey.isNotEmpty) {
        _randomSeedKey = '';
        setState(() => _active = _config);
      }
      return;
    }
    if (musicId == _randomSeedKey) return;
    _randomSeedKey = musicId;
    final seed = musicId.isEmpty ? 1 : musicId.hashCode;
    setState(() => _active = LyricEffectConfig.randomized(seed));
  }

  void _applyLyric(String lyricText) {
    if (lyricText.isEmpty) return;
    final parsed = LyricParser.parse(lyricText);
    if (parsed.isEmpty) return;
    if (!mounted) return;
    setState(() => _lyrics = parsed);
  }

  void _openEffectSheet() {
    showLyricEffectSheet(context).then((_) {
      if (mounted) _refreshConfig();
    });
  }

  Future<void> _refreshConfig() async {
    final cfg = await LyricEffectConfig.load();
    if (mounted) setState(() => _config = cfg);
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final musicId = ref.watch(currentMusicProvider).valueOrNull?.id ?? '';

    // 随机模式：切歌时换一套特效
    _syncRandom(musicId);

    ref.listen(lyricProvider, (prev, next) {
      _applyLyric(next.valueOrNull?['lyric'] ?? '');
    });

    final pal = _active.palette;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: pal.bg,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _CoverTexture(),
            SafeArea(
              child: Column(
                children: [
                  _TopBar(onMenu: _openEffectSheet),
                  Expanded(
                    child: _lyrics.isEmpty
                        ? const SizedBox.shrink()
                        : JizuraLyricsView(
                            lines: _lyrics,
                            position: position,
                            config: _active,
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

/// 顶部栏（含特效菜单按钮）
class _TopBar extends ConsumerWidget {
  final VoidCallback onMenu;
  const _TopBar({required this.onMenu});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final music = ref.watch(currentMusicProvider).valueOrNull;
    final singer = music?.singer ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
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
          IconButton(
            tooltip: '特效',
            icon: const Icon(Icons.auto_awesome_rounded,
                size: 20, color: Colors.white54),
            onPressed: onMenu,
          ),
        ],
      ),
    );
  }
}

/// 封面底纹：模糊封面 + 极低透明度，只做氛围
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
