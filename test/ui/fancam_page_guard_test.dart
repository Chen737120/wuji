// 缺陷 1 回归守卫（冒烟 s33/s36/s64 ＋ flutter run 堆栈 fancam_page.dart:707）：
// FancamPage 首帧 build 时 _ctl/_track 尚未初始化（_init 异步、video_player
// initialize 未返回），`_controlsVisible` 默认 true → 底部条挂载 →
// `valueListenable: _ctl!` 抛 Null check operator used on a null value，
// 进圈选页即红屏（3/3 复现）。修复＝底部条加 ctl != null 初始化门
// （顶部返回不加门：视频加载慢时用户仍须能返回）。本测试锁住两条：
// ① 首帧 build 不抛异常；② 加载期底部条（含「＋打码」）不挂载、返回可用。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/media_source_picker.dart';
import 'package:wuji/ui/fancam/fancam_page.dart';

void main() {
  testWidgets('首帧（视频未初始化）不抛 Null check——底部条初始化门', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FancamPage(
        source: const PickedSource(path: '/tmp/guard.mp4', name: 'guard'),
      ),
    ));
    expect(tester.takeException(), isNull,
        reason: '首帧 build 不得抛 Null check operator（冒烟缺陷 1）');
    // 加载期：顶部返回可用，底部条未挂载
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.text('＋打码'), findsNothing);
  });
}
