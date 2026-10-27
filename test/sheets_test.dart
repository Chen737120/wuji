import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wuji/data/db.dart';
import 'package:wuji/data/taxonomy_repo.dart';
import 'package:wuji/models/models.dart';
import 'package:wuji/ui/sheets/duration_sheet.dart';
import 'package:wuji/ui/sheets/date_range_sheet.dart';
import 'package:wuji/ui/sheets/date_sheet.dart';
import 'package:wuji/ui/sheets/style_sheet.dart';
import 'package:wuji/ui/sheets/text_sheet.dart';

void main() {
  late AppDatabase db;
  late TaxonomyRepo repo;
  setUp(() {
    db = appDatabaseForTest();
    repo = TaxonomyRepo(db);
  });
  tearDown(() => db.close());

  Widget host(Widget child) => MultiProvider(providers: [
        Provider<TaxonomyRepo>.value(value: repo),
      ], child: MaterialApp(home: Scaffold(body: child)));

  testWidgets('style sheet shows 19 presets + 自定义, custom adds and returns',
      (tester) async {
    TaxonomyItem? picked;
    await tester.pumpWidget(host(Builder(builder: (context) => Center(
      child: TextButton(
        onPressed: () async => picked = await showStyleSheet(context, repo),
        child: const Text('open'),
      ),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('爵士'), findsOneWidget);
    expect(find.text('芭蕾'), findsOneWidget);
    expect(find.text('自定义'), findsOneWidget);
    // 预设网格 19 个 tile
    for (final name in TaxonomyRepo.builtinStyles) {
      expect(find.text(name), findsOneWidget, reason: name);
    }

    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '国风爵士');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.name, '国风爵士');
  });

  testWidgets('style sheet tap preset returns it', (tester) async {
    TaxonomyItem? picked;
    await tester.pumpWidget(host(Builder(builder: (context) => Center(
      child: TextButton(
        onPressed: () async => picked = await showStyleSheet(context, repo),
        child: const Text('open'),
      ),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('K-Pop'));
    await tester.pumpAndSettle();
    expect(picked!.name, 'K-Pop');
    expect(picked!.isBuiltin, isTrue);
  });

  testWidgets('duration sheet returns sessions × minutes selection',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    (int, int)? picked;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: Builder(builder: (context) => TextButton(
        onPressed: () async {
          picked = await showDurationSheet(context,
              sessions: 1, minutesEach: 90);
        },
        child: const Text('open'),
      )),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('课程时长'), findsOneWidget);
    expect(find.text('上课节数'), findsOneWidget);
    expect(find.text('每节时长'), findsOneWidget);
    // 时长从 50 起步、步进 5（抽查 50/55/60）
    expect(find.text('50 分钟'), findsOneWidget);
    expect(find.text('55 分钟'), findsOneWidget);
    expect(find.text('60 分钟'), findsOneWidget);

    await tester.tap(find.text('2 节'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('50 分钟'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认时长'));
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.$1, 2);
    expect(picked!.$2, 50);
  });

  testWidgets('text sheet shows recent chips and tap chip returns',
      (tester) async {
    await repo.touchByName(TaxonomyKind.teacher, '小鹿');
    TaxonomyItem? picked;
    await tester.pumpWidget(host(Builder(builder: (context) => Center(
      child: TextButton(
        onPressed: () async {
          picked = await showTextSheet(context, repo, TaxonomyKind.teacher,
              title: '授课老师', hint: '老师名字');
        },
        child: const Text('open'),
      ),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('授课老师'), findsOneWidget);
    expect(find.text('最近输入'), findsOneWidget);
    expect(find.text('小鹿'), findsOneWidget);
    await tester.tap(find.text('小鹿'));
    await tester.pumpAndSettle();
    expect(picked!.name, '小鹿');
  });

  testWidgets('text sheet caps recent chips: teacher 10, studio 6',
      (tester) async {
    var tick = 0;
    final clockRepo = TaxonomyRepo(db,
        clock: () => DateTime(2026, 1, 1).add(Duration(minutes: tick++)));
    for (var i = 1; i <= 13; i++) {
      await clockRepo.touchByName(
          TaxonomyKind.teacher, '老师${i.toString().padLeft(2, '0')}');
    }
    for (var i = 1; i <= 8; i++) {
      await clockRepo.touchByName(
          TaxonomyKind.studio, '舞室${i.toString().padLeft(2, '0')}');
    }

    var kind = TaxonomyKind.teacher;
    await tester.pumpWidget(host(Builder(builder: (context) => Center(
      child: TextButton(
        onPressed: () async {
          await showTextSheet(context, clockRepo, kind,
              title: '输入', hint: '输入');
        },
        child: const Text('open'),
      ),
    ))));

    // 老师：只出最近 10 个（老师04..老师13），更早的不出现
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ActionChip), findsNWidgets(10));
    expect(find.text('老师13'), findsOneWidget);
    expect(find.text('老师04'), findsOneWidget);
    expect(find.text('老师03'), findsNothing);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // 舞室：只出最近 6 个（舞室03..舞室08）
    kind = TaxonomyKind.studio;
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ActionChip), findsNWidgets(6));
    expect(find.text('舞室08'), findsOneWidget);
    expect(find.text('舞室03'), findsOneWidget);
    expect(find.text('舞室02'), findsNothing);
  });

  group('日期弹层（P3 补强）', () {
    testWidgets('区间弹层：先点晚再点早自动互换', (tester) async {
      tester.view.physicalSize = const Size(420, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      final month = DateTime(now.year, now.month);
      (DateTime, DateTime)? picked;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await showDateRangeSheet(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('${month.year}年${month.month}月'), findsOneWidget);

      await tester.tap(find.text('20'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10')); // 早于开始 → 应与开始互换
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(picked, isNotNull);
      expect(picked!.$1, DateTime(month.year, month.month, 10));
      expect(picked!.$2, DateTime(month.year, month.month, 20));
    });

    testWidgets('区间弹层：同日区间可提交', (tester) async {
      tester.view.physicalSize = const Size(420, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      (DateTime, DateTime)? picked;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await showDateRangeSheet(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // 当月 15 日点两次：第一次开始、第二次结束
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(picked, isNotNull);
      expect(picked!.$1, picked!.$2, reason: '同日区间应为同一天');
      expect(picked!.$1.day, 15);
    });

    testWidgets('区间弹层：跨年区间原样回传', (tester) async {
      tester.view.physicalSize = const Size(420, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      (DateTime, DateTime)? picked;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await showDateRangeSheet(context,
                      initialStart: DateTime(2025, 12, 20),
                      initialEnd: DateTime(2026, 1, 5));
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // 锚定开始月（2025年12月），结束跨到下一年
      expect(find.text('2025年12月'), findsOneWidget);
      expect(find.text('开始 12月20日'), findsOneWidget);
      expect(find.text('结束 1月5日'), findsOneWidget);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(picked!.$1, DateTime(2025, 12, 20));
      expect(picked!.$2, DateTime(2026, 1, 5));
    });

    testWidgets('日期弹层：初始日期越界时「确定」返回 null', (tester) async {
      tester.view.physicalSize = const Size(420, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      DateTime? picked;
      var closed = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await showDateSheet(context,
                      initial: DateTime(1990, 1, 1),
                      firstDate: DateTime(2000, 1, 1));
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(picked, isNull, reason: '初始越界时确定不得返回非法日期');
    });

    testWidgets('日期弹层：月份翻页在边界禁用', (tester) async {
      tester.view.physicalSize = const Size(420, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDateSheet(context,
                    initial: DateTime(2026, 10, 15),
                    firstDate: DateTime(2026, 10, 1),
                    lastDate: DateTime(2026, 12, 31)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      IconButton chevron(IconData icon) => tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, icon));
      expect(find.text('2026年10月'), findsOneWidget);
      expect(chevron(Icons.chevron_left).onPressed, isNull,
          reason: '已到 firstDate 月份，不能再往前');
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.text('2026年11月'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.text('2026年12月'), findsOneWidget);
      expect(chevron(Icons.chevron_right).onPressed, isNull,
          reason: '已到 lastDate 月份，不能再往后');
    });
  });
}
