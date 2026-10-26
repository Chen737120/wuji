// test/save_to_gallery_button_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/ui/widgets/save_to_gallery_button.dart';

void main() {
  Future<void> pump(WidgetTester tester, GallerySaver saver) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Center(
              child: SaveToGalleryButton(path: '/a.mp4', saver: saver))),
    ));
  }

  testWidgets('点击调用 saver 且参数为 path，成功提示', (tester) async {
    final calls = <String>[];
    await pump(tester, (p) async => calls.add(p));
    await tester.tap(find.byIcon(Icons.download));
    await tester.pump();
    expect(calls, ['/a.mp4']);
    expect(find.text('已保存到相册'), findsOneWidget);
  });

  testWidgets('saver 抛异常提示保存失败', (tester) async {
    await pump(tester, (p) async => throw Exception('boom'));
    await tester.tap(find.byIcon(Icons.download));
    await tester.pump();
    expect(find.textContaining('保存失败'), findsOneWidget);
  });

  testWidgets('saving 期间图标转圈且重复点击不二次调用', (tester) async {
    final c = Completer<void>();
    var calls = 0;
    await pump(tester, (p) async {
      calls++;
      await c.future;
    });
    await tester.tap(find.byIcon(Icons.download));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(IconButton), warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);
    c.complete();
  });

  testWidgets('完成后恢复下载图标且可再次保存', (tester) async {
    var calls = 0;
    await pump(tester, (p) async => calls++);
    await tester.tap(find.byIcon(Icons.download));
    await tester.pumpAndSettle(const Duration(seconds: 5)); // 等 SnackBar 消失
    expect(find.byIcon(Icons.download), findsOneWidget);
    await tester.tap(find.byIcon(Icons.download));
    await tester.pump();
    expect(calls, 2);
  });
}
