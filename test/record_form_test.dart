import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wuji/data/app_repository.dart';
import 'package:wuji/data/db.dart';
import 'package:wuji/data/taxonomy_repo.dart';
import 'package:wuji/services/media_importer.dart';
import 'package:wuji/ui/record_form_page.dart';

class FakeImporter implements MediaImporter {
  FakeImporter(this.files);
  final List<PickedMedia> files;
  @override
  Future<List<PickedMedia>> pick(BuildContext context, {int max = 30}) async =>
      files;
}

/// 无 IO 的表单测试假仓库：widget 测试跑在 FakeAsync 区，
/// 真实 drift/文件 IO 在该区会非确定性挂死（见台账 T8 裁定）；
/// 保存正确性由 save_flow_test（常规区）覆盖，这里只测表单行为。
class FakeFormRepo implements ClassSaver {
  FakeFormRepo(this.db);

  @override
  final AppDatabase db;
  final drafts = <ClassDraft>[];
  List<MediaAsset> mediaRows = const [];
  final Completer<void> gate = Completer<void>(); // 控制保存完成时机

  @override
  Future<void> saveDraft(ClassDraft d) async {
    drafts.add(d);
    return gate.future;
  }

  @override
  Future<List<MediaAsset>> mediaOf(String classId) async => mediaRows;
}

void main() {
  late AppDatabase db;
  late FakeFormRepo repo;

  setUp(() {
    db = appDatabaseForTest();
    repo = FakeFormRepo(db);
  });
  tearDown(() => db.close());

  Widget host(Widget child) => MultiProvider(providers: [
        Provider<ClassSaver>.value(value: repo),
      ], child: MaterialApp(home: child));

  PickedMedia pm(String path, {bool video = true, int size = 10}) =>
      PickedMedia(
        path: path,
        ext: video ? 'mp4' : 'jpg',
        isVideo: video,
        sizeBytes: size,
      );

  testWidgets('picked files are passed to the saver with form fields',
      (tester) async {
    await tester.pumpWidget(host(RecordFormPage(
      importer: FakeImporter([pm('/x/a.mp4'), pm('/x/b.mp4')]),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('视频 / 图片'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_arrow), findsNWidgets(2));

    await tester.enterText(find.byType(TextField).last, '今天很棒');
    repo.gate.complete();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(repo.drafts, hasLength(1));
    final d = repo.drafts.single;
    expect(d.record.note, '今天很棒');
    expect(d.newMedia, hasLength(2));
    expect(d.record.sessionCount, 1);
    expect(d.record.minutesEach, 90);
  });

  testWidgets('edit mode prefills existing values and media', (tester) async {
    final existing = ClassRecord(
      id: 'r1',
      date: '2026-09-30',
      styleName: '爵士',
      teacherName: '小鹿',
      sessionCount: 2,
      minutesEach: 90,
      note: '旧标题',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    repo.mediaRows = [
      MediaAsset(
        id: 'm1',
        classId: 'r1',
        type: 'video',
        fileName: 'media/2026-09/abc.mp4',
        sizeBytes: 1,
        createdAt: DateTime.now(),
      ),
    ];

    await tester.pumpWidget(host(RecordFormPage(existing: existing)));
    await tester.pumpAndSettle();

    expect(find.text('爵士'), findsOneWidget);
    expect(find.text('小鹿'), findsOneWidget);
    expect(find.text('2节×90分'), findsOneWidget);
    expect(find.text('abc.mp4'), findsOneWidget);
    expect(find.text('编辑这节课'), findsOneWidget);
  });

  testWidgets('save button disables and shows 保存中 until save completes',
      (tester) async {
    // 用真实 push 结构，保存完成后 pop 回来（根路由上 pop 是 no-op）；
    // Provider 必须包在 MaterialApp 外层，push 进来的路由才找得到 ClassSaver。
    await tester.pumpWidget(MultiProvider(
      providers: [Provider<ClassSaver>.value(value: repo)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RecordFormPage(
                    importer: FakeImporter([pm('/x/big.mp4')]),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('视频 / 图片'));
    await tester.pumpAndSettle();

    expect(find.text('保存中…'), findsNothing);
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('保存中…'), findsOneWidget);
    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '保存中…'));
    expect(button.onPressed, isNull);

    await tester.runAsync(() async {
      repo.gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('保存中…'), findsNothing);
    expect(find.text('open'), findsOneWidget); // 已 pop 回来
  });
}
