import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wuji/data/app_repository.dart';
import 'package:wuji/data/db.dart';
import 'package:wuji/services/archive_fs.dart' show MediaPathResolver;
import 'package:wuji/services/media_importer.dart';
import 'package:wuji/ui/record_form_page.dart';

/// 假解析器：表单里旧附件封面/预览需要它（P1-13 后无 resolver 时
/// resolve 返回 null，页面按「文件已丢失」处理）。
class _FakeResolver implements MediaPathResolver {
  @override
  Future<String?> toAbsolutePath(String rel, {bool paced = false}) async =>
      '/abs/$rel';
}

class FakeImporter implements MediaImporter {
  FakeImporter(this.files);
  final List<PickedMedia> files;
  @override
  Future<PickResult> pick(BuildContext context, {int max = 30}) async =>
      PickResult(picked: files);
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
  bool failNextSave = false; // 模拟保存失败（异常路径用）

  @override
  Future<void> saveDraft(ClassDraft d) async {
    drafts.add(d);
    if (failNextSave) throw StateError('disk full');
    return gate.future;
  }

  @override
  Future<List<MediaAsset>> mediaOf(String classId) async => mediaRows;

  @override
  Future<Map<String, List<MediaAsset>>> mediaByClass() async => const {};

  @override
  Future<List<ClassRecord>> allRecords() async => const [];

  @override
  Future<bool> needsSpaceWarningFor(inputs) async => false;

  @override
  Future<void> deleteRecord(String id) async {}
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
        Provider<MediaPathResolver>.value(value: _FakeResolver()),
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
    expect(d.record.minutesEach, 60);
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

  testWidgets('picked image uses itself as tile cover', (tester) async {
    // 2026-10-24 需求：表单条目显示封面——新选图片直接用原图当封面
    await tester.pumpWidget(host(RecordFormPage(
      importer: FakeImporter([pm('/x/b.jpg', video: false)]),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('视频 / 图片'));
    await tester.pumpAndSettle();
    // Image.file 已构建（测试里文件不存在时 errorBuilder 兜底成图标，
    // 但 Image widget 本身在树中）
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('edit mode resolves existing thumb into tile cover image', (tester) async {
    final existing = ClassRecord(
      id: 'r2',
      date: '2026-09-30',
      sessionCount: 1,
      minutesEach: 60,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    repo.mediaRows = [
      MediaAsset(
        id: 'm2',
        classId: 'r2',
        type: 'video',
        fileName: 'media/2026-09/def.mp4',
        thumbName: 'thumbs/t.jpg',
        sizeBytes: 1,
        createdAt: DateTime.now(),
      ),
    ];
    await tester.pumpWidget(host(RecordFormPage(existing: existing)));
    await tester.pumpAndSettle();
    // resolver 给出绝对路径（/abs/…）→ Image.file 构建（errorBuilder 兜底）
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('def.mp4'), findsOneWidget);
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

  testWidgets('同一帧内连点两次保存只调用一次 saveDraft（P1-5 防重入）',
      (tester) async {
    await tester.pumpWidget(host(RecordFormPage(
      importer: FakeImporter([pm('/x/a.mp4')]),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('视频 / 图片'));
    await tester.pumpAndSettle();

    // 不 pump：第二次点击时按钮仍可点（重启前旧实现会并发进入 _save）
    await tester.tap(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('保存中…'), findsOneWidget);

    await tester.runAsync(() async {
      repo.gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(repo.drafts, hasLength(1), reason: '双击不得并发保存两份媒体');
  });

  testWidgets('保存失败后 _saving 复位，按钮可再次点击（P1-5）', (tester) async {
    repo.failNextSave = true;
    await tester.pumpWidget(host(RecordFormPage(
      importer: FakeImporter([pm('/x/a.mp4')]),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('视频 / 图片'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('保存中…'), findsNothing);
    final button =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存'));
    expect(button.onPressed, isNotNull, reason: '失败后必须能再次保存');
    expect(find.text('保存失败，请重试'), findsOneWidget);
  });

  test('shouldRetryCover：失败过的键不再重试，清除后可重试（P2-26）', () {
    final failed = <String>{'/x/a.mp4'};
    expect(shouldRetryCover('/x/a.mp4', failed), isFalse);
    expect(shouldRetryCover('/x/b.mp4', failed), isTrue);
    failed.remove('/x/a.mp4'); // 用户重选同一文件时的动作
    expect(shouldRetryCover('/x/a.mp4', failed), isTrue);
  });

  testWidgets('保存中关闭按钮禁用（P2-24）', (tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [Provider<ClassSaver>.value(value: repo)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RecordFormPage()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('保存中…'), findsOneWidget);
    final closeBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.close).first);
    expect(closeBtn.onPressed, isNull, reason: '保存中不得退出，否则本次保存丢失');

    await tester.runAsync(() async {
      repo.gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  });

  testWidgets('removeMediaIds 传快照：保存中再删附件不影响本次保存（P2-27）',
      (tester) async {
    final now = DateTime.now();
    final existing = ClassRecord(
      id: 'r3',
      date: '2026-10-01',
      sessionCount: 1,
      minutesEach: 60,
      createdAt: now,
      updatedAt: now,
    );
    repo.mediaRows = [
      MediaAsset(
          id: 'm1',
          classId: 'r3',
          type: 'video',
          fileName: 'media/2026-10/a.mp4',
          sizeBytes: 1,
          createdAt: now),
      MediaAsset(
          id: 'm2',
          classId: 'r3',
          type: 'video',
          fileName: 'media/2026-10/b.mp4',
          sizeBytes: 1,
          createdAt: now),
    ];
    await tester.pumpWidget(MultiProvider(
      providers: [Provider<ClassSaver>.value(value: repo)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => RecordFormPage(existing: existing)),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 按标题定位附件行（AppBar ✕ 与附件 ✕ 的树序不稳定，不用下标）
    Finder removeButtonFor(String name) => find.descendant(
          of: find.ancestor(of: find.text(name), matching: find.byType(Row)).first,
          matching: find.byIcon(Icons.close),
        );
    expect(removeButtonFor('a.mp4'), findsOneWidget);
    await tester.tap(removeButtonFor('a.mp4')); // 删 m1
    await tester.pump();

    await tester.tap(find.text('保存'));
    await tester.pump();
    // 保存仍挂起：再删 m2（UI 可操作）
    await tester.tap(removeButtonFor('b.mp4'));
    await tester.pump();

    await tester.runAsync(() async {
      repo.gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(repo.drafts, hasLength(1));
    expect(repo.drafts.single.removeMediaIds, ['m1'],
        reason: '保存中的后续删除不得混进本次快照');
  });
}
