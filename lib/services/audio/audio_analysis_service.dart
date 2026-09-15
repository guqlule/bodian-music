import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/utils/logger.dart';

/// 频谱数据
class SpectrumData {
  final List<double> frequencies;
  final double bass;
  final double mid;
  final double treble;
  final double volume;
  final double beat;

  const SpectrumData({
    required this.frequencies,
    this.bass = 0,
    this.mid = 0,
    this.treble = 0,
    this.volume = 0,
    this.beat = 0,
  });

  static const empty = SpectrumData(frequencies: []);
}

/// 基于 Android 原生 Visualizer API 的音频分析服务。
/// 从播放会话直接抓 FFT 数据，不需要麦克风权限。
class AudioAnalysisService {
  static const _channel = MethodChannel('com.lxmusic/visualizer');
  final _outputController = StreamController<SpectrumData>.broadcast();

  bool _isPlaying = false;
  bool _capturing = false;
  int _currentSessionId = -1;

  // 环形缓冲区代替 List 队列，避免每帧分配新 List
  // 用 _historyIndex 跟踪下次写入位置，_historyFilled 跟踪有效元素数
  static const int _historySize = 3;
  final List<List<double>> _history = List.generate(
    _historySize,
    (_) => List<double>.filled(_nBars, 0),
  );
  int _historyIndex = 0;
  int _historyFilled = 0;
  double _lastBass = 0;
  double _beatThreshold = 0.15;
  int _beatCooldown = 0;
  int _logCounter = 0;

  // 诊断字段（供 UI 调试面板读取，无需 adb 即可排查）
  int framesReceived = 0;
  double lastFftMax = 0;
  bool lastStartOk = false;
  String? lastStartError;
  int reattachAttempts = 0;

  // 无帧看门狗：startCapture 成功但一个帧都收不到（原生创建失败/被系统拒绝）
  Timer? _noFrameWatchdog;
  DateTime _startAttemptAt = DateTime.now();

  // 全零数据看门狗：FFT 连续全零 → 尝试切换 session 重连
  DateTime lastLiveDataAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _zeroFrames = 0;
  int _reattachAttempts = 0;
  int? Function()? _sessionResolver;

  /// 提供 just_audio 的真实 audioSessionId（home_screen 注入）
  void setSessionResolver(int? Function()? resolver) => _sessionResolver = resolver;

  // 预分配的频率映射表，避免每帧重建
  static const int _nBars = 64;
  late List<int> _mapStartIdx;
  late List<int> _mapEndIdx;
  final List<double> _frequencies = List<double>.filled(_nBars, 0);
  final List<double> _smoothed = List<double>.filled(_nBars, 0);
  int _lastFftLength = 0;

  Stream<SpectrumData> get spectrumStream => _outputController.stream;
  bool get isPlaying => _isPlaying;
  bool get isCapturing => _capturing;

  AudioAnalysisService() {
    _channel.setMethodCallHandler(_onMethodCall);
    // 预计算频率映射表（基于 FFT 长度 1024）
    _initFrequencyMap(1024);
  }

  void _initFrequencyMap(int nFft) {
    _lastFftLength = nFft;
    _mapStartIdx = List<int>.filled(_nBars, 0);
    _mapEndIdx = List<int>.filled(_nBars, 0);
    final logN = log(nFft.toDouble());
    for (int i = 0; i < _nBars; i++) {
      final logMin = (i / _nBars) * logN;
      final logMax = ((i + 1) / _nBars) * logN;
      _mapStartIdx[i] = exp(logMin).floor().clamp(0, nFft - 1);
      _mapEndIdx[i] = exp(logMax).ceil().clamp(_mapStartIdx[i], nFft - 1);
    }
  }

  Future<void> _onMethodCall(MethodCall call) async {
    if (call.method == 'onFftData') {
      // 原生传 DoubleArray → 编解码为 Float64List（零装箱），兜底兼容 List
      final raw = call.arguments['frequencies'];
      final List<double> freqs = raw is Float64List
          ? raw
          : (raw as List).cast<double>();
      framesReceived++;
      _processFftData(freqs);
    }
  }

