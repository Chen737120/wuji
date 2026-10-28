import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wuji/data/app_repository.dart';
import 'package:wuji/data/db.dart';
import 'package:wuji/ui/player_page.dart';
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

String iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 按天分组组头文案（与 groupByDay 一致）
String dayHeader(DateTime d) {
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return '${d.month}月${d.day}日 ${weekdays[d.weekday - 1]}';
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
    // 2026-10-08 需求 #6：日历默认**当前月份**——种数据用当月日期验证
    final now = DateTime.now();
    final d1 = DateTime(now.year, now.month, now.day >= 2 ? now.day - 1 : 1);
    final d2 = DateTime(now.year, now.month, 1);
    final lastMonth = DateTime(now.year, now.month, 0); // 上月最后一天
    final saver = FakeSaver(records: [
      rec('r1', iso(d1), style: '爵士', teacher: '小鹿',
          note: '发现一个宝藏老师 ✨\n正文'),
      rec('r2', iso(d2), style: '韩舞', teacher: '阿哲'),
      rec('r3', iso(lastMonth), style: '爵士'),
    ]);
    await tester.pumpWidget(MultiProvider(providers: [
      Provider<ClassSaver>.value(value: saver),
    ], child: const MaterialApp(home: RecordsPage())));
    await tester.pumpAndSettle();

    expect(find.text('${now.year}年${now.month}月'), findsOneWidget); // 日历头=当前月
    // 感受完整显示一遍（2026-10-07 #6/#7：单遍、不折叠）
    expect(find.text('发现一个宝藏老师 ✨\n正文'), findsOneWidget);
    expect(find.text('${d2.month}/${d2.day} 韩舞课'), findsOneWidget);
    expect(find.text('${lastMonth.month}/${lastMonth.day} 爵士课'), findsOneWidget);
    // 胶囊标签已移除（2026-10-07 #4）
    expect(find.text('#爵士'), findsNothing);
    expect(find.byIcon(Icons.more_horiz), findsWidgets); // 右下角"…"按钮
    expect(find.text(dayHeader(d1)), findsOneWidget); // 按天分组组头
    expect(find.text(dayHeader(lastMonth)), findsOneWidget);
    // 当前月日历格子可命中（默认页即当前月）
    expect(
        find.byKey(ValueKey('day-${now.year}-${now.month}-${d1.day}')),
        findsOneWidget);
  });

  testWidgets('tapping a calendar day filters the stream', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final d1 = DateTime(now.year, now.month, now.day >= 2 ? now.day - 1 : 1);
    final d2 = DateTime(now.year, now.month, 1);
    final saver = FakeSaver(records: [
      rec('r1', iso(d1), style: '爵士', note: '标题一'),
      rec('r2', iso(d2), style: '韩舞', note: '标题二'),
    ]);
    await tester.pumpWidget(MultiProvider(providers: [
      Provider<ClassSaver>.value(value: saver),
    ], child: const MaterialApp(home: RecordsPage())));
    await tester.pumpAndSettle();

    expect(find.text('标题一'), findsOneWidget);
    expect(find.text('标题二'), findsOneWidget);

    // 点日历上 d1 那天；按 key 精确命中当前月页
    await tester
        .tap(find.byKey(ValueKey('day-${now.year}-${now.month}-${d1.day}')));
    await tester.pumpAndSettle();

    expect(find.text('${d1.month}月${d1.day}日 · 1 节课'), findsOneWidget);
    expect(find.text('标题一'), findsOneWidget);
    expect(find.text('标题二'), findsNothing);

    // 清除筛选
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('标题二'), findsOneWidget);
  });

  testWidgets('视频解析失败：立即进播放页、页内提示丢失且无播放器（P1-13 + 反馈 #1）',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final d1 = DateTime(now.year, now.month, now.day);
    final saver = FakeSaver(
      records: [rec('r1', iso(d1), style: '爵士')],
      media: [
        MediaAsset(
          id: 'm1',
          classId: 'r1',
          type: 'video',
          fileName: 'media/2026-10/u1.mp4',
          sizeBytes: 4,
          createdAt: DateTime(2026, 10, 27),
        ),
      ],
    );
    // 无 MediaPathResolver → resolve 返回 null（相对路径不得回退给播放器）
    await tester.pumpWidget(MultiProvider(providers: [
      Provider<ClassSaver>.value(value: saver),
    ], child: const MaterialApp(home: RecordsPage())));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();

    // 反馈 #1：点击立即进页（解析挪到页内）；P1-13：解析失败只在页内提示，
    // 绝不把相对路径交给播放器（不创建 VideoPlayerController → 无加载/错误外框）
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.text('视频文件已丢失，可从备份导入恢复'), findsOneWidget);
  });
}
