import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wuji/data/db.dart';
import 'package:wuji/data/taxonomy_repo.dart';
import 'package:wuji/models/models.dart';
import 'package:wuji/ui/sheets/duration_sheet.dart';
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
}
