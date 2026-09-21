import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/mini_ktv_lyric_bar.dart';
import 'effect_picker.dart';
import 'playlist_sheet.dart';
import '../../widgets/audio_visualizer.dart';
import '../../models/music_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/download_providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/player/player_service.dart';
import '../../services/api/songlist_service.dart';
import '../../services/audio/audio_analysis_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/logger.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<SonglistInfo> _recommendPlaylists = [];
  bool _isLoadingRecommend = false;

  @override
  void initState() {
    super.initState();
    _refreshRecommend();
  }

  Future<void> _refreshRecommend() async {
    setState(() => _isLoadingRecommend = true);
    try {
      final playlists = await SonglistService().getRecommendSonglists(page: 1, pageSize: 10);
      if (!mounted) return;
      setState(() {
        _recommendPlaylists = playlists;
        _isLoadingRecommend = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingRecommend = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: _buildDrawer(),
      body: PlayerHomeView(
        recommendPlaylists: _recommendPlaylists,
        isLoadingRecommend: _isLoadingRecommend,
        onRefreshRecommend: _refreshRecommend,
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 澶撮儴
            Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoftColor,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: AppNeumorphic.soft,
                    ),
                    child: Icon(Icons.music_note_rounded, size: 24, color: AppColors.primary),
                  ),
                  const SizedBox(height: 12),
                  Text('波点音乐', style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text('轻新拟态 · 治愈聆听', style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 11, letterSpacing: 1)),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 4),
            // 菜单项
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _drawerItem(Icons.search_rounded, '搜索', () => context.push('/search')),
                  _drawerItem(Icons.folder_open_rounded, '本地音乐', () => context.push('/local-music')),
                  _drawerItem(Icons.cloud_rounded, 'WebDAV 音乐库', () => context.push('/webdav')),
                  _drawerItem(Icons.equalizer_rounded, '均衡器', () => context.push('/equalizer')),
                  _drawerItem(Icons.library_music_rounded, '我的歌单', () => context.push('/my-list')),
                  _drawerItem(Icons.favorite_rounded, '我喜欢', () => context.push('/favorites')),
                  _drawerItem(Icons.download_rounded, '下载管理', () => context.push('/download')),
                  _drawerItem(Icons.history_rounded, '最近播放', () => context.push('/recent')),
                  _drawerItem(Icons.leaderboard_rounded, '排行榜', () => context.push('/leaderboard')),
                  _drawerItem(Icons.timer_rounded, '定时关闭', () => context.push('/sleep-timer')),
                  Divider(height: 1, color: AppColors.divider),
                  _drawerItem(Icons.settings_rounded, '设置', () => context.push('/settings')),
                  _drawerItem(Icons.info_outline_rounded, '关于', () => context.push('/about')),
                ],
              ),
            ),
            // 底部版本号
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Text('v1.0.0', style: TextStyle(color: AppColors.textHint, fontSize: 10)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.textSecondary, size: 20),
      ),
      title: Text(label, style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      dense: true,
      horizontalTitleGap: 12,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
    );
  }
}

// ==================== 首页播放器（新拟态治愈风） ====================
class PlayerHomeView extends ConsumerStatefulWidget {
  final List<SonglistInfo> recommendPlaylists;
  final bool isLoadingRecommend;
  final VoidCallback onRefreshRecommend;

  const PlayerHomeView({
    super.key,
    required this.recommendPlaylists,
    required this.isLoadingRecommend,
    required this.onRefreshRecommend,
  });

  @override
  ConsumerState<PlayerHomeView> createState() => _PlayerHomeViewState();
}

