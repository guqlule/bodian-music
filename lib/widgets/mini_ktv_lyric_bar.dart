import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../core/theme/app_theme.dart';
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
    final key = '${ref.read(currentMusicProvider).valueOrNull?.id ?? ''}_$lyricText';
    if (key == _lyricKey) return;
    _lyricKey = key;
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

    final estPos = _playing
        ? _basePos + DateTime.now().difference(_basePosTime)
        : _basePos;
    final idx = _findIndex(estPos);
    if (idx < 0) return const SizedBox.shrink();
    final progress = _progress(idx, estPos);

    return GestureDetector(
      onTap: () => _showLargeLyric(context),
      child: Container(
        height: _visibleLines * _lineHeight,
        margin: const EdgeInsets.fromLTRB(24, 4, 24, 8),
        child: AnimatedBuilder(
          animation: _tickerListenable,
          builder: (context, _) {
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