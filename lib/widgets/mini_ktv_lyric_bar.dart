import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../core/theme/app_theme.dart';
import '../services/api/lyric_api_service.dart';
import '../services/lyric/lyric_parser.dart';
import '../screens/pv_lyrics/pv_lyrics_screen.dart';
import 'large_ktv_overlay.dart';

/// Mini播放器上方的 5 行 KTV 歌词（当前行扫字，前后各 2 行陪衬）
class MiniKtvLyricBar extends ConsumerStatefulWidget {
  const MiniKtvLyricBar({super.key});

  @override
  ConsumerState<MiniKtvLyricBar> createState() => _MiniKtvLyricBarState();
}

class _MiniKtvLyricBarState extends ConsumerState<MiniKtvLyricBar> {
  static const int _visibleLines = 5;
  static const double _lineHeight = 36;

  List<LyricLine> _lyrics = [];
  String _lyricKey = '';
  int _lastIndex = -1;

  /// 当前歌词实际来自哪个源（由 PlayerService 在结果里标注）
  String _lyricSource = '';
  bool _switching = false;

  Duration _basePos = Duration.zero;
  DateTime _basePosTime = DateTime.now();
  bool _playing = false;
  Timer? _ticker;
  final _tickerListenable = _TickerNotifier();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _readInitial();
      _syncTicker();
    });
  }

  void _readInitial() {
    if (!mounted) return;
    _tryParseLyric(ref.read(lyricProvider).valueOrNull);
    _basePos = ref.read(positionProvider).valueOrNull ?? Duration.zero;
    _basePosTime = DateTime.now();
    _playing = ref.read(isPlayingProvider).valueOrNull ?? false;
  }

  void _syncTicker() {
    if (_playing && _ticker == null) {
      _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) {
        if (!mounted) return;
        _tickerListenable.notify();
      });
    } else if (!_playing && _ticker != null) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _tryParseLyric(Map<String, String?>? lyricMap) {
    final lyricText = lyricMap?['lyric'] ?? '';
    final src = lyricMap?[LyricApiService.kSourceKey] ?? '';
    final key = '${ref.read(currentMusicProvider).valueOrNull?.id ?? ''}_$lyricText';
    if (key == _lyricKey) return;
    _lyricKey = key;
    _lyricSource = src;
    _lyrics = LyricParser.parse(lyricText);
    _lastIndex = -1;
    if (mounted) setState(() {});
    if (_lyrics.isNotEmpty && _playing && _ticker == null) {
      _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) {
        if (!mounted) return;
        _tickerListenable.notify();
      });
    }
  }

  String get _sourceLabel {
    for (final o in lyricSourceOptions) {
      if (o.id == _lyricSource) return o.label;
    }
    return '歌词';
  }

  /// 单曲换源：只试这一个源，不走自动兜底，也不后台升级逐字。
  Future<void> _switchSource(String source) async {
    if (_switching) return;
    setState(() => _switching = true);
    final ok = await ref.read(playerServiceProvider).switchLyricSource(source);
    if (!mounted) return;
    setState(() => _switching = false);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(
      content: Text(ok != null
          ? '已切换歌词源'
          : '该源取不到歌词'),
      duration: const Duration(milliseconds: 1400),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showSourceSheet() {
    final music = ref.read(currentMusicProvider).valueOrNull;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Text('歌词源',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text('当前：$_sourceLabel',
                      style: TextStyle(
                          color: AppColors.textHint, fontSize: 12)),
                ],
              ),
            ),
            for (final o in lyricSourceOptions)
              Builder(builder: (_) {
                final unusable = o.needsOwnSource &&
                    music != null &&
                    music.source != o.id;
                final isCurrent = o.id == _lyricSource;
                return ListTile(
                  leading: Icon(
                    isCurrent
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color:
                        isCurrent ? AppColors.primary : AppColors.textHint,
                  ),
                  title: Text(o.label,
                      style: TextStyle(color: AppColors.textPrimary)),
                  subtitle: Text(
                    unusable ? '${o.desc}（当前歌曲非本源）' : o.desc,
                    style:
                        TextStyle(color: AppColors.textHint, fontSize: 11),
                  ),
                  enabled: !unusable && !isCurrent,
                  onTap: () {
                    Navigator.pop(ctx);
                    _switchSource(o.id);
                  },
                );
              }),
          ],
        ),
      ),
    );
  }

  int _findIndex(Duration pos) {
    final n = _lyrics.length;
    if (_lastIndex >= 0 && _lastIndex < n && pos >= _lyrics[_lastIndex].time) {
      var idx = _lastIndex;
      var start = _lastIndex;
      while (start < n && pos >= _lyrics[start].time) {
        idx = start;
        start++;
      }
      return (_lastIndex = idx);
    }
    _lastIndex = -1;
    var idx = -1;
    var start = 0;
    while (start < n && pos >= _lyrics[start].time) {
      idx = start;
      start++;
    }
    return (_lastIndex = idx);
  }

  void _showLargeLyric(BuildContext context) {
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, __, ___) => const PvLyricsScreen(),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 300),
    ));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _tickerListenable.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(lyricProvider, (_, next) => _tryParseLyric(next.valueOrNull));
    ref.listen(positionProvider, (_, next) => next.whenData((p) {
      _basePos = p;
      _basePosTime = DateTime.now();
    }));
    ref.listen(isPlayingProvider, (_, next) {
      final p = next.valueOrNull ?? false;
      if (p != _playing) {
        _playing = p;
        _syncTicker();
      }
    });
    ref.listen(currentMusicProvider, (prev, next) {
      if (prev?.valueOrNull?.id != next.valueOrNull?.id) {
        _lyricKey = '';
        _lyrics = [];
        _lastIndex = -1;
      }
    });

    if (_lyricKey.isEmpty) {
      _tryParseLyric(ref.read(lyricProvider).valueOrNull);
    }
    // 自适应高度：无歌词时塌缩为 0，上方 Expanded 频谱区自动吸收空间，
    // 有歌词时展开 5 行。避免固定槽位占 188px 空白导致页面很空。
    if (_lyrics.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => _showLargeLyric(context),
      child: Container(
        height: _visibleLines * _lineHeight,
        margin: const EdgeInsets.fromLTRB(24, 4, 24, 8),
        child: Stack(
          children: [
            // 歌词本体铺满，外层 GestureDetector 负责进全屏
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _tickerListenable,
                // 关键：estPos/idx/progress 必须放在 builder 内，
                // 否则 ticker 触发的重建会复用旧的 idx 和 progress，歌词就不会动。
                // 之前 build() 只在 setState 时调用，AnimatedBuilder.builder
                // 内部用的闭包变量是 build() 时的快照。
                builder: (context, _) {
                  final estPos = _playing
                      ? _basePos + DateTime.now().difference(_basePosTime)
                      : _basePos;
                  final idx = _findIndex(estPos);
                  if (idx < 0) return const SizedBox.shrink();
                  final progress = _progress(idx, estPos);

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_visibleLines, (slot) {
                      final lineIdx = idx - (_visibleLines ~/ 2) + slot;
                      if (lineIdx < 0 || lineIdx >= _lyrics.length) {
                        return const SizedBox(height: _lineHeight);
                      }
                      final text = _lyrics[lineIdx].text;
                      if (text.isEmpty) return const SizedBox(height: _lineHeight);
                      if (lineIdx != idx) {
                        return _SurroundingLine(
                          text: text,
                          distance: (lineIdx - idx).abs(),
                        );
                      }
                      return _CurrentLine(text: text, progress: progress);
                    }),
                  );
                },
              ),
            ),
            // 源标识：自己吃掉手势，避免冒泡到外层触发进全屏
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: _switching ? null : _showSourceSheet,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lyrics_rounded,
                          size: 11,
                          color: AppColors.primary.withValues(alpha: 0.9)),
                      const SizedBox(width: 3),
                      Text(
                        _switching ? '切换中' : _sourceLabel,
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.primary
                              .withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _progress(int idx, Duration estPos) {
    final line = _lyrics[idx];
    final lineEnd = idx + 1 < _lyrics.length
        ? _lyrics[idx + 1].time
        : line.time + const Duration(seconds: 5);
    final lineDur = lineEnd - line.time;
    if (lineDur <= Duration.zero) return 0;
    return ((estPos - line.time).inMilliseconds / lineDur.inMilliseconds)
        .clamp(0.0, 1.0);
  }
}

/// 当前行（逐字 Color.lerp 扫字）— RepaintBoundary 隔开
class _CurrentLine extends StatelessWidget {
  final String text;
  final double progress;
  const _CurrentLine({required this.text, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _MiniKtvLyricBarState._lineHeight,
      alignment: Alignment.center,
      child: RepaintBoundary(
        child: LerpScanText(
          text: text,
          progress: progress,
          scannedColor: AppColors.primaryDark,
          unscannedColor: AppColors.textHint,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 上下陪衬行（淡灰小字）
class _SurroundingLine extends StatelessWidget {
  final String text;
  final int distance;
  const _SurroundingLine({required this.text, required this.distance});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _MiniKtvLyricBarState._lineHeight,
      alignment: Alignment.center,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          color: AppColors.textSecondary.withValues(alpha: distance == 1 ? 0.55 : 0.3),
        ),
      ),
    );
  }
}

class _TickerNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}