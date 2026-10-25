// 模式开关单测（Task 4 ruling 6）：FancamPage 全页测试受 video_player 平台通道
// 限制（代码库无 fancam_page 测试先例），故把模式开关抽成顶层小 widget 单测
// 回调与选中态；FancamPage 中默认值为 FancamEditMode.manual（页面字段初始化）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/ui/fancam/fancam_page.dart';

void main() {
  Widget host(FancamEditMode mode, ValueChanged<FancamEditMode> onChanged) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: FancamModeSwitch(mode: mode, onChanged: onChanged),
          ),
        ),
      );

  testWidgets('两个段「手动」「自动跟踪」；选中态随 mode 参数', (tester) async {
    await tester.pumpWidget(
        host(FancamEditMode.manual, (_) {}));
    expect(find.text('手动'), findsOneWidget);
    expect(find.text('自动跟踪'), findsOneWidget);
    final seg = tester.widget<SegmentedButton<FancamEditMode>>(
        find.byType(SegmentedButton<FancamEditMode>));
    expect(seg.selected, {FancamEditMode.manual},
        reason: '手动为默认模式（ruling 1）');
    // follow 传入时选中态切换
    await tester.pumpWidget(host(FancamEditMode.follow, (_) {}));
    final seg2 = tester.widget<SegmentedButton<FancamEditMode>>(
        find.byType(SegmentedButton<FancamEditMode>));
    expect(seg2.selected, {FancamEditMode.follow});
  });

  testWidgets('点「自动跟踪」→ onChanged(FancamEditMode.follow)', (tester) async {
    FancamEditMode? got;
    await tester.pumpWidget(host(FancamEditMode.manual, (m) => got = m));
    await tester.tap(find.text('自动跟踪'));
    await tester.pump();
    expect(got, FancamEditMode.follow);
  });

  testWidgets('点「手动」→ onChanged(FancamEditMode.manual)', (tester) async {
    FancamEditMode? got;
    await tester.pumpWidget(host(FancamEditMode.follow, (m) => got = m));
    await tester.tap(find.text('手动'));
    await tester.pump();
    expect(got, FancamEditMode.manual);
  });
}
