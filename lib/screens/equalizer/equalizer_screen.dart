import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../services/platform/equalizer_service.dart';

class EqualizerScreen extends ConsumerStatefulWidget {
  const EqualizerScreen({super.key});

  @override
  ConsumerState<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends ConsumerState<EqualizerScreen> {
  final _eqService = EqualizerService();
  bool _isEnabled = true;
  String _currentPreset = 'flat';
  List<_EqBand> _bands = [];
  bool _isSupported = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initEqualizer();
  }

  Future<void> _initEqualizer() async {
    try {
      final playerService = ref.read(playerServiceProvider);
      final audioPlayer = playerService.audioPlayer;

      // 获取当前音频会话 ID
      final sessionId = await audioPlayer.androidAudioSessionId;
      if (sessionId != null && sessionId != 0) {
        await _eqService.attachSession(sessionId);
        final info = await _eqService.getInfo();
        if (info != null && mounted) {
          setState(() {
            _isSupported = true;
            _isEnabled = info.enabled;
            _bands = info.bands.map((b) => _EqBand(
              index: b.index,
              centerFreq: b.centerFreq,
              minLevel: b.minLevel,
              maxLevel: b.maxLevel,
              gain: b.currentLevel,
            )).toList();
            _isLoading = false;
          });
          // 加载持久化设置并应用
          await _loadPersistedSettings();
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isSupported = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPersistedSettings() async {
    final settings = await _eqService.loadSettings();
    if (settings == null || !mounted) return;
    setState(() => _isEnabled = settings.enabled);
    await _eqService.setEnabled(settings.enabled);
    if (settings.preset != 'flat' || settings.bandLevels != null) {
      if (settings.bandLevels != null && settings.bandLevels!.length == _bands.length) {
        setState(() {
          _currentPreset = settings.preset;
          for (int i = 0; i < _bands.length; i++) {
            _bands[i].gain = settings.bandLevels![i];
          }
        });
        for (int i = 0; i < _bands.length; i++) {
          await _eqService.setBandLevel(_bands[i].index, settings.bandLevels![i]);
        }
      } else {
        _applyPreset(settings.preset);
      }
    }
  }

  void _toggleEqualizer(bool value) async {
    setState(() => _isEnabled = value);
    await _eqService.setEnabled(value);
    _saveCurrentSettings();
  }

  void _applyPreset(String presetId) {
    setState(() => _currentPreset = presetId);
    final gains = _getPresetGains(presetId);
    for (int i = 0; i < _bands.length && i < gains.length; i++) {
      _bands[i].gain = gains[i];
      _eqService.setBandLevel(_bands[i].index, gains[i]);
    }
    _saveCurrentSettings();
  }

  void _saveCurrentSettings() {
    final levels = _bands.map((b) => b.gain).toList();
    _eqService.setBandLevels(levels, _currentPreset);
  }

  List<int> _getPresetGains(String preset) {
    final n = _bands.length;
    switch (preset) {
      case 'flat':
        return List.filled(n, 0);
      case 'bass':
        return List.generate(n, (i) {
          final norm = i / (n - 1).clamp(1, n - 1);
          return norm < 0.4 ? ((0.4 - norm) * 1200).toInt().clamp(-1200, 1200) : 0;
        });
      case 'treble':
        return List.generate(n, (i) {
          final norm = i / (n - 1).clamp(1, n - 1);
          return norm > 0.6 ? ((norm - 0.6) * 1200).toInt().clamp(-1200, 1200) : 0;
        });
      case 'vocal':
        return List.generate(n, (i) {
          final norm = i / (n - 1).clamp(1, n - 1);
          return (norm > 0.3 && norm < 0.7) ? 400 : -200;
        });
      case 'rock':
        return List.generate(n, (i) {
          final norm = i / (n - 1).clamp(1, n - 1);
          if (norm < 0.3) return 400;
          if (norm > 0.7) return 300;
          return -100;
        });
      case 'electronic':
        return List.generate(n, (i) {
          final norm = i / (n - 1).clamp(1, n - 1);
          if (norm < 0.25) return 500;
          if (norm > 0.75) return 400;
          return -200;
        });
      case 'jazz':
        return List.generate(n, (i) {
          final norm = i / (n - 1).clamp(1, n - 1);
          if (norm < 0.3) return 300;
          if (norm > 0.5 && norm < 0.8) return 200;
          return 0;
        });
      case 'classical':
        return List.generate(n, (i) {
          final norm = i / (n - 1).clamp(1, n - 1);
          if (norm < 0.2) return 200;
          if (norm > 0.8) return 300;
          return 0;
        });
      default:
        return List.filled(n, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('均衡器'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isSupported)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Switch(
                value: _isEnabled,
                onChanged: _toggleEqualizer,
                activeThumbColor: AppColors.primary,
              ),
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _isSupported
              ? _buildEqualizer()
              : _buildUnsupported(),
    );
  }

  Widget _buildUnsupported() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.primarySoftColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppNeumorphic.soft,
            ),
            child: Icon(Icons.equalizer_rounded, size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          Text('均衡器暂不可用',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('请先播放一首歌曲，均衡器会自动连接',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _initEqualizer,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                boxShadow: AppNeumorphic.soft,
              ),
              child: Text('重试', style: TextStyle(color: AppColors.primary, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEqualizer() {
    return Column(
      children: [
        _buildPresets(),
        const SizedBox(height: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                _buildScaleLabels(),
                const SizedBox(height: 4),
                Expanded(
                  child: Row(
                    children: _bands.map((band) {
                      return Expanded(child: _buildBandColumn(band));
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: GestureDetector(
            onTap: () => _applyPreset('flat'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                boxShadow: AppNeumorphic.flat,
              ),
              child: Center(
                child: Text('重置为平坦', style: TextStyle(
                  color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPresets() {
    final presets = [
      ('flat', '平坦'),
      ('bass', '低音增强'),
      ('treble', '高音增强'),
      ('vocal', '人声'),
      ('rock', '摇滚'),
      ('electronic', '电子'),
      ('jazz', '爵士'),
      ('classical', '古典'),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: presets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (id, name) = presets[index];
          final isSelected = _currentPreset == id;
          return GestureDetector(
            onTap: () => _applyPreset(id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.card,
                borderRadius: BorderRadius.circular(12),
                boxShadow: isSelected ? [] : AppNeumorphic.flat,
              ),
              child: Center(
                child: Text(name, style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                  fontSize: 12, fontWeight: FontWeight.w500)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildScaleLabels() {
    return SizedBox(
      height: 20,
      child: Row(
        children: [
          Expanded(child: Text('+12', textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textHint, fontSize: 9))),
          Expanded(child: Text('+6', textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textHint, fontSize: 9))),
          Expanded(child: Text('0', textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w600))),
          Expanded(child: Text('-6', textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textHint, fontSize: 9))),
          Expanded(child: Text('-12', textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textHint, fontSize: 9))),
        ],
      ),
    );
  }

  Widget _buildBandColumn(_EqBand band) {
    final gainDb = band.gain / 100.0;
    return Column(
      children: [
        Text(
          '${gainDb > 0 ? '+' : ''}${gainDb.toStringAsFixed(0)}',
          style: TextStyle(
            color: gainDb > 0 ? AppColors.primary : gainDb < 0 ? AppColors.error : AppColors.textHint,
            fontSize: 10, fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: RotatedBox(
            quarterTurns: -1,
            child: Slider(
              value: band.gain.toDouble().clamp(band.minLevel.toDouble(), band.maxLevel.toDouble()),
              min: band.minLevel.toDouble(),
              max: band.maxLevel.toDouble(),
              activeColor: gainDb > 0 ? AppColors.primary : gainDb < 0 ? AppColors.error : AppColors.textSecondary,
              inactiveColor: AppColors.border,
              onChanged: (value) {
                final level = value.toInt();
                setState(() {
                  band.gain = level;
                  _currentPreset = 'custom';
                });
                _eqService.setBandLevel(band.index, level);
                _saveCurrentSettings();
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(band.displayFreq, style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
      ],
    );
  }
}

class _EqBand {
  final int index;
  final int centerFreq;
  final int minLevel;
  final int maxLevel;
  int gain;

  _EqBand({
    required this.index,
    required this.centerFreq,
    required this.minLevel,
    required this.maxLevel,
    required this.gain,
  });

  String get displayFreq {
    if (centerFreq >= 1000) {
      final k = centerFreq / 1000;
      return k == k.roundToDouble() ? '${k.toInt()}k' : '${k.toStringAsFixed(1)}k';
    }
    return centerFreq.toString();
  }
}