  /// 切换会话重连（全零数据时调用）：
  /// sid=0 全局混音在某些设备/版本抓不到数据，真实 sid 失效后也会全零，
  /// 因此在「真实 sid」和「0」之间自动交替重试。
  Future<void> _reattachWithAltSession() async {
    final realSid = _sessionResolver?.call();
    int alt;
    if (_currentSessionId == 0) {
      if (realSid == null || realSid <= 0) return; // 没有真实会话可换，维持现状
      alt = realSid;
    } else {
      alt = 0;
    }
    _reattachAttempts++;
    reattachAttempts = _reattachAttempts;
    logDebug('[AudioAnalysis] FFT 全零，尝试切换会话 $_currentSessionId -> $alt (尝试$_reattachAttempts)');
    await startCapture(alt, resetAttempts: false);
  }

  /// 确保捕获在运行（幂等）
  Future<void> ensureCapturing() async {
    if (!_isPlaying || _capturing) return;
    await startCapture(_currentSessionId);
  }

  /// 开始捕获（传入 just_audio 的 audioSessionId）
  Future<void> startCapture(int sessionId, {bool resetAttempts = true}) async {
    _isPlaying = true;
    _currentSessionId = sessionId;
    framesReceived = 0;
    _zeroFrames = 0;
    lastFftMax = 0;
    _startAttemptAt = DateTime.now();
    if (resetAttempts) _reattachAttempts = 0;
    try {
      // sessionId=0 表示全局输出混合（需 RECORD_AUDIO 运行时权限）；
      // 真实会话 id 不需要权限，避免弹麦克风授权框
      if (sessionId == 0) await _ensureRecordPermission();
      final result = await _channel.invokeMethod<Map>('startCapture', {'sessionId': sessionId});
      final ok = result?['ok'] == true;
      _capturing = ok;
      lastStartOk = ok;
      lastStartError = result?['error'] as String?;
      logDebug('[AudioAnalysis] 开始捕获音频 session=$sessionId ok=$ok err=$lastStartError');
    } catch (e) {
      logDebug('[AudioAnalysis] 捕获启动失败: $e');
      _capturing = false;
      lastStartOk = false;
      lastStartError = '$e';
    }
    _startNoFrameWatchdog();
  }

  /// 全局混音 (sessionId=0) 在多数系统上需要 RECORD_AUDIO 运行时权限
  Future<void> _ensureRecordPermission() async {
    try {
      final status = await Permission.microphone.status;
      if (!status.isGranted) {
        final res = await Permission.microphone.request();
        logDebug('[AudioAnalysis] RECORD_AUDIO 权限请求结果: $res');
      }
    } catch (e) {
      logDebug('[AudioAnalysis] 权限请求异常: $e');
    }
  }

  /// 强制用当前 sessionId 重启捕获（看门狗用）
  Future<void> restartCapture() async {
    await startCapture(_currentSessionId);
  }

