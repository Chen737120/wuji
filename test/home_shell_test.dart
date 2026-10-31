import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wuji/ui/home_shell.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget shell() => MaterialApp(
      home: HomeShell(
          pages: const [SizedBox(), SizedBox(), SizedBox(), SizedBox()],
          onFabPressed: null));

  testWidgets('四个区域：记录/剪辑/统计/我的（图标＋文字；2026-10-31 T2 四 tab）',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('剪辑'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
    expect(find.byIcon(Icons.content_cut), findsOneWidget);
    expect(find.byIcon(Icons.pie_chart_outline), findsOneWidget);
    expect(find.byIcon(Icons.person_outlined), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('点统计切页，选中加重', (tester) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();
    await tester.tap(find.text('统计'));
    await tester.pumpAndSettle();
    final statStyle = tester.widget<Text>(find.text('统计')).style!;
    final recordStyle = tester.widget<Text>(find.text('记录')).style!;
    expect(statStyle.fontWeight, FontWeight.w700);
    expect(recordStyle.fontWeight, FontWeight.w400);
  });

  testWidgets('切 tab 时选中图标 bump（ScaleTransition 1→1.14→1）',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();
    ScaleTransition cutIconScale() => tester.widget<ScaleTransition>(
        find.byWidgetPredicate((w) =>
            w is ScaleTransition &&
            w.child is Icon &&
            (w.child as Icon).icon == Icons.content_cut));
    await tester.tap(find.text('剪辑'));
    await tester.pump(); // 激活动画 ticker
    await tester.pump(const Duration(milliseconds: 100)); // bump 进行中
    expect(cutIconScale().scale.value, greaterThan(1.0));
    await tester.pumpAndSettle(); // bump 收尾回到 1.0
    expect(cutIconScale().scale.value, 1.0);
  });
}
