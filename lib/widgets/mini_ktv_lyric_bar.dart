import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../core/theme/app_theme.dart';
import '../services/lyric/lyric_parser.dart';
import '../screens/pv_lyrics/pv_lyrics_screen.dart';
import 'large_ktv_overlay.dart';

/// Mini播放器上方的 5 行 KTV 歌词（当前行扫字，前后各 2 行陪衬）
/// 使用 Ticker 逐帧插值，扫字平滑不卡顿
class MiniKtvLyricBar extends ConsumerStatefulWidget {
  const MiniKtvLyricBar({super.key});

  @override
  ConsumerState<MiniKtvLyricBar> createState() => _MiniKtvLyricBarState();
}

class _MiniKtvLyricBarState extends ConsumerState<MiniKtvLyricBar>
    with SingleTickerProviderStateMixin {
  /// 显示行数（当前行居中，前后各 2 行）
  static const int _visibleLines = 5;
  static const double _lineHeight = 36;

  List<LyricLine> _lyrics = [];
  String _lyricKey = '';

  // 位置基准点（流更新）+ 播放状态，用于帧间外推
  Duration _basePos = Duration.zero;
  DateTime _basePosTime = DateTime.now();
  bool _playing = false;
  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
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

  /// 播放中启动 Ticker（逐帧刷新扫字），暂停时停止
  /// 注意：不 dispose ticker（SingleTickerProviderStateMixin 的 ticker
  /// 只能创建一次），暂停只 stop，恢复时重新 start
  void _syncTicker() {
    if (_playing && mounted) {
      if (_ticker == null) {
        _ticker = createTicker(_onTick);
      }
      if (!_ticker!.isActive) {
        _ticker!.start();
      }
    } else if (!_playing) {
      _ticker?.stop();
    }
  }

  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    if (_lyrics.isEmpty && _ticker != null) {
      _ticker!.stop();
    }
    // 节流至 ~30fps：歌词扫字不需要60fps，30fps 已足够流畅且减半 rebuild 开销
    final now = DateTime.now();
    if (now.difference(_lastTick).inMilliseconds < 33) return;
    _lastTick = now;
    setState(() {}); // 进度在 build 中按外推位置计算
  }

  void _tryParseLyric(Map<String, String?>? lyricMap) {
    final lyricText = lyricMap?['lyric'] ?? '';
    final key = '${ref.read(currentMusicProvider).valueOrNull?.id ?? ''}_$lyricText';
    if (key == _lyricKey) return;
    _lyricKey = key;
    _lyrics = LyricParser.parse(lyricText);
    // 歌词到达后重启 ticker（空歌词时被暂停过）
    if (_lyrics.isNotEmpty && _playing && _ticker != null && !_ticker!.isActive) {
      _ticker!.start();
    }
  }

  // 当前行索引
  int _findIndex(Duration pos) {
    int idx = -1;
    for (int i = 0; i < _lyrics.length; i++) {
      if (pos >= _lyrics[i].time) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  void _showLargeLyric(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const PvLyricsScreen(),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 歌词数据
    ref.listen(lyricProvider, (prev, next) {
      _tryParseLyric(next.valueOrNull);
      if (mounted) setState(() {});
    });
    // 位置更新：记录基准点（流是200ms节流，帧间由Ticker外推）
    ref.listen(positionProvider, (prev, next) {
      next.whenData((p) {
        _basePos = p;
        _basePosTime = DateTime.now();
        if (!_playing && mounted) setState(() {});
      });
    });
    // 播放状态：控制 Ticker
    ref.listen(isPlayingProvider, (prev, next) {
      final p = next.valueOrNull ?? false;
      if (p != _playing) {
        _playing = p;
        _syncTicker();
      }
    });
    // 切歌时重置
    ref.listen(currentMusicProvider, (prev, next) {
      if (prev?.valueOrNull?.id != next.valueOrNull?.id) {
        _lyricKey = '';
        _lyrics = [];
        _tryParseLyric(ref.read(lyricProvider).valueOrNull);
        if (mounted) setState(() {});
      }
    });

    // 外推当前位置：基准位置 + 播放中经过的时间
    final now = DateTime.now();
    final estPos = _playing
        ? _basePos + now.difference(_basePosTime)
        : _basePos;

    // 计算当前行 + 扫字进度
    final idx = _findIndex(estPos);
    double progress = 0;

    if (idx >= 0 && _lyrics.isNotEmpty) {
      final line = _lyrics[idx];
      // 行结束时间 = 下一行开始（或当前+5s）
      final lineEnd = idx + 1 < _lyrics.length
          ? _lyrics[idx + 1].time
          : line.time + const Duration(seconds: 5);
      final lineDur = lineEnd - line.time;
      if (lineDur > Duration.zero) {
        progress = ((estPos - line.time).inMilliseconds / lineDur.inMilliseconds)
            .clamp(0.0, 1.0);
      }
    }

    return GestureDetector(
      onTap: () {
        // 点击弹出大歌词 overlay
        _showLargeLyric(context);
      },
      child: Container(
        height: _visibleLines * _lineHeight,
        margin: const EdgeInsets.fromLTRB(24, 4, 24, 8),
        child: _lyrics.isEmpty || idx < 0
            ? const SizedBox.shrink()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_visibleLines, (slot) {
                  final lineIdx = idx - (_visibleLines ~/ 2) + slot;
                  final isCurrent = lineIdx == idx;
                  if (lineIdx < 0 || lineIdx >= _lyrics.length) {
                    return SizedBox(height: _lineHeight);
                  }
                  final text = _lyrics[lineIdx].text;
                  if (text.isEmpty) return SizedBox(height: _lineHeight);

                  if (!isCurrent) {
                    // 非当前行：淡灰小字，离当前行越远越淡
                    final distance = (lineIdx - idx).abs();
                    final opacity = distance == 1 ? 0.55 : 0.3;
                    return Container(
                      height: _lineHeight,
                      alignment: Alignment.center,
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary.withValues(alpha: opacity),
                        ),
                      ),
                    );
                  }
                  // 当前行：LerpScanText 逐字符 Color.lerp 扫字（零伪影）
                  return Container(
                    height: _lineHeight,
                    alignment: Alignment.center,
                    child: LerpScanText(
                      text: text,
                      progress: progress,
                      scannedColor: AppColors.primaryDark,
                      unscannedColor: AppColors.textHint,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  );
                }),
              ),
      ),
    );
  }
}
