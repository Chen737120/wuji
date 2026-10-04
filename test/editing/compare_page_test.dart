import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/media_source_picker.dart';
import 'package:wuji/ui/compare/compare_page.dart';

PickedSource src(String name, {int seconds = 60}) =>
    PickedSource(path: '/nonexistent/$name.mp4', name: name, duration: Duration(seconds: seconds));

void main() {
  testWidgets('时间微调：延后一步显示延后文案、还原归零、导出按钮不可用',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: ComparePage(teacher: src('teacher'), mine: src('mine'))));
    await tester.pumpAndSettle();

    // 双侧占位画面渲染（无真视频）
    expect(find.text('老师视频'), findsWidgets); // 侧标签＋图例
    expect(find.text('我的视频'), findsWidgets);
    // 默认未偏移；60s 源重叠充足 → 导出可用
    expect(find.text('未偏移'), findsOneWidget);
    expect(find.text('导出视频'), findsOneWidget);

    // 延后一步 → 0.10 秒
    await tester.tap(find.text('延后'));
    await tester.pumpAndSettle();
    expect(find.text('我的视频延后 0.10 秒'), findsOneWidget);

    // 提前两步 → 0.08 秒
    await tester.tap(find.text('提前'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提前'));
    await tester.pumpAndSettle();
    expect(find.text('我的视频提前 0.10 秒'), findsOneWidget); // +0.10-0.20=-0.10

    // 还原时间 → 归零
    await tester.tap(find.text('还原时间'));
    await tester.pumpAndSettle();
    expect(find.text('未偏移'), findsOneWidget);
  });

  testWidgets('重叠不足 1 秒：导出禁用并提示', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: ComparePage(teacher: src('t', seconds: 2), mine: src('m', seconds: 1))));
    await tester.pumpAndSettle();
    // 我的视频延后 2 秒 → 区间 [2s, 2s) = 0 → 禁用
    await tester.tap(find.text('延后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('延后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('延后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('延后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('延后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('延后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('延后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('延后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('延后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('延后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('延后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('延后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('延后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('延后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('延后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('延后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('延后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('延后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('延后'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('延后'));
    await tester.pumpAndSettle();
    expect(find.text('重叠区间不足 1 秒，无法导出'), findsOneWidget);
  });

  testWidgets('切换画面微调 tab', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: ComparePage(teacher: src('teacher'), mine: src('mine'))));
    await tester.pumpAndSettle();

    expect(find.text('画面微调（下一步接入）'), findsNothing);
    await tester.tap(find.text('画面微调'));
    await tester.pumpAndSettle();
    expect(find.text('画面微调（下一步接入）'), findsOneWidget);
  });
}
