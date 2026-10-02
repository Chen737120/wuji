import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wuji/data/app_repository.dart';
import 'package:wuji/data/db.dart';
import 'package:wuji/services/archive_fs.dart';
import 'package:wuji/ui/detail_page.dart';
import 'helpers/fake_saver.dart';

/// 无 IO 的文件存在性假实现。
class FakeLocator implements MediaLocator {
  FakeLocator(this.missing);
  final Set<String> missing;
  @override
  Future<bool> exists(String rel) async => !missing.contains(rel);
}

class DeletingSaver extends FakeSaver {
  DeletingSaver({required super.records, super.media});
  final deleted = <String>[];

  @override
  Future<void> deleteRecord(String id) async {
    deleted.add(id);
  }
}

void main() {
  ClassRecord seed() => ClassRecord(
        id: 'r1',
        date: '2026-09-30',
        styleName: '爵士',
        teacherName: '小鹿',
        studioName: '光影舞室',
        sessionCount: 1,
        minutesEach: 90,
        note: '发现一个宝藏老师 ✨\n今天换了小鹿老师的班，分解动作特别细。',
        createdAt: DateTime(2026, 9, 30),
        updatedAt: DateTime(2026, 9, 30),
      );

  testWidgets('renders title, meta, feelings and missing-file state',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final saver = DeletingSaver(records: [seed()], media: [
      MediaAsset(
          id: 'm1',
          classId: 'r1',
          type: 'video',
          fileName: 'media/2026-09/ok.mp4',
          sizeBytes: 1,
          createdAt: DateTime(2026, 9, 30)),
      MediaAsset(
          id: 'm2',
          classId: 'r1',
          type: 'video',
          fileName: 'media/2026-09/missing.mp4',
          sizeBytes: 1,
          createdAt: DateTime(2026, 9, 30)),
    ]);
    await tester.pumpWidget(MultiProvider(providers: [
      Provider<ClassSaver>.value(value: saver),
      Provider<MediaLocator>.value(value: FakeLocator({'media/2026-09/missing.mp4'})),
    ], child: const MaterialApp(home: DetailPage(classId: 'r1'))));
    await tester.pumpAndSettle();

    expect(find.text('发现一个宝藏老师 ✨'), findsOneWidget);
    expect(find.text('9月30日 周三 · 爵士 · 1节×90分 · 小鹿 · 光影舞室'),
        findsOneWidget);
    expect(find.text('今天换了小鹿老师的班，分解动作特别细。'), findsOneWidget);
    // 丢失态在第 2 页（PageView 惰性），滑动后断言
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('文件已丢失（可从云盘备份导入）'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('导出这一课'), findsOneWidget);
  });

  testWidgets('meta omits empty segments', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final bare = ClassRecord(
      id: 'r2',
      date: '2026-09-19',
      sessionCount: 2,
      minutesEach: 60,
      createdAt: DateTime(2026, 9, 19),
      updatedAt: DateTime(2026, 9, 19),
    );
    final saver = DeletingSaver(records: [bare]);
    await tester.pumpWidget(MultiProvider(providers: [
      Provider<ClassSaver>.value(value: saver),
      Provider<MediaLocator>.value(value: FakeLocator(const {})),
    ], child: const MaterialApp(home: DetailPage(classId: 'r2'))));
    await tester.pumpAndSettle();
    expect(find.text('9月19日 周六 · 2节×60分'), findsOneWidget);
  });

  testWidgets('delete flow confirms then calls deleteRecord and pops',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final saver = DeletingSaver(records: [seed()], media: [
      MediaAsset(
          id: 'm1',
          classId: 'r1',
          type: 'video',
          fileName: 'media/2026-09/ok.mp4',
          sizeBytes: 1,
          createdAt: DateTime(2026, 9, 30)),
      MediaAsset(
          id: 'm2',
          classId: 'r1',
          type: 'video',
          fileName: 'media/2026-09/two.mp4',
          sizeBytes: 1,
          createdAt: DateTime(2026, 9, 30)),
    ]);
    late BuildContext pushedContext;
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<ClassSaver>.value(value: saver),
        Provider<MediaLocator>.value(value: FakeLocator(const {})),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () {
                pushedContext = context;
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => DetailPage(classId: 'r1')));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // ⋯ → 删除这节课
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除这节课'));
    await tester.pumpAndSettle();

    // 确认弹窗文案含附件数与不可恢复
    expect(find.textContaining('将删除 2 个视频/图片，不可恢复'), findsOneWidget);
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();

    expect(saver.deleted, ['r1']);
    expect(find.text('open'), findsOneWidget); // 已 pop
    expect(pushedContext, isNotNull);
  });
}
