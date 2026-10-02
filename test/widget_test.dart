import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/ui/home_shell.dart';

void main() {
  testWidgets('shell boots with two pages', (tester) async {
    await tester.pumpWidget(MaterialApp(home: HomeShell(
      pages: const [SizedBox(), SizedBox()],
      onFabPressed: null,
    )));
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
  });
}
