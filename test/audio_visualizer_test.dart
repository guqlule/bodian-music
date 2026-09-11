import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lx_music_flutter/widgets/audio_visualizer.dart';
import 'package:lx_music_flutter/services/audio/audio_analysis_service.dart';

void main() {
  for (final effect in VisualizerEffect.values) {
    testWidgets('AudioVisualizer ${effect.name} builds without error', (tester) async {
      final controller = StreamController<SpectrumData>.broadcast();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: AudioVisualizer(
                barCount: 32,
                effect: effect,
                spectrumStream: controller.stream,
                playing: true,
              ),
            ),
          ),
        ),
      );
      // 模拟频谱数据
      controller.add(SpectrumData(
        frequencies: List.generate(64, (i) => 0.5),
        bass: 0.5, mid: 0.4, treble: 0.3, volume: 0.4, beat: 1.0,
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));
      await controller.close();
    });
  }
}
