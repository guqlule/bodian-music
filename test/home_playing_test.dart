import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:lx_music_flutter/screens/home/home_screen.dart';
import 'package:lx_music_flutter/models/music_model.dart';
import 'package:lx_music_flutter/providers/app_providers.dart';

void main() {
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('lx_playing_test').path);
  });

  testWidgets('HomeScreen playing state (with playlist) renders without layout errors',
      (tester) async {
    final song = MusicInfo(
      id: 'tx_t1', name: '测试歌曲甲乙丙丁', singer: '测试歌手', album: '测试专辑',
      duration: 180000, source: 'tx', songId: '1', songmid: 'm1',
    );
    final song2 = MusicInfo(
      id: 'tx_t2', name: '第二首歌曲', singer: '歌手二号', album: '专辑二',
      duration: 200000, source: 'tx', songId: '2', songmid: 'm2',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [],
        child: MaterialApp(home: const HomeScreen()),
      ),
    );
    // 拿到 PlayerService（单例），手动注入播放状态而不触发网络
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    final player = container.read(playerServiceProvider);
    // 直接操作公开流不行——用反射不可行；改用只设置当前歌曲的方式：
    // PlayerService 没有公开注入接口，这里通过 playMusic 会在测试环境失败，
    // 但 currentMusicController.add 已在 playMusic 开头同步发生
    player.playMusic(song).catchError((_) {});
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // 再注入第二首到队列（模拟播放过两首）
    player.playMusic(song2).catchError((_) {});
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  });
}
