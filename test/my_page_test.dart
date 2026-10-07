import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wuji/data/app_repository.dart';
import 'package:wuji/data/db.dart';
import 'package:wuji/theme.dart';
import 'package:wuji/ui/my_page.dart';
import 'helpers/fake_saver.dart';

ClassRecord rec(String id, String date) => ClassRecord(
      id: id,
      date: date,
      sessionCount: 1,
      minutesEach: 90,
      createdAt: DateTime.parse(date),
      updatedAt: DateTime.parse(date),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows usage summary, sections and footer', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final saver = FakeSaver(records: [rec('a', '2026-09-28'), rec('b', '2026-09-20')], media: [
      MediaAsset(
          id: 'm1', classId: 'a', type: 'video', fileName: 'x.mp4', sizeBytes: 1366, createdAt: DateTime(2026, 9, 28)),
      MediaAsset(
          id: 'm2', classId: 'a', type: 'video', fileName: 'y.mp4', sizeBytes: 1365, createdAt: DateTime(2026, 9, 28)),
      MediaAsset(
          id: 'm3', classId: 'b', type: 'image', fileName: 'z.jpg', sizeBytes: 1365, createdAt: DateTime(2026, 9, 20)),
    ]);
    final theme = ThemeController();
    await tester.pumpWidget(MultiProvider(providers: [
      Provider<ClassSaver>.value(value: saver),
      ChangeNotifierProvider<ThemeController>.value(value: theme),
    ], child: const MaterialApp(home: MyPage())));
    await tester.pumpAndSettle();

    expect(find.text('我的'), findsOneWidget);
    expect(find.text('2 节课 · 3 个附件 · 约 4 KB（视频占大头）'), findsOneWidget);
    expect(find.text('导出全部记录'), findsOneWidget);
    expect(find.text('按时间段导出'), findsOneWidget);
    expect(find.text('导入备份'), findsOneWidget);
    expect(find.text('舞种管理'), findsOneWidget);
    expect(find.text('老师管理'), findsOneWidget);
    expect(find.text('舞室管理'), findsOneWidget);
    expect(find.text('关于舞记'), findsOneWidget);
    expect(find.text('数据只存在这台手机上 · 导出即备份'), findsOneWidget);
  });

  testWidgets('accent picker switches global preset', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final theme = ThemeController();
    await tester.pumpWidget(MultiProvider(providers: [
      Provider<ClassSaver>.value(value: FakeSaver()),
      ChangeNotifierProvider<ThemeController>.value(value: theme),
    ], child: const MaterialApp(home: MyPage())));
    await tester.pumpAndSettle();

    await tester.tap(find.text('宝蓝'));
    await tester.pumpAndSettle();
    expect(theme.accentPreset, AccentPreset.blue);
  });

  test('humanBytes formats KB/MB/GB', () {
    expect(humanBytes(512), '512 B');
    expect(humanBytes(4 * 1024), '约 4 KB');
    expect(humanBytes(12 * 1024 * 1024), '约 12 MB');
    expect(humanBytes(3 * 1024 * 1024 * 1024), '约 3.0 GB');
  });
}
