import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/ui/home_shell.dart';

void main() {
  testWidgets('三个区域：首页/＋/记录', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: HomeShell(pages: const [SizedBox(), SizedBox()], onFabPressed: null, fabDestination: 0)));
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('点记录切页，选中加重', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: HomeShell(pages: const [SizedBox(), SizedBox()], onFabPressed: null, fabDestination: 0)));
    await tester.tap(find.text('记录'));
    await tester.pump();
    final recordStyle = tester.widget<Text>(find.text('记录')).style!;
    final homeStyle = tester.widget<Text>(find.text('首页')).style!;
    expect(recordStyle.fontWeight, FontWeight.w700);
    expect(homeStyle.fontWeight, FontWeight.w400);
  });
}
