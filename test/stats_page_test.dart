import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wuji/data/app_repository.dart';
import 'package:wuji/data/db.dart';
import 'package:wuji/theme.dart';
import 'package:wuji/ui/stats_page.dart';
import 'helpers/fake_saver.dart';

ClassRecord rec(String id, String date, int sessions, int minutesEach,
    {String? style, String? teacher}) {
  return ClassRecord(
    id: id,
    date: date,
    styleName: style,
    teacherName: teacher,
    sessionCount: sessions,
    minutesEach: minutesEach,
    createdAt: DateTime.parse(date),
    updatedAt: DateTime.parse(date),
  );
}

Widget host(ClassSaver saver) => MultiProvider(
      providers: [
        Provider<ClassSaver>.value(value: saver),
        ChangeNotifierProvider<ThemeController>.value(value: ThemeController()),
      ],
      child: const MaterialApp(home: StatsPage()),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows totals, labels and charts with seeded data',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final saver = FakeSaver(
      records: [
        rec('a', '2026-09-28', 2, 90, style: '爵士', teacher: '小鹿'),
        rec('b', '2026-09-20', 1, 60, style: '韩舞'),
      ],
      media: [
        MediaAsset(
            id: 'm1',
            classId: 'a',
            type: 'video',
            fileName: 'x.mp4',
            sizeBytes: 1,
            createdAt: DateTime(2026, 9, 28)),
        MediaAsset(
            id: 'm2',
            classId: 'a',
            type: 'image',
            fileName: 'y.jpg',
            sizeBytes: 1,
            createdAt: DateTime(2026, 9, 28)),
      ],
    );
    await tester.pumpWidget(host(saver));
    await tester.pumpAndSettle();

    expect(find.text('跳舞节数'), findsOneWidget);
    expect(find.text('跳舞时长'), findsOneWidget);
    expect(find.text('跳舞天数'), findsOneWidget);
    expect(find.text('视频·图片'), findsOneWidget);
    expect(find.text('3'), findsWidgets); // 节数（趋势柱上无文字，卡片区 1 处）
    expect(find.text('240'), findsOneWidget); // 120+120 分钟
    expect(find.text('2'), findsWidgets); // 天数
    expect(find.text('跳舞趋势（分钟）'), findsOneWidget);
    expect(find.text('舞种分布'), findsOneWidget);
    expect(find.text('老师统计'), findsOneWidget);
    expect(find.text('按天'), findsOneWidget);
    expect(find.text('按月'), findsOneWidget);
  });

  testWidgets('empty state still shows zero charts with a hint',
      (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(FakeSaver()));
    await tester.pumpAndSettle();

    expect(find.text('还没有课堂记录，点下方 ＋ 记录第一节课'), findsOneWidget);
    expect(find.text('跳舞趋势（分钟）'), findsOneWidget);
    expect(find.text('舞种分布'), findsOneWidget);
    expect(find.text('老师统计'), findsOneWidget);
    expect(find.text('舞室统计'), findsOneWidget);
  });

  testWidgets('last-30-days chip excludes older records', (tester) async {
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    String f(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final saver = FakeSaver(records: [
      rec('a', f(now.subtract(const Duration(days: 1))), 1, 60),
      rec('b', f(now.subtract(const Duration(days: 31))), 2, 90),
    ]);
    await tester.pumpWidget(host(saver));
    await tester.pumpAndSettle();

    // 默认近1月：只剩 1 节、60 分钟
    expect(find.text('60'), findsOneWidget);
    // 切到全部：3 节
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsWidgets);
    expect(find.text('240'), findsOneWidget); // 时长 60 + 2节×90
    // 切回近1月
    await tester.tap(find.text('近1月'));
    await tester.pumpAndSettle();
    expect(find.text('60'), findsOneWidget);
  });
}