  /// 查询原生 Visualizer 状态（无需 adb）
  Future<Map<String, dynamic>?> getNativeStatus() async {
    try {
      final result = await _channel.invokeMethod<Map>('getNativeStatus');
      return result?.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  int get currentSessionId => _currentSessionId;

  /// 停止捕获
  Future<void> stopCapture() async {
    _isPlaying = false;
    _noFrameWatchdog?.cancel();
    _noFrameWatchdog = null;
    try {
      await _channel.invokeMethod('stopCapture');
    } catch (_) {}
    _capturing = false;
    _outputController.add(SpectrumData.empty);
  }

  void updatePlayingState(bool isPlaying, {int sessionId = 0}) {
    if (isPlaying) {
      startCapture(sessionId);
    } else {
      stopCapture();
    }
  }

  void _startNoFrameWatchdog() {
    _noFrameWatchdog?.cancel();
    _noFrameWatchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_isPlaying) return;
      if (_capturing && framesReceived > 0) {
        _noFrameWatchdog?.cancel();
        _noFrameWatchdog = null;
        return;
      }
      // 原生启动失败 (cap=OFF) 或启动后 4 秒一帧未到 → 换会话重试
      final elapsed = DateTime.now().difference(_startAttemptAt).inMilliseconds;
      if (elapsed < 4000) return;
      _noFrameWatchdog?.cancel();
      _noFrameWatchdog = null;
      logDebug('[AudioAnalysis] 启动4秒无帧/失败，尝试备用会话 (当前 sid=$_currentSessionId)');
      _reattachWithAltSession();
    });
  }

  void _processFftData(List<double> fft) {
    if (fft.isEmpty) return;

    // 对数频率映射（使用预计算的映射表，避免每帧 exp/log 计算）
    final nFft = fft.length;
    // 动态调整映射表（如果 FFT 长度变化）
    if (nFft != _lastFftLength) _initFrequencyMap(nFft);

    double globalMax = 0;
    for (int i = 0; i < _nBars; i++) {
      final startIdx = _mapStartIdx[i];
      final endIdx = _mapEndIdx[i].clamp(startIdx, nFft - 1);
      double maxVal = 0;
      for (int j = startIdx; j <= endIdx; j++) {
        final v = fft[j].abs();
        if (v > maxVal) maxVal = v;
      }
      if (maxVal > 1.0) maxVal = 1.0;
      _frequencies[i] = maxVal;
      if (maxVal > globalMax) globalMax = maxVal;
    }
    lastFftMax = globalMax;

    // 全零数据看门狗：数据在流动但内容是静音 → 换会话重连
    if (lastFftMax > 0.004) {
      _zeroFrames = 0;
      _reattachAttempts = 0;
      lastLiveDataAt = DateTime.now();
    } else {
      _zeroFrames++;
      // 16ms 一帧，300 帧 ≈ 4.8 秒全零才触发；最多重试 4 次
      if (_zeroFrames >= 300 && _reattachAttempts < 4) {
        _zeroFrames = 0;
        _reattachWithAltSession();
      }
    }

    // 写入环形缓冲区（零分配）
    final slot = _history[_historyIndex];
    for (int i = 0; i < _nBars; i++) {
      slot[i] = _frequencies[i];
    }
    _historyIndex = (_historyIndex + 1) % _historySize;
    if (_historyFilled < _historySize) _historyFilled++;

    // 平滑 + 分段累加（合并到一个循环，避免多次遍历 _smoothed）
    // 旧实现：3 次 for 循环（累计、bass、mid、treble）= 256 次迭代
    // 新实现：1 次 for 循环 = 64 次迭代
    final invHist = 1.0 / _historyFilled;
    double bassSum = 0, midSum = 0, trebleSum = 0;
    for (int i = 0; i < _nBars; i++) {
      double sum = 0;
      for (int h = 0; h < _historyFilled; h++) {
        sum += _history[h][i];
      }
      final v = sum * invHist;
      _smoothed[i] = v;
      if (i < 16) {
        bassSum += v;
      } else if (i < 40) {
        midSum += v;
      } else {
        trebleSum += v;
      }
    }
    final bass = bassSum / 16;
    final mid = midSum / 24;
    final treble = trebleSum / 24;

    if (_beatCooldown > 0) _beatCooldown--;
    double beat = 0;
    if (bass > _lastBass + _beatThreshold && _beatCooldown == 0) {
      beat = 1.0;
      _beatCooldown = 6;
    }
    _lastBass = bass;

    final volume = bass * 0.4 + mid * 0.35 + treble * 0.25;

    _outputController.add(SpectrumData(
      frequencies: _smoothed,
      bass: bass, mid: mid, treble: treble,
      volume: volume, beat: beat,
    ));
  }

  void dispose() {
    _noFrameWatchdog?.cancel();
    _noFrameWatchdog = null;
    stopCapture();
    _outputController.close();
  }
}

final audioAnalysisProvider = Provider<AudioAnalysisService>((ref) {
  final service = AudioAnalysisService();
  ref.onDispose(() => service.dispose());
  return service;
});