class _PlayerHomeViewState extends ConsumerState<PlayerHomeView>
    with TickerProviderStateMixin {
  late AnimationController _floatCtrl;
  late AnimationController _rotateCtrl;
  VisualizerEffect _currentEffect = VisualizerEffect.bars;
  Widget? _cachedVisualizer;

  @override
  void initState() {
    super.initState();
    _floatCtrl = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);
    _rotateCtrl = AnimationController(
      duration: const Duration(seconds: 60),
      vsync: this,
    );

    // 延迟初始化音频分析
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAudioAnalysis();
    });
  }

  void _initAudioAnalysis() {
    final audioAnalysis = ref.read(audioAnalysisProvider);
    // 注入会话解析器：全零数据时服务可在「真实 sid」和「0」之间自动切换重连
    audioAnalysis.setSessionResolver(() {
      try {
        final player = ref.read(playerServiceProvider);
        return player.audioPlayer.androidAudioSessionId;
      } catch (_) {
        return null;
      }
    });
    final playing = ref.read(isPlayingProvider).valueOrNull ?? false;
    logDebug('[Home] _initAudioAnalysis playing=$playing');
    if (playing) {
      _startAnalysisCapture();
    }
  }

  void _startAnalysisCapture() async {
    try {
      final player = ref.read(playerServiceProvider);
      final sessionId = await player.audioPlayer.androidAudioSessionId ?? 0;
      logDebug('[Home] _startAnalysisCapture sessionId=$sessionId');
      ref.read(audioAnalysisProvider).startCapture(sessionId);
    } catch (e) {
      logDebug('[Home] _startAnalysisCapture error: $e, fallback sessionId=0');
      ref.read(audioAnalysisProvider).startCapture(0);
    }
  }

  void _setupListeners() {
    ref.listen<AsyncValue<bool>>(isPlayingProvider, (prev, next) {
      final playing = next.valueOrNull ?? false;
      _syncRotation(playing);
      if (playing) {
        _startAnalysisCapture();
      } else {
        ref.read(audioAnalysisProvider).stopCapture();
      }
    });
  }

  @override
  void dispose() {
    _restartTimer?.cancel();
    _floatCtrl.dispose();
    _rotateCtrl.dispose();
    super.dispose();
  }

  void _syncRotation(bool playing) {
    if (playing && !_rotateCtrl.isAnimating) {
      _rotateCtrl.repeat();
    } else if (!playing && _rotateCtrl.isAnimating) {
      _rotateCtrl.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    _setupListeners();
    // 返回首页（详情页/其它页面 pop 回来）时恢复音频捕获：
    // isPlaying 值未变化不会触发 listen，特效数据流可能已断，需幂等兜底
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(audioAnalysisProvider).ensureCapturing();
      final playing = ref.read(isPlayingProvider).valueOrNull ?? false;
      _syncRotation(playing);
    });
    // 只 watch 必要的 provider，减少rebuild
    final currentMusic = ref.watch(currentMusicProvider);
    final playMode = ref.watch(playModeProvider);
    final currentIndex = ref.watch(currentIndexProvider);
    final playlistLen = ref.watch(currentPlaylistProvider.select((v) => v.whenData((l) => l.length)));

    // isPlaying 改用 listen，不触发全屏 rebuild
    final playing = ref.watch(isPlayingProvider).when(data: (p) => p, loading: () => false, error: (_, __) => false);
    final index = currentIndex.when(data: (i) => i, loading: () => -1, error: (_, __) => -1);
    final total = playlistLen.when(data: (l) => l, loading: () => 0, error: (_, __) => 0);

    return Stack(
      children: [
        SafeArea(
          child: currentMusic.when(
            data: (music) {
              if (music == null) return _buildEmpty();
              return OrientationBuilder(
                builder: (context, orientation) {
                  if (orientation == Orientation.landscape) {
                    return _buildLandscapePlayer(music, playing, playMode, index, total);
                  }
                  return _buildPlayer(music, playing, playMode, index, total);
                },
              );
            },
            loading: () => Center(
              child: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppNeumorphic.light,
                ),
                child: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
              ),
            ),
            error: (_, __) => _buildEmpty(),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Column(
      children: [
        // 顶部栏
        _buildTopBar(),
        // 空状态 + 推荐内容
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 28),
                // 孟菲斯风装饰
                _buildMemphisDecoration(),
                const SizedBox(height: 20),
                Text('还没有在播放的歌曲', style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 14)),
                const SizedBox(height: 6),
                Text('搜索在线音乐开始听歌', style: TextStyle(
                  color: AppColors.textHint, fontSize: 12)),
                const SizedBox(height: 16),
                // 搜索按钮
                GestureDetector(
                  onTap: () => context.push('/search'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text('发现音乐', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                // 推荐歌单（横向滑动）
                _buildRecommendSection(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 推荐歌单横滑区（空态时填充首页）
  Widget _buildRecommendSection() {
    if (widget.isLoadingRecommend && widget.recommendPlaylists.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
      );
    }
    if (widget.recommendPlaylists.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('推荐歌单', style: TextStyle(
              color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
            GestureDetector(
              onTap: widget.onRefreshRecommend,
              child: Icon(Icons.refresh_rounded, color: AppColors.textHint, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: widget.recommendPlaylists.length,
            itemBuilder: (context, idx) {
              final list = widget.recommendPlaylists[idx];
              return GestureDetector(
                onTap: () => context.push('/songlist-detail/${list.id}',
                    extra: {'name': list.name, 'source': list.source}),
                child: Container(
                  width: 120,
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: 120, height: 120,
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: AppNeumorphic.soft,
                            ),
                              child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: list.imgUrl.isNotEmpty
                                  ? Image.network(list.imgUrl, fit: BoxFit.cover, cacheWidth: 240,
                                      errorBuilder: (_, __, ___) => _playlistIcon(idx))
                                  : _playlistIcon(idx),
                            ),
                          ),
                          // 播放量角标
                          Positioned(
                            right: 6, bottom: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 11),
                                  Text(_formatCount(list.playCount), style: const TextStyle(
                                    color: Colors.white, fontSize: 9)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(list.name, style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(list.author, style: TextStyle(
                        color: AppColors.textHint, fontSize: 10),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _playlistIcon(int index) {
    final colors = [AppColors.accent1, AppColors.accent2, AppColors.accent3, AppColors.accent4];
    return Container(
      color: colors[index % colors.length].withValues(alpha: 0.3),
      child: Icon(Icons.queue_music_rounded, color: AppColors.primary, size: 32),
    );
  }

  String _formatCount(int count) {
    if (count >= 100000000) {
      return '${(count / 100000000).toStringAsFixed(1)}亿';
    }
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return '$count';
  }

  // 孟菲斯几何装饰
  Widget _buildMemphisDecoration() {
    return SizedBox(
      height: 160,
      width: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 大圆
          AnimatedBuilder(
            animation: _floatCtrl,
            builder: (_, __) => Transform.translate(
              offset: Offset(0, sin(_floatCtrl.value * pi) * 8),
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  color: AppColors.primarySoftColor,
                  shape: BoxShape.circle,
                  boxShadow: AppNeumorphic.soft,
                ),
              ),
            ),
          ),
          // 小三角
          Positioned(
            top: 10, right: 20,
            child: Transform.rotate(
              angle: pi / 6,
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: AppColors.accent1.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          // 小圆点
          Positioned(
            bottom: 20, left: 20,
            child: Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                color: AppColors.accent2.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
            ),
          ),
          // 方块
          Positioned(
            bottom: 30, right: 30,
            child: Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                color: AppColors.accent3.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          // 闊崇鍥炬爣
          Icon(Icons.headphones_rounded, size: 40, color: AppColors.primary),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
            // 菜单按钮 - 新拟态风格
          GestureDetector(
            onTap: () => Scaffold.of(context).openDrawer(),
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                boxShadow: AppNeumorphic.soft,
              ),
              child: Icon(Icons.menu_rounded, color: AppColors.textSecondary, size: 20),
            ),
          ),
          Row(
            children: [
              GestureDetector(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoftColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                child: Text('正在播放', style: TextStyle(
                    color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w500)),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _showCurrentSongMenu,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: AppNeumorphic.flat,
                  ),
                  child: Icon(Icons.more_vert_rounded, color: AppColors.textSecondary, size: 18),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _showEffectPicker,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: AppNeumorphic.flat,
                  ),
                  child: Icon(effectIconFor(_currentEffect), color: AppColors.textSecondary, size: 18),
                ),
              ),
              const SizedBox(width: 8),
              // 定时关闭快捷入口：激活时高亮并显示剩余分钟数
              Consumer(builder: (context, ref, _) {
                final active = ref.watch(sleepTimerActiveProvider).valueOrNull ?? false;
                return GestureDetector(
                  onTap: () => context.push('/sleep-timer'),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: active ? AppColors.primarySoftColor : AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: active ? null : AppNeumorphic.flat,
                    ),
                    child: Icon(
                      Icons.timer_rounded,
                      color: active ? AppColors.primary : AppColors.textSecondary,
                      size: 18,
                    ),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  void _showEffectPicker() {
    showEffectPicker(
      context,
      current: _currentEffect,
      onSelected: (effect) {
        setState(() {
          _currentEffect = effect;
          _cachedVisualizer = null;
        });
      },
    );
  }

  Widget _buildPlayer(MusicInfo music, bool playing, AsyncValue<PlayMode> playMode, int index, int total) {
    return Column(
      children: [
        _buildTopBar(),
        // 频谱动画区域（点击进详情，滑动手势切歌）
        Expanded(
          child: GestureDetector(
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity == null) return;
              if (details.primaryVelocity! < -100) {
                ref.read(playerServiceProvider).playNext();
              } else if (details.primaryVelocity! > 100) {
                ref.read(playerServiceProvider).playPrevious();
              }
            },
            child: Stack(
              children: [
                Positioned.fill(
                  top: 120,
                  child: _buildFullSpectrumVisualizer(playing),
                ),
                // 顶部歌曲信息（渐变遮罩保证可读性）
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: IgnorePointer(
                    child: _buildPlayingSongInfo(music, index, total),
                  ),
                ),
              ],
            ),
          ),
        ),
        // KTV 歌词条
        const MiniKtvLyricBar(),
        // 播放控制（自播放详情页移植：进度条 + 模式/上一首/播放暂停/下一首/队列）
        _buildHomeControls(music, playing),
      ],
    );
  }

  // ==================== 横屏布局（左右分栏）====================
  Widget _buildLandscapePlayer(MusicInfo music, bool playing, AsyncValue<PlayMode> playMode, int index, int total) {
    final currentPlayMode = playMode.valueOrNull ?? PlayMode.listLoop;
    final isLoading = ref.watch(isLoadingProvider).valueOrNull ?? false;
    final w = MediaQuery.of(context).size.width;

    IconData modeIcon() {
      switch (currentPlayMode) {
        case PlayMode.singleLoop: return Icons.repeat_one_rounded;
        case PlayMode.random: return Icons.shuffle_rounded;
        case PlayMode.list: return Icons.arrow_forward_rounded;
        case PlayMode.none: return Icons.block_rounded;
        case PlayMode.listLoop: return Icons.repeat_rounded;
      }
    }

    return Row(
      children: [
        // ===== 左侧：封面 + 歌名 + 控制 =====
        SizedBox(
          width: w * 0.38,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopBar(),
                const Spacer(),
                // 歌名 + 歌手（播放条上方）
                Text(
                  music.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  music.singer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 8),
                // 进度条
                const _HomeProgressBar(compact: false),
                // 控制按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _landscapeCtrlBtn(modeIcon(), () => ref.read(playerServiceProvider).togglePlayMode()),
                    _landscapeCtrlBtn(Icons.skip_previous_rounded, () => ref.read(playerServiceProvider).playPrevious(), size: 44),
                    GestureDetector(
                      onTap: () {
                        final p = ref.read(playerServiceProvider);
                        playing ? p.pause() : p.play();
                      },
                      child: Container(
                        width: 54, height: 54,
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          shape: BoxShape.circle,
                          boxShadow: AppNeumorphic.light,
                        ),
                        child: Container(
                          margin: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: playing ? AppColors.primary : AppColors.primarySoftColor,
                            shape: BoxShape.circle,
                          ),
                          child: isLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(7),
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                )
                              : Icon(
                                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: playing ? Colors.white : AppColors.primary,
                                  size: 24,
                                ),
                        ),
                      ),
                    ),
                    _landscapeCtrlBtn(Icons.skip_next_rounded, () => ref.read(playerServiceProvider).playNext(), size: 44),
                    _landscapeCtrlBtn(Icons.queue_music_rounded, () => showPlaylistSheet(context)),
                  ],
                ),
              ],
            ),
          ),
        ),
        // 分割线
        Container(
          width: 1,
          margin: const EdgeInsets.symmetric(vertical: 24),
          color: AppColors.divider,
        ),
        // ===== 右侧：频谱 + 歌词 =====
        Expanded(
          child: GestureDetector(
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity == null) return;
              if (details.primaryVelocity! < -100) {
                ref.read(playerServiceProvider).playNext();
              } else if (details.primaryVelocity! > 100) {
                ref.read(playerServiceProvider).playPrevious();
              }
            },
            child: Stack(
              children: [
                // 全屏频谱
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.1,
                    child: _buildFullSpectrumVisualizer(playing),
                  ),
                ),
                // 顶部歌曲信息（渐变遮罩）
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: IgnorePointer(
                    child: _buildPlayingSongInfo(music, index, total),
                  ),
                ),
                // KTV 歌词条（底部）
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    color: Colors.transparent,
                    child: const MiniKtvLyricBar(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _landscapeCtrlBtn(IconData icon, VoidCallback onTap, {double size = 40}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(size * 0.35),
          boxShadow: AppNeumorphic.flat,
        ),
        child: Icon(icon, color: AppColors.textSecondary, size: size * 0.5),
      ),
    );
  }

  /// 首页播放控制区（紧凑版进度条 + 控制按钮）
  Widget _buildHomeControls(MusicInfo music, bool playing) {
    final playMode = ref.watch(playModeProvider).valueOrNull ?? PlayMode.listLoop;

    IconData modeIcon() {
      switch (playMode) {
        case PlayMode.singleLoop:
          return Icons.repeat_one_rounded;
        case PlayMode.random:
          return Icons.shuffle_rounded;
        case PlayMode.list:
          return Icons.arrow_forward_rounded;
        case PlayMode.none:
          return Icons.block_rounded;
        case PlayMode.listLoop:
          return Icons.repeat_rounded;
      }
    }

    final isLoading = ref.watch(isLoadingProvider).valueOrNull ?? false;

    Widget ctrlBtn(IconData icon, VoidCallback onTap, {double size = 42, Color? iconColor}) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: size, height: size,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(size * 0.35),
            boxShadow: AppNeumorphic.flat,
          ),
          child: Icon(icon, color: iconColor ?? AppColors.textSecondary, size: size * 0.5),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
      child: Column(
        children: [
          // 紧凑进度条
          const _HomeProgressBar(),
          const SizedBox(height: 4),
          // 控制按钮排
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ctrlBtn(modeIcon(), () => ref.read(playerServiceProvider).togglePlayMode()),
              ctrlBtn(Icons.skip_previous_rounded, () => ref.read(playerServiceProvider).playPrevious(), size: 46),
              // 播放/暂停主按钮
              GestureDetector(
                onTap: () {
                  final p = ref.read(playerServiceProvider);
                  playing ? p.pause() : p.play();
                },
                child: Container(
                  width: 58, height: 58,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    shape: BoxShape.circle,
                    boxShadow: AppNeumorphic.light,
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: playing ? AppColors.primary : AppColors.primarySoftColor,
                      shape: BoxShape.circle,
                    ),
                    child: isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(7),
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          )
                        : Icon(
                            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: playing ? Colors.white : AppColors.primary,
                            size: 26,
                          ),
                  ),
                ),
              ),
              ctrlBtn(Icons.skip_next_rounded, () => ref.read(playerServiceProvider).playNext(), size: 46),
              ctrlBtn(Icons.queue_music_rounded, () => showPlaylistSheet(context), size: 42),
            ],
          ),
        ],
      ),
    );
  }

  /// 播放态歌曲信息卡（歌名/歌手/队列进度）
  Widget _buildPlayingSongInfo(MusicInfo music, int index, int total) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.background,
            AppColors.background.withValues(alpha: 0),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(music.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            music.singer.isNotEmpty
                ? (music.album.isNotEmpty ? '${music.singer} · ${music.album}' : music.singer)
                : music.album,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 音质徽章（实际播放音质）
              Consumer(builder: (context, ref, _) {
                final q = ref.watch(playQualityProvider).valueOrNull ?? '';
                final label = switch (q) {
                  'flac24bit' => 'Hi-Res',
                  'flac' => '无损',
                  '320k' => '320k',
                  '128k' => '128k',
                  _ => '',
                };
                if (label.isEmpty) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoftColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(label, style: const TextStyle(
                    color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w600)),
                );
              }),
              // 频谱模拟兜底提示：真实 FFT 不可用时，可视化在跑假数据，给个 "模拟" 角标
              Consumer(builder: (context, ref, _) {
                final playing = ref.watch(isPlayingProvider).valueOrNull ?? false;
                final simulating = ref.watch(audioAnalysisProvider).isSimulating;
                if (!playing || !simulating) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: AppNeumorphic.flat,
                  ),
                  child: Text('模拟', style: TextStyle(
                    color: AppColors.textHint, fontSize: 10, fontWeight: FontWeight.w500)),
                );
              }),
              if (total > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: AppNeumorphic.flat,
                  ),
                  child: Text('${index + 1} / $total', style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w500)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // 全屏频谱动画
  Widget _buildFullSpectrumVisualizer(bool playing) {
    final audioAnalysis = ref.read(audioAnalysisProvider);
    // 缓存的可视化器：effect 变化才创建新实例，playing 变化通过 didUpdateWidget 生效
    final cached = _cachedVisualizer;
    final shouldCreate = cached is! AudioVisualizer || cached.effect != _currentEffect;
    if (shouldCreate) {
      _cachedVisualizer = AudioVisualizer(
        key: ValueKey('viz_${_currentEffect.name}'),
        barCount: 32,
        effect: _currentEffect,
        spectrumStream: audioAnalysis.spectrumStream,
        playing: playing,
        onNativeStale: _onVizNativeStale,
        isDataAlive: () => audioAnalysis.isCapturing &&
            audioAnalysis.lastFftMax > 0.004,
      );
    }
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: AppColors.background,
      child: _cachedVisualizer!,
    );
  }

  /// 看门狗触发：播放中但原生 FFT 数据流中断（多为切歌后 Visualizer 绑定旧会话死亡）
  void _onVizNativeStale() {
    if (_restartTimer != null) return;
    _restartTimer = Timer(const Duration(milliseconds: 2500), () {
      _restartTimer = null;
      if (!(ref.read(isPlayingProvider).valueOrNull ?? false)) return;
      _startAnalysisCapture();
    });
  }

  Timer? _restartTimer;


  void _showPlaylist() {
    showPlaylistSheet(context);
  }

  /// 当前歌菜单（收藏 / 添加到歌单）——顶栏菜单按钮
  void _showCurrentSongMenu() {
    final music = ref.read(currentMusicProvider).valueOrNull;
    if (music == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前没有播放的歌曲')));
      return;
    }
    final isFav = ref.read(favoritesProvider.notifier).isFavorite(music.id);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoftColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: music.imgUrl != null && music.imgUrl!.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(music.imgUrl!, cacheWidth: 200, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.music_note_rounded,
                                    color: AppColors.primary, size: 22)),
                          )
                        : Icon(Icons.music_note_rounded, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(music.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(music.singer, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Container(width: 36, height: 36, decoration: BoxDecoration(
                color: AppColors.primarySoftColor, borderRadius: BorderRadius.circular(10)),
                child: Icon(
                  isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: AppColors.error, size: 18)),
              title: Text(isFav ? '取消喜欢' : '我喜欢',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              onTap: () {
                ref.read(favoritesProvider.notifier).toggleFavorite(music);
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(isFav ? '已取消喜欢' : '已加入我喜欢')));
              },
            ),
            ListTile(
              leading: Container(width: 36, height: 36, decoration: BoxDecoration(
                color: AppColors.primarySoftColor, borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.playlist_add_rounded, color: AppColors.primary, size: 18)),
              title: Text('添加到歌单',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              onTap: () {
                Navigator.pop(sheetContext);
                _showAddToPlaylistSheet(music);
              },
            ),
            ListTile(
              leading: Container(width: 36, height: 36, decoration: BoxDecoration(
                color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.queue_music_rounded, color: AppColors.textSecondary, size: 18)),
              title: Text('当前播放队列',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              onTap: () {
                Navigator.pop(sheetContext);
                _showPlaylist();
              },
            ),
            () {
              final isDl = ref.watch(downloadProvider).isDownloaded(music.id);
              if (isDl) {
                return ListTile(
                   leading: Container(
                       width: 36,
                       height: 36,
                       decoration: BoxDecoration(
                           color: AppColors.surface,
                           borderRadius: BorderRadius.circular(10)),
                       child: Icon(Icons.check_circle_rounded,
                           color: AppColors.primary, size: 18)),
                    title: Text('已下载',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 14)),
                    subtitle: Text('离线可用',
                        style: TextStyle(
                            color: AppColors.textHint, fontSize: 11)),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    ref
                        .read(downloadProvider.notifier)
                        .deleteDownloaded(music);
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(
                            content: Text('已删除本地「${music.name}」')));
                  },
                );
              } else {
                return ListTile(
                  leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(10)),
                       child: Icon(Icons.download_rounded,
                           color: AppColors.textSecondary, size: 18)),
                    title: Text('下载',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 14)),
                    subtitle: Text('保存到本地，离线播放',
                        style: TextStyle(
                            color: AppColors.textHint, fontSize: 11)),
                   onTap: () async {
                     final messenger = ScaffoldMessenger.maybeOf(context);
                     final quality = ref.read(settingsProvider).quality;
                     try {
                       await ref
                           .read(downloadProvider.notifier)
                           .download(music, quality: quality);
                     } catch (e) {
                       logDebug('[Download] 下载失败: $e');
                     }
                     if (!sheetContext.mounted) return;
                     Navigator.pop(sheetContext);
                     messenger?.showSnackBar(
                       const SnackBar(
                           content: Text(
                               '已加入下载队列，可在「下载管理」查看进度')),
                     );
                   },
                );
              }
            }(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 添加到歌单（歌单选择弹窗）
  void _showAddToPlaylistSheet(MusicInfo music) {
    final playlists = ref.read(playlistProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: EdgeInsets.all(16),
              child: Text('添加到歌单', style: TextStyle(
                color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            if (playlists.isEmpty)
              Padding(
                padding: EdgeInsets.all(24),
                child: Text('还没有歌单，先去创建一个吧',
                  style: TextStyle(color: AppColors.textHint, fontSize: 13)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final pl = playlists[index];
                    return ListTile(
                      leading: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primarySoftColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: pl.coverUrl != null && pl.coverUrl!.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(pl.coverUrl!, cacheWidth: 200, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.queue_music_rounded,
                                        color: AppColors.primary, size: 20)),
                              )
                            : Icon(Icons.queue_music_rounded, color: AppColors.primary, size: 20),
                      ),
                      title: Text(pl.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                      subtitle: Text('${pl.songs.length} 首',
                        style: TextStyle(color: AppColors.textHint, fontSize: 11)),
                      onTap: () {
                        ref.read(playlistProvider.notifier).addToPlaylist(pl.id, music);
                        Navigator.pop(sheetContext);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('已添加到「${pl.name}」')));
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

}

/// 独立进度条 Widget —— 用 ref.listen 代替 ref.watch，
/// 避免 position 每 200ms 变化导致整个首页 rebuild。
class _HomeProgressBar extends ConsumerStatefulWidget {
  final bool compact; // 竖屏紧凑模式
  const _HomeProgressBar({this.compact = true});

  @override
  ConsumerState<_HomeProgressBar> createState() => _HomeProgressBarState();
}

class _HomeProgressBarState extends ConsumerState<_HomeProgressBar> {
  // 仅用 ref.watch 触发重建，移除冗余的 ref.listen + setState
  // 拖动进度条时记录用户预览位置：拖动中显示预览值，松手才真正 seek，避免拖动时频繁 seek
  double? _scrubPos;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final pos = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final buffered = ref.watch(bufferedProvider).valueOrNull ?? Duration.zero;
    final dur = ref.watch(durationProvider).valueOrNull;

    final maxMs = (dur?.inMilliseconds ?? 0).toDouble().clamp(1.0, double.infinity);
    // 拖动中显示预览位置，否则显示真实播放位置
    final isScrubbing = _scrubPos != null;
    final activeMs = isScrubbing ? _scrubPos!.clamp(0.0, maxMs) : pos.inMilliseconds.toDouble().clamp(0.0, maxMs);
    final bufferedMs = buffered.inMilliseconds.toDouble().clamp(0.0, maxMs);
    final thumbR = widget.compact ? 6.0 : 5.0;
    final trackH = widget.compact ? 3.0 : 2.5;
    final fontSize = widget.compact ? 10.0 : 10.0;

    return Row(
      children: [
        // 左时间标签：长按快退 10s
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () {
            var target = pos - const Duration(seconds: 10);
            if (target < Duration.zero) target = Duration.zero;
            ref.read(playerServiceProvider).seek(target);
          },
          child: Text(isScrubbing ? _fmt(Duration(milliseconds: activeMs.round())) : _fmt(pos),
            style: TextStyle(
              color: isScrubbing ? AppColors.primary : AppColors.textHint,
              fontSize: fontSize,
              fontWeight: isScrubbing ? FontWeight.w600 : FontWeight.normal,
            )),
        ),
        Expanded(
          child: CustomSliderProgress(
            activeMs: activeMs,
            bufferedMs: bufferedMs,
            maxMs: maxMs,
            trackH: trackH,
            thumbR: thumbR,
            onChanged: (v) {
              // 预览值钳制到 [0, maxMs]，避免拖动越界导致右侧剩余时间变负
              _scrubPos = v.clamp(0.0, maxMs);
              setState(() {});
            },
            onRelease: (v) {
              _scrubPos = null;
              ref.read(playerServiceProvider).seek(Duration(milliseconds: v.toInt()));
            },
          ),
        ),
        // 右时间标签：长按快进 10s（不超时长）
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () {
            if (dur == null) return;
            var target = pos + const Duration(seconds: 10);
            if (target > dur) target = dur;
            ref.read(playerServiceProvider).seek(target);
          },
          child: Text(
            () {
              final shown = isScrubbing ? Duration(milliseconds: activeMs.round()) : pos;
              final remaining = dur != null ? dur - shown : null;
              if (remaining == null) return '-:--';
              return '-${_fmt(remaining < Duration.zero ? Duration.zero : remaining)}';
            }(),
            style: TextStyle(color: AppColors.textHint, fontSize: fontSize)),
        ),
      ],
    );
  }
}

/// 带缓冲进度的自定义滑条：
/// 底层灰色（inactive）→ 中层浅色（buffered 已缓冲）→ 顶层主色（active 已播放）。
/// 拖动时 [onChanged] 实时回调（更新预览值），松手 [onRelease] 才真正 seek。
class CustomSliderProgress extends StatelessWidget {
  final double activeMs;
  final double bufferedMs;
  final double maxMs;
  final double trackH;
  final double thumbR;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onRelease;

  const CustomSliderProgress({
    required this.activeMs,
    required this.bufferedMs,
    required this.maxMs,
    required this.trackH,
    required this.thumbR,
    required this.onChanged,
    required this.onRelease,
  });

  @override
  Widget build(BuildContext context) {
    // Flutter Slider 几何（对齐 slider_parts.dart / slider.dart）：
    // 覆盖 overlay 为 RoundSliderOverlayShape(overlayRadius: thumbR)，
    // 让左右 inset 都 = thumbR（对称），轨道 Y 中心 = (48 - trackH)/2。
    // 缓冲段用同样的 inset 与 Y 中心绘制，即与 Slider 轨道像素级对齐。
    const sliderHeight = 48.0;
    final inset = thumbR; // 对称缩进（overlayRadius = thumbR）
    final trackCenterY = (sliderHeight - trackH) / 2;

    final activeRatio = maxMs > 0 ? (activeMs / maxMs).clamp(0.0, 1.0) : 0.0;
    final bufferedRatio = maxMs > 0 ? (bufferedMs / maxMs).clamp(0.0, 1.0) : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // 两层都用 Positioned.fill 占满 Stack，像素级对齐
        return Stack(
          children: [
            // 中层：已缓冲段（浅主色）
            Positioned.fill(
              child: CustomPaint(
                painter: _BufferedBarPainter(
                  activeRatio: activeRatio,
                  bufferedRatio: bufferedRatio,
                  inset: inset,
                  trackH: trackH,
                  trackCenterY: trackCenterY,
                  color: AppColors.primary.withValues(alpha: 0.28),
                ),
              ),
            ),
            // 顶层：Slider（active 段 + 拖动 thumb + 交互）
            Positioned.fill(
              child: SizedBox(
                height: sliderHeight,
                width: width,
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: AppColors.divider,
                    thumbColor: AppColors.card,
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: thumbR, elevation: 2),
                    overlayShape: RoundSliderOverlayShape(overlayRadius: thumbR),
                    trackHeight: trackH,
                    overlayColor: AppColors.primarySoftColor,
                  ),
                  child: Slider(
                    value: activeMs,
                    max: maxMs,
                    onChanged: onChanged,
                    onChangeEnd: onRelease,
                  ),
                ),
              ),
            ),
            // 最顶层：双击定位 seek
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTapDown: (details) {
                  final ratio = ((details.localPosition.dx - inset) / (width - inset * 2)).clamp(0.0, 1.0);
                  onRelease((ratio * maxMs).roundToDouble());
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 在底层 track 之上、Slider 之下，画一条"已缓冲"浅色进度段。
/// 只画 active 末端到 buffered 末端之间的增量（active 本身由 Slider 画）。
class _BufferedBarPainter extends CustomPainter {
  final double activeRatio;
  final double bufferedRatio;
  final double inset; // 轨道左右缩进（与 Slider 的 max(overlay,thumb) 对齐）
  final double trackH;
  final double trackCenterY;
  final Color color;

  _BufferedBarPainter({
    required this.activeRatio,
    required this.bufferedRatio,
    required this.inset,
    required this.trackH,
    required this.trackCenterY,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bufferedRatio <= activeRatio) return; // 没有增量缓冲可画
    // 与 Slider 轨道相同的水平范围（左右各缩进 inset）
    final usableW = (size.width - inset * 2).clamp(0.0, size.width);
    final startX = inset + usableW * activeRatio;
    final endX = inset + usableW * bufferedRatio;
    final rect = Rect.fromLTRB(
      startX,
      trackCenterY - trackH / 2,
      endX,
      trackCenterY + trackH / 2,
    );
    final paint = Paint()..color = color;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(trackH / 2)), paint);
  }

  @override
  bool shouldRepaint(covariant _BufferedBarPainter old) =>
      old.activeRatio != activeRatio ||
      old.bufferedRatio != bufferedRatio ||
      old.color != color ||
      old.inset != inset ||
      old.trackH != trackH ||
      old.trackCenterY != trackCenterY;
}

