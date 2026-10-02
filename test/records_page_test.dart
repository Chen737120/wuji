import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wuji/data/app_repository.dart';
import 'package:wuji/data/db.dart';
import 'package:wuji/ui/records_page.dart';
import 'helpers/fake_saver.dart';

ClassRecord rec(String id, String date,
    {String? style, String? teacher, String? studio, String? note, int sessions = 1}) {
  return ClassRecord(
    id: id,
    date: date,
    styleName: style,
    teacherName: teacher,
    studioName: studio,
    sessionCount: sessions,
    minutesEach: 90,
    note: note,
    createdAt: DateTime.parse(date),
    updatedAt: DateTime.parse(date),
  );
}

void main() {
  test('recordTitle prefers first note line', () {
    final r = rec('a', '2026-09-30',
        style: '爵士', note: '发现一个宝藏老师 ✨\n正文第二行');
    expect(recordTitle(r), '发现一个宝藏老师 ✨');
  });

  test('recordTitle falls back to date + style', () {
    expect(recordTitle(rec('a', '2026-09-19', style: '爵士')), '9/19 爵士课');
    expect(recordTitle(rec('b', '2026-09-19')), '9/19 舞蹈课');
  });

  test('groupByMonth sorts months descending', () {
    final groups = groupByMonth([
      rec('a', '2026-08-21'),
      rec('b', '2026-09-30'),
      rec('c', '2026-09-19'),
    ]);
    expect(groups.map((g) => g.key).toList(), ['2026年9月', '2026年8月']);
    expect(
        groups.firstWhere((g) => g.key == '2026年9月').value.map((e) => e.id),
        ['b', 'c']);
  });

  testWidgets('renders month groups, card titles and calendar dots',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 2000); // 放大视口，全量可见
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final saver = FakeSaver(records: [
      rec('r1', '2026-09-30', style: '爵士', teacher: '小鹿',
          note: '发现一个宝藏老师 ✨\n正文'),
      rec('r2', '2026-09-24', style: '韩舞', teacher: '阿哲'),
      rec('r3', '2026-08-21', style: '爵士'),
    ]);
    await tester.pumpWidget(MultiProvider(providers: [
      Provider<ClassSaver>.value(value: saver),
    ], child: const MaterialApp(home: RecordsPage())));
    await tester.pumpAndSettle();

    expect(find.text('2026年9月'), findsWidgets); // 日历头＋分组头
    expect(find.text('发现一个宝藏老师 ✨'), findsOneWidget);
    expect(find.text('9/24 韩舞课'), findsOneWidget);
    expect(find.text('8/21 爵士课'), findsOneWidget);
    expect(find.text('爵士 · 1节×90分 · 小鹿'), findsOneWidget);
    expect(find.text('2026年8月'), findsOneWidget);
  });

  testWidgets('tapping a calendar day filters the stream', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final saver = FakeSaver(records: [
      rec('r1', '2026-09-30', style: '爵士', note: '标题一'),
      rec('r2', '2026-09-24', style: '韩舞', note: '标题二'),
    ]);
    await tester.pumpWidget(MultiProvider(providers: [
      Provider<ClassSaver>.value(value: saver),
    ], child: const MaterialApp(home: RecordsPage())));
    await tester.pumpAndSettle();

    expect(find.text('标题一'), findsOneWidget);
    expect(find.text('标题二'), findsOneWidget);

    // 点日历上的 30 号（2026年9月30日是周三）
    await tester.tap(find.text('30'));
    await tester.pumpAndSettle();

    expect(find.text('9月30日 · 1 节课'), findsOneWidget);
    expect(find.text('标题一'), findsOneWidget);
    expect(find.text('标题二'), findsNothing);

    // 清除筛选
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('标题二'), findsOneWidget);
  });
}
