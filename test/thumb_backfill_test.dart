import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/data/app_repository.dart';
import 'package:wuji/data/db.dart';
import 'package:wuji/data/taxonomy_repo.dart';
import 'package:wuji/services/archive_fs.dart';
import 'package:wuji/services/archive_store.dart';

/// P2-36：启动后台补齐缺失封面。
/// 用真实 sqlite（内存库）＋临时存档目录；thumbMaker 注入假实现。
void main() {
  late Directory tmp;
  late AppDatabase db;
  late ArchiveStore store;
  late List<String> calls;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wuji_thumb_backfill');
    db = appDatabaseForTest();
    store = ArchiveStore(LocalArchiveFs(tmp.path));
    calls = [];
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// 建一节带 [n] 条视频附件的课，所有 thumbName 为 null。
  Future<void> seedVideos(int n) async {
    final now = DateTime(2026, 10, 27);
    await db.into(db.classRecords).insert(ClassRecordsCompanion.insert(
          id: 'r1',
          date: '2026-10-27',
          createdAt: now,
          updatedAt: now,
        ));
    for (var i = 0; i < n; i++) {
      await db.into(db.mediaAssets).insert(MediaAssetsCompanion.insert(
            id: 'm$i',
            classId: 'r1',
            type: 'video',
            fileName: 'media/2026-10/m$i.mp4',
            createdAt: now,
          ));
    }
  }

  Future<int> countMissing() async {
    final rows = await db.select(db.mediaAssets).get();
    return rows.where((r) => r.thumbName == null).length;
  }

  AppRepository repoWith(Future<String?> Function(String) maker) =>
      AppRepository(db, store, TaxonomyRepo(db), thumbMaker: maker);

  test('每次最多补 10 条，再调一次补齐剩余', () async {
    await seedVideos(12);
    final repo = repoWith((src) async {
      calls.add(src);
      return 'thumbs/${calls.length}.jpg';
    });

    expect(await repo.backfillMissingThumbs(), 10);
    expect(calls, hasLength(10));
    expect(await countMissing(), 2);

    expect(await repo.backfillMissingThumbs(), 2);
    expect(calls, hasLength(12));
    expect(await countMissing(), 0);
    // 第三次已无可补：不再调用 maker
    expect(await repo.backfillMissingThumbs(), 0);
    expect(calls, hasLength(12));
  });

  test('生成器抛异常或返回 null：该行保持 null、不抛、继续下一条', () async {
    await seedVideos(3);
    var n = 0;
    final repo = repoWith((src) async {
      n++;
      if (n == 1) throw StateError('decode failed');
      if (n == 2) return null;
      return 'thumbs/ok.jpg';
    });

    expect(await repo.backfillMissingThumbs(), 1);
    expect(await countMissing(), 2);
    final rows = await db.select(db.mediaAssets).get();
    expect(rows.firstWhere((r) => r.id == 'm2').thumbName, 'thumbs/ok.jpg');
  });

  test('没有 thumbMaker 时直接返回 0', () async {
    await seedVideos(2);
    final repo = AppRepository(db, store, TaxonomyRepo(db));
    expect(await repo.backfillMissingThumbs(), 0);
    expect(await countMissing(), 2);
  });

  test('补生成成功会刷新 manifest', () async {
    await seedVideos(1);
    final repo = repoWith((src) async => 'thumbs/x.jpg');
    expect(await repo.backfillMissingThumbs(), 1);
    final manifest = await store.readManifest();
    expect(manifest, isNotNull);
    expect(manifest, contains('thumbs/x.jpg'));
  });
}
