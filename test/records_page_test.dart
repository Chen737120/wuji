import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wuji/data/app_repository.dart';
import 'package:wuji/data/db.dart';
import 'package:wuji/services/archive_fs.dart' show MediaPathResolver;
import 'package:wuji/ui/player_page.dart';
import 'package:wuji/ui/records_page.dart';
import 'package:wuji/ui/widgets/pressable_scale.dart';
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

/// 按天分组组头（T5 v1 形态：日期 14/700 与「· 星期」11/faint 拆成两个 Text）
const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

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

  test('groupByDay splits date label and weekday (T5 v1)', () {
    final groups = groupByDay([
      rec('a', '2026-10-31'),
      rec('b', '2026-10-29'),
    ]);
    expect(groups, hasLength(2));
    expect(groups.first.dateLabel, '10月31日');
    expect(groups.first.weekday, '周六');
    expect(groups.last.dateLabel, '10月29日');
    expect(groups.last.weekday, '周四');
    expect(groups.first.records.single.id, 'a');
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

    // T5 子项 1：Large Title「记录」＋搜索钮（不再有页头 16 号「首页」）
    expect(find.text('记录'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.search_off), findsNothing);
    expect(
        tester
            .widget<Text>(find.text('记录'))
            .style!
            .fontSize,
        28);
    expect(find.text('收起日历 ⌃'), findsNothing); // 文字钮已移除

    // 感受完整显示一遍（2026-10-07 #6/#7：单遍、不折叠）
    expect(find.text('发现一个宝藏老师 ✨\n正文'), findsOneWidget);
    expect(find.text('${d2.month}/${d2.day} 韩舞课'), findsOneWidget);
    expect(find.text('${lastMonth.month}/${lastMonth.day} 爵士课'), findsOneWidget);
    // 胶囊标签已移除（2026-10-07 #4）
    expect(find.text('#爵士'), findsNothing);
    expect(find.byIcon(Icons.more_horiz), findsWidgets); // 右下角"…"按钮
    // T5 子项 4：日期头拆为 14/700 日期＋11/faint「· 星期」
    expect(
        find.text('${d1.month}月${d1.day}日'), findsOneWidget);
    expect(find.text('· ${weekdays[d1.weekday - 1]}'), findsOneWidget);
    expect(
        find.text('${lastMonth.month}月${lastMonth.day}日'), findsOneWidget);
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

  testWidgets('T5：视频时长胶囊＋日历 chevron 收起/展开＋媒体格按压',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 890); // 真机视口（附A）
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final d1 = DateTime(now.year, now.month, 1);
    final saver = FakeSaver(
      records: [rec('r1', iso(d1), style: '爵士', note: '标题一')],
      media: [
        MediaAsset(
          id: 'm1',
          classId: 'r1',
          type: 'video',
          fileName: 'media/2026-10/u1.mp4',
          thumbName: 'media/2026-10/t.jpg',
          durationSec: 134,
          sizeBytes: 4,
          createdAt: DateTime(2026, 10, 31),
        ),
      ],
    );
    await tester.pumpWidget(MultiProvider(providers: [
      Provider<ClassSaver>.value(value: saver),
      // resolver 返回假绝对路径 → 有封面叠加层（Image 失败走占位不影响断言）
      Provider<MediaPathResolver>.value(
          value: _FixedResolver('C:/fake/t.jpg')),
    ], child: const MaterialApp(home: RecordsPage())));
    await tester.pumpAndSettle();

    // 时长胶囊：134s → 02:14（durationSec 为 null 时不显示，见上一用例）
    expect(find.text('02:14'), findsOneWidget);
    // 媒体格包 PressableScale
    expect(find.byType(PressableScale), findsWidgets);

    // 收起日历：点卡头 chevron 圆钮 → 周条出现
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.calendar_month), findsOneWidget); // 周条展开钮

    // 再展开日历
    await tester.tap(find.byIcon(Icons.calendar_month));
    await tester.pumpAndSettle();
    expect(
        find.byKey(ValueKey('day-${now.year}-${now.month}-1')),
        findsOneWidget);
  });
}

class _FixedResolver implements MediaPathResolver {
  _FixedResolver(this.path);
  final String path;

  @override
  Future<String?> toAbsolutePath(String rel, {bool paced = false}) async =>
      path;
}
