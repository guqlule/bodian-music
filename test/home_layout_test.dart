import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:lx_music_flutter/screens/home/home_screen.dart';

void main() {
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('lx_layout_test').path);
  });

  testWidgets('HomeScreen renders without layout errors', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: HomeScreen())),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  });
}
