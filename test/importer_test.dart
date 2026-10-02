import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/data/app_repository.dart';
import 'package:wuji/data/db.dart';
import 'package:wuji/data/taxonomy_repo.dart';
import 'package:wuji/models/models.dart';
import 'package:wuji/services/archive_fs.dart';
import 'package:wuji/services/archive_store.dart';
import 'package:wuji/services/importer.dart';
import 'package:wuji/services/manifest.dart';

void main() {
  late Directory tmp;
  late AppDatabase db;
  late ArchiveStore store;
  late TaxonomyRepo taxonomy;
  late AppRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wuji_import');
    db = appDatabaseForTest();
    store = ArchiveStore(LocalArchiveFs(tmp.path));
    taxonomy = TaxonomyRepo(db);
    repo = AppRepository(db, store, taxonomy);
  });
  tearDown(() async {
    await db.close();
    for (var i = 0; i < 5; i++) {
      try {
        await tmp.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
  });

  test('planImport: empty db → all create; same key → patch', () async {
    final entries = [
      ManifestEntry(
          id: 'x1', date: '2026-09-30', styleName: '爵士',
          sessionCount: 1, minutesEach: 90,
          media: [ManifestMedia(fileName: 'media/2026-09/a.mp4', type: 'video', sizeBytes: 4)]),
    ];
    // 空库 → create
    final plan1 = planImport(entries, await repo.allRecords());
    expect(plan1.toCreate, hasLength(1));
    expect(plan1.toPatch, isEmpty);
    // 执行后重复导入 → unchanged/patch
    await executeImport(plan1,
        sourceFs: store.fs, archive: store, repo: repo, taxonomy: taxonomy);
    expect((await repo.allRecords()).single.id, 'x1');
    final plan2 = planImport(entries, await repo.allRecords());
    expect(plan2.toCreate, isEmpty);
    expect(plan2.toPatch, hasLength(1));
  });

  test('executeImport copies media into archive with new uuid path', () async {
    final srcDir = Directory('${tmp.path}/src/media/2026-09')
      ..createSync(recursive: true);
    File('${srcDir.path}/a.mp4').writeAsBytesSync([1, 2, 3, 4]);
    final sourceFs = LocalArchiveFs('${tmp.path}/src');
    final entries = [
      ManifestEntry(
          id: 'x1', date: '2026-09-30', styleName: '爵士', teacherName: '小鹿',
          sessionCount: 2, minutesEach: 90, note: '旧课',
          media: [ManifestMedia(fileName: 'media/2026-09/a.mp4', type: 'video', sizeBytes: 4)]),
    ];
    final plan = planImport(entries, await repo.allRecords());
    await executeImport(plan,
        sourceFs: sourceFs, archive: store, repo: repo, taxonomy: taxonomy);

    final rec = await db.getClassRecord('x1');
    expect(rec.note, '旧课');
    expect(rec.sessionCount, 2);
    final media = await repo.mediaOf('x1');
    expect(media, hasLength(1));
    expect(media.first.fileName.startsWith('media/2026-09/'), isTrue);
    expect(media.first.fileName.endsWith('.mp4'), isTrue);
    expect(await store.fs.exists(media.first.fileName), isTrue);
    // 名单自动补建
    final teachers = await taxonomy.byKind(TaxonomyKind.teacher);
    expect(teachers.any((t) => t.name == '小鹿'), isTrue);
  });

  test('folder-name fallback parses date_style_teacher_studio', () {
    final entries = parseFolderFallback([
      '2026-09-24_韩舞_阿哲',
      '2026-09-30_爵士_小鹿_光影舞室',
      'not-a-date_爵士',
    ]);
    expect(entries, hasLength(2));
    expect(entries[0].date, '2026-09-24');
    expect(entries[0].styleName, '韩舞');
    expect(entries[0].teacherName, '阿哲');
    expect(entries[0].studioName, isNull);
    expect(entries[1].studioName, '光影舞室');
  });

  test('interrupted import re-run completes without duplicates', () async {
    final srcDir = Directory('${tmp.path}/src2/media/2026-09')
      ..createSync(recursive: true);
    File('${srcDir.path}/a.mp4').writeAsBytesSync([9, 9]);
    final sourceFs = LocalArchiveFs('${tmp.path}/src2');
    final entries = [
      ManifestEntry(
          id: 'y1', date: '2026-09-24', styleName: '韩舞',
          sessionCount: 1, minutesEach: 60,
          media: [ManifestMedia(fileName: 'media/2026-09/a.mp4', type: 'video', sizeBytes: 2)]),
    ];
    // 模拟中断：记录已建但媒体缺失（先建记录）
    final plan = planImport(entries, await repo.allRecords());
    await executeImport(plan,
        sourceFs: LocalArchiveFs('${tmp.path}/empty'),
        archive: store, repo: repo, taxonomy: taxonomy);
    expect(await repo.mediaOf('y1'), isEmpty); // 源不存在 → 媒体没进

    // 重跑（这次源在）→ 补回媒体，不重复建课
    final plan2 = planImport(entries, await repo.allRecords());
    expect(plan2.toPatch, hasLength(1));
    await executeImport(plan2,
        sourceFs: sourceFs, archive: store, repo: repo, taxonomy: taxonomy);
    expect((await repo.allRecords()), hasLength(1));
    expect(await repo.mediaOf('y1'), hasLength(1));
  });

  test('ROUND-TRIP: export zip layout -> import restores media (C1)', () async {
    final srcDir = Directory('${tmp.path}/zipx/2026-09-30_爵士')
      ..createSync(recursive: true);
    File('${srcDir.path}/abc.mp4').writeAsBytesSync([5, 6, 7]);
    final sourceFs = LocalArchiveFs('${tmp.path}/zipx');
    const entries = [
      ManifestEntry(
          id: 'z1', date: '2026-09-30', styleName: '爵士', teacherName: '小鹿',
          sessionCount: 1, minutesEach: 90, note: 'round-trip',
          media: [ManifestMedia(fileName: 'media/2026-09/abc.mp4', type: 'video', sizeBytes: 3)]),
    ];
    final plan = planImport(entries, await repo.allRecords());
    final report = await executeImport(plan,
        sourceFs: sourceFs, archive: store, repo: repo, taxonomy: taxonomy);
    expect(report.created, 1);
    final media = await repo.mediaOf('z1');
    expect(media, hasLength(1));
    expect(await store.fs.exists(media.first.fileName), isTrue);
    expect(media.first.sizeBytes, 3);
  });

  test('重复导入同一备份不翻倍附件 (I1)', () async {
    final srcDir = Directory('${tmp.path}/dup/media/2026-09')
      ..createSync(recursive: true);
    File('${srcDir.path}/a.mp4').writeAsBytesSync([1, 1, 1]);
    final sourceFs = LocalArchiveFs('${tmp.path}/dup');
    const entries = [
      ManifestEntry(
          id: 'd1', date: '2026-09-24', styleName: '韩舞',
          sessionCount: 1, minutesEach: 60,
          media: [ManifestMedia(fileName: 'media/2026-09/a.mp4', type: 'video', sizeBytes: 3)]),
    ];
    await executeImport(planImport(entries, await repo.allRecords()),
        sourceFs: sourceFs, archive: store, repo: repo, taxonomy: taxonomy);
    expect(await repo.mediaOf('d1'), hasLength(1));
    final plan2 = planImport(entries, await repo.allRecords());
    final report2 = await executeImport(plan2,
        sourceFs: sourceFs, archive: store, repo: repo, taxonomy: taxonomy);
    expect(report2.mediaCopied, 0);
    expect(await repo.mediaOf('d1'), hasLength(1));
  });
  test('planImport describe text', () {
    final entries = [
      ManifestEntry(id: 'a', date: '2026-09-30', styleName: '爵士',
          sessionCount: 1, minutesEach: 90, media: []),
    ];
    final plan = planImport(entries, []);
    expect(plan.describe(), '发现 1 节课 → 新建 1 节');
  });
}
