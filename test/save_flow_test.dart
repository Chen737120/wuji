import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/data/app_repository.dart';
import 'package:wuji/data/db.dart';
import 'package:wuji/data/taxonomy_repo.dart';
import 'package:wuji/services/archive_fs.dart';
import 'package:wuji/services/archive_store.dart';
import 'package:wuji/services/manifest.dart';
import 'package:wuji/models/models.dart';

void main() {
  late Directory tmp;
  late AppDatabase db;
  late ArchiveStore store;
  late TaxonomyRepo taxonomy;
  late AppRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wuji_save');
    db = appDatabaseForTest();
    store = ArchiveStore(LocalArchiveFs(tmp.path));
    taxonomy = TaxonomyRepo(db);
    repo = AppRepository(db, store, taxonomy);
  });
  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  MediaInput mi(String path, {bool video = true, int size = 100}) =>
      MediaInput(
        sourcePath: path,
        ext: video ? 'mp4' : 'jpg',
        isVideo: video,
        sizeBytes: size,
      );

  test('save draft inserts record, files and manifest', () async {
    final src = File('${tmp.path}/v.mp4')..writeAsBytesSync([1, 2, 3, 4]);
    final draft = ClassDraft(
      record: ClassRecord(
        id: 'r1',
        date: '2026-10-02',
        styleName: '爵士',
        teacherName: '小鹿',
        sessionCount: 2,
        minutesEach: 90,
        note: '第一行标题\n正文',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      newMedia: [mi(src.path)],
      removeMediaIds: const [],
    );
    await repo.saveDraft(draft);

    final media = await repo.mediaOf('r1');
    expect(media, hasLength(1));
    expect(await store.fs.exists(media.first.fileName), isTrue);
    expect(media.first.type, 'video');
    // 名称快照回填：styleId/teacherId 指向名单
    final rec = await db.getClassRecord('r1');
    expect(rec.styleId, isNotNull);
    expect(rec.teacherId, isNotNull);
    // manifest 已写且含这条记录
    final manifest = await store.readManifest();
    expect(manifest, isNotNull);
    expect(manifest!, contains('"r1"'));
  });

  test('save then delete removes db rows and files', () async {
    final src = File('${tmp.path}/v2.mp4')..writeAsBytesSync([5, 6]);
    await repo.saveDraft(ClassDraft(
      record: ClassRecord(
        id: 'r2',
        date: '2026-10-02', sessionCount: 1, minutesEach: 90,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      newMedia: [mi(src.path)],
      removeMediaIds: const [],
    ));
    final media = await repo.mediaOf('r2');
    expect(await store.fs.exists(media.first.fileName), isTrue);
    await repo.deleteRecord('r2');
    expect(await repo.mediaOf('r2'), isEmpty);
    expect(await (db.select(db.classRecords)..where((t) => t.id.equals('r2'))).get(),
        isEmpty);
    expect(await store.fs.exists(media.first.fileName), isFalse);
  });

  test('same source twice in one draft is deduped by path+size', () async {
    final src = File('${tmp.path}/v3.mp4')..writeAsBytesSync([7, 8, 9]);
    await repo.saveDraft(ClassDraft(
      record: ClassRecord(
        id: 'r3',
        date: '2026-10-02', sessionCount: 1, minutesEach: 90,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      newMedia: [mi(src.path, size: 3), mi(src.path, size: 3)],
      removeMediaIds: const [],
    ));
    expect(await repo.mediaOf('r3'), hasLength(1));
  });

  test('edit draft removes media rows and files, adds new ones', () async {
    final src1 = File('${tmp.path}/a.mp4')..writeAsBytesSync([1]);
    final src2 = File('${tmp.path}/b.mp4')..writeAsBytesSync([2]);
    await repo.saveDraft(ClassDraft(
      record: ClassRecord(
          id: 'r4', date: '2026-10-02', sessionCount: 1, minutesEach: 90,
          createdAt: DateTime.now(), updatedAt: DateTime.now()),
      newMedia: [mi(src1.path)],
      removeMediaIds: const [],
    ));
    final first = (await repo.mediaOf('r4')).single;

    await repo.saveDraft(ClassDraft(
      record: await db.getClassRecord('r4'),
      newMedia: [mi(src2.path)],
      removeMediaIds: [first.id],
    ));
    final after = await repo.mediaOf('r4');
    expect(after, hasLength(1));
    expect(after.first.id, isNot(first.id));
    expect(await store.fs.exists(first.fileName), isFalse);
    expect(await store.fs.exists(after.first.fileName), isTrue);
  });

  test('reconcileOnStartup keeps unreferenced media (C3: never delete user data)', () async {
    final src = File('${tmp.path}/c.mp4')..writeAsBytesSync([3]);
    await repo.saveDraft(ClassDraft(
      record: ClassRecord(
          id: 'r5', date: '2026-10-02', sessionCount: 1, minutesEach: 90,
          createdAt: DateTime.now(), updatedAt: DateTime.now()),
      newMedia: [mi(src.path)],
      removeMediaIds: const [],
    ));
    final media = (await repo.mediaOf('r5')).single;
    // 制造一个孤儿
    await store.fs.write('media/2026-10/orphan.mp4', Stream.value([9]));
    await repo.reconcileOnStartup();
    expect(await store.fs.exists(media.fileName), isTrue);
    expect(await store.fs.exists('media/2026-10/orphan.mp4'), isTrue);
  });

  test('reconcile rebuilds records from manifest when db is empty', () async {
    // 用本 repo 存一节课（写 manifest＋媒体），再用新空库模拟重装后对账
    final src = File('${tmp.path}/d.mp4')..writeAsBytesSync([4, 4]);
    await repo.saveDraft(ClassDraft(
      record: ClassRecord(
        id: 'r6',
        date: '2026-09-30',
        styleName: '爵士',
        teacherName: '小鹿',
        sessionCount: 1,
        minutesEach: 90,
        note: '旧课',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      newMedia: [mi(src.path)],
      removeMediaIds: const [],
    ));
    final oldMedia = (await repo.mediaOf('r6')).single;

    final db3 = appDatabaseForTest();
    final repo3 = AppRepository(db3, store, TaxonomyRepo(db3));
    await repo3.reconcileOnStartup();
    final manifestDebug = await store.readManifest();
    expect(manifestDebug, isNotNull, reason: 'manifest: $manifestDebug');
    final parsedDebug = parseManifest(manifestDebug!);
    expect(parsedDebug.errors, isEmpty,
        reason: 'parse errors: ${parsedDebug.errors}');
    final all = await repo3.allRecords();
    expect(all, hasLength(1));
    expect(all.single.id, 'r6');
    expect(all.single.note, '旧课');
    final media3 = await repo3.mediaOf('r6');
    expect(media3, hasLength(1));
    expect(media3.single.fileName, oldMedia.fileName);
    expect(await store.fs.exists(oldMedia.fileName), isTrue);
    await db3.close();
  });

  test('停用老师后编辑含该名称的历史课仍能保存（P1-1）', () async {
    final record = ClassRecord(
      id: 'r7',
      date: '2026-10-02',
      styleName: '爵士',
      teacherName: '张三',
      sessionCount: 1,
      minutesEach: 90,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final draft =
        ClassDraft(record: record, newMedia: const [], removeMediaIds: const []);
    await repo.saveDraft(draft);

    final teacher = (await taxonomy.byKind(TaxonomyKind.teacher))
        .singleWhere((e) => e.name == '张三');
    await taxonomy.deactivate(teacher.id);

    // 编辑同一课再保存（旧实现此处撞 UNIQUE(kind,name)，UI 显示「保存失败」）
    await repo.saveDraft(draft);

    final teachers =
        await taxonomy.byKind(TaxonomyKind.teacher, includeInactive: true);
    expect(teachers, hasLength(1));
    expect(teachers.single.isActive, isTrue, reason: '同名停用项应复活');
    expect((await repo.allRecords()).single.teacherName, '张三');
  });
}
