import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/main.dart';

void main() {
  testWidgets('AppRoot boots and shows shell', (tester) async {
    await tester.pumpWidget(const AppRoot());
    await tester.pump();
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
  });
}
