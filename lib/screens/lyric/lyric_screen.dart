import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/music_model.dart';
import '../../providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../services/lyric/lyric_parser.dart';

/// 歌词页：实时跟随当前播放歌曲的完整歌词
/// 修复：之前依赖从未被调用的 musicDetailProvider（死功能），
/// 现改用 lyricProvider 实时流，与播放详情页数据源一致
class LyricScreen extends ConsumerStatefulWidget {
  const LyricScreen({super.key});

  @override
  ConsumerState<LyricScreen> createState() => _LyricScreenState();
}

class _LyricScreenState extends ConsumerState<LyricScreen> {
  late ScrollController _scrollController;
  List<LyricLine> _lyrics = [];
  String _lyricKey = '';
  int _currentLineIndex = 0;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    // 用 ref.listen 替代 ref.watch，避免每 200ms 全页 rebuild
    ref.listen<AsyncValue<Duration>>(positionProvider, (prev, next) {
      final p = next.valueOrNull;
      if (p != null && mounted) setState(() => _position = p);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _syncLyrics(Map<String, String?>? lyricMap, String? musicId) {
    final lyricText = lyricMap?['lyric'] ?? '';
    final key = '${musicId ?? ''}_$lyricText';
    if (key == _lyricKey) return;
    _lyricKey = key;
    _lyrics = LyricParser.parse(lyricText);
    _currentLineIndex = 0;
  }

  @override
  Widget build(BuildContext context) {
    final currentMusic = ref.watch(currentMusicProvider);
    final lyricData = ref.watch(lyricProvider);

    // 同步歌词
    _syncLyrics(lyricData.valueOrNull, currentMusic.valueOrNull?.id);

    final music = currentMusic.valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('歌词')),
      body: music == null
          ? const Center(child: Text('未在播放'))
          : _buildLyricView(music, _position),
    );
  }

  Widget _buildLyricView(MusicInfo music, Duration position) {
    if (_lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(24),
                boxShadow: AppNeumorphic.soft,
              ),
              child: Icon(Icons.lyrics_rounded, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            Text('「${music.name}」暂无歌词',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          ],
        ),
      );
    }

    // 找当前行
    int newIndex = 0;
    for (int i = 0; i < _lyrics.length; i++) {
      if (position >= _lyrics[i].time) {
        newIndex = i;
      } else {
        break;
      }
    }

    if (newIndex != _currentLineIndex) {
      _currentLineIndex = newIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        const lineH = 52.0;
        final target = newIndex * lineH;
        _scrollController.animateTo(
          target.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      });
    }

    return ListView.builder(
      controller: _scrollController,
      // 顶部锚点让当前行居中偏上
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).size.height * 0.25,
        bottom: MediaQuery.of(context).size.height * 0.6,
      ),
      itemCount: _lyrics.length,
      itemBuilder: (context, index) {
        final line = _lyrics[index];
        final isCurrentLine = index == _currentLineIndex;

        return GestureDetector(
          onTap: () => ref.read(playerServiceProvider).seek(line.time),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 52,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  line.text,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isCurrentLine ? 18 : 15,
                    fontWeight: isCurrentLine ? FontWeight.bold : FontWeight.normal,
                    color: isCurrentLine
                        ? AppColors.primary
                        : AppColors.textHint,
                  ),
                ),
                if (line.translation != null && line.translation!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      line.translation!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isCurrentLine ? 13 : 11,
                        color: isCurrentLine
                            ? AppColors.primary.withValues(alpha: 0.7)
                            : AppColors.textHint.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
