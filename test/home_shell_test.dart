import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wuji/ui/home_shell.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget shell() => MaterialApp(
      home: HomeShell(
          pages: const [SizedBox(), SizedBox(), SizedBox()],
          onFabPressed: null));

  testWidgets('三个区域：首页/剪辑/记录（图标＋文字）', (tester) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('剪辑'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    expect(find.byIcon(Icons.content_cut), findsOneWidget);
    expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('点记录切页，选中加重', (tester) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    final recordStyle = tester.widget<Text>(find.text('记录')).style!;
    final homeStyle = tester.widget<Text>(find.text('首页')).style!;
    expect(recordStyle.fontWeight, FontWeight.w700);
    expect(homeStyle.fontWeight, FontWeight.w400);
  });
}
