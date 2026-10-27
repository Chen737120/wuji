import 'dart:developer' as dev;

import 'package:drift/drift.dart';
import 'db.dart';
import 'taxonomy_repo.dart';
import '../models/models.dart';
import '../services/archive_fs.dart' show MediaPathResolver;
import '../services/archive_store.dart';
import '../services/manifest.dart';
import '../services/save_flow.dart' as space_check
    show incomingBytesOf, needsSpaceWarning;

/// 表单→存档的输入载体。
class MediaInput {
  const MediaInput({
    required this.sourcePath,
    required this.ext,
    required this.isVideo,
    this.durationSec,
    this.sizeBytes = 0,
  });

  final String sourcePath;
  final String ext;
  final bool isVideo;
  final int? durationSec;
  final int sizeBytes;
}

class ClassDraft {
  const ClassDraft({
    required this.record,
    required this.newMedia,
    required this.removeMediaIds,
  });

  final ClassRecord record;
  final List<MediaInput> newMedia; // 待导入的相册文件
  final List<String> removeMediaIds; // 编辑时被 ✕ 的旧附件
}

/// 表单页依赖的窄接口：widget 测试可注入无 IO 的假实现。
abstract class ClassSaver {
  AppDatabase get db;
  Future<void> saveDraft(ClassDraft d);
  Future<List<MediaAsset>> mediaOf(String classId);

  /// 全量附件按课分组（一次查询取回，替代逐课 N+1 查询）。
  Future<Map<String, List<MediaAsset>>> mediaByClass();
  Future<List<ClassRecord>> allRecords();
  Future<void> deleteRecord(String id);

  /// 空间预检（规格 §8）：freeBytes 不可用时恒 false。
  Future<bool> needsSpaceWarningFor(List<MediaInput> inputs);
}

/// 应用仓库：保存（全或无）、删除（级联文件）、启动对账、统计取数。
class AppRepository implements ClassSaver {
  AppRepository(this._db, this._archive, this._taxonomy, {this.thumbMaker});

  final AppDatabase _db;
  final ArchiveStore _archive;
  final TaxonomyRepo _taxonomy;

  /// 名单弹层需要同库仓库（表单页用）。
  @override
  AppDatabase get db => _db;

  /// 保存前空间预检：剩余空间不足新附件总量时返回 true（SAF 查询不可用则恒 false）。
  Future<bool> needsSpaceWarning(List<MediaInput> inputs) async {
    final free = await _archive.fs.freeBytes();
    return space_check.needsSpaceWarning(
        free, space_check.incomingBytesOf(inputs));
  }

  @override
  Future<bool> needsSpaceWarningFor(List<MediaInput> inputs) =>
      needsSpaceWarning(inputs);

  /// 视频缩略图生成器（设备端注入 video_thumbnail；宿主测试 null）。
  /// 返回缩略图在存档内的相对路径（如 thumbs/uuid.jpg），失败返回 null。
  final Future<String?> Function(String sourcePath)? thumbMaker;

  @override
  Future<List<ClassRecord>> allRecords() =>
      (_db.select(_db.classRecords)
            ..orderBy([(t) => OrderingTerm.desc(t.date)]))
          .get();

  @override
  Future<List<MediaAsset>> mediaOf(String classId) =>
      (_db.select(_db.mediaAssets)..where((t) => t.classId.equals(classId)))
          .get();

  @override
  Future<Map<String, List<MediaAsset>>> mediaByClass() async {
    final all = await _db.select(_db.mediaAssets).get();
    final byClass = <String, List<MediaAsset>>{};
    for (final m in all) {
      byClass.putIfAbsent(m.classId, () => []).add(m);
    }
    return byClass;
  }

  Future<List<MediaAsset>> allMedia() => _db.select(_db.mediaAssets).get();

  /// 全或无保存（规格 §5.2）：
  /// staging→commit 文件 → 事务登记（upsert 课 + 新附件 + 删旧附件行）→ 删旧文件 → 刷 manifest。
  /// 任一步失败：反向删除本次已落盘文件并上抛，不留半截。
  @override
  Future<void> saveDraft(ClassDraft d) async {
    // 表单内同一文件去重（键=sourcePath+sizeBytes）
    final seen = <String>{};
    final inputs = d.newMedia
        .where((m) => seen.add('${m.sourcePath}:${m.sizeBytes}'))
        .toList();

    final committed = <String>[]; // 本次已转正的文件
    final staged = <String>[]; // 本次已 staging 的文件
    final thumbs = <String>[]; // 本次生成的缩略图
    final mediaRows = <MediaAssetsCompanion>[];
    try {
      await _taxonomy.ensureBuiltins();
      for (final m in inputs) {
        final id = _archive.newId();
        final tempRel = await _archive.stageFromPath(m.sourcePath, ext: m.ext);
        staged.add(tempRel);
        String? thumbRel;
        if (m.isVideo && thumbMaker != null) {
          try {
            thumbRel = await thumbMaker!(m.sourcePath);
            if (thumbRel != null) thumbs.add(thumbRel);
          } catch (_) {
            thumbRel = null; // 封面失败容忍：null，UI 用占位
          }
        }
        final finalRel = await _archive.commit(
            tempRel, DateTime.parse(d.record.date), id, m.ext);
        staged.remove(tempRel);
        committed.add(finalRel);
        mediaRows.add(MediaAssetsCompanion.insert(
          id: id,
          classId: d.record.id,
          type: m.isVideo ? 'video' : 'image',
          fileName: finalRel,
          thumbName: Value(thumbRel),
          durationSec: Value(m.durationSec),
          sizeBytes: Value(m.sizeBytes),
          createdAt: DateTime.now(),
        ));
      }

      // 名称快照回填：touch 名单并取 id
      String? sid, tid, stid;
      if ((d.record.styleName ?? '').isNotEmpty) {
        final t = await _taxonomy.touchByName(TaxonomyKind.style, d.record.styleName!);
        sid = t.id;
      }
      if ((d.record.teacherName ?? '').isNotEmpty) {
        final t = await _taxonomy.touchByName(TaxonomyKind.teacher, d.record.teacherName!);
        tid = t.id;
      }
      if ((d.record.studioName ?? '').isNotEmpty) {
        final t = await _taxonomy.touchByName(TaxonomyKind.studio, d.record.studioName!);
        stid = t.id;
      }

      // 事务前先取被移除附件的文件名（行删除后查不到）
      final removedFiles = <(String, String?)>[];
      if (d.removeMediaIds.isNotEmpty) {
        final oldRows = await (_db.select(_db.mediaAssets)
              ..where((t) => t.id.isIn(d.removeMediaIds)))
            .get();
        removedFiles.addAll(oldRows.map((r) => (r.fileName, r.thumbName)));
      }

      await _db.transaction(() async {
        await _db.into(_db.classRecords).insertOnConflictUpdate(
                ClassRecordsCompanion.insert(
                id: d.record.id,
                date: d.record.date,
                styleId: Value(sid),
                teacherId: Value(tid),
                studioId: Value(stid),
                styleName: Value(d.record.styleName),
                teacherName: Value(d.record.teacherName),
                studioName: Value(d.record.studioName),
                sessionCount: Value(d.record.sessionCount),
                minutesEach: Value(d.record.minutesEach),
                note: Value(d.record.note),
                createdAt: d.record.createdAt,
                updatedAt: DateTime.now(),
              ),
            );
        for (final row in mediaRows) {
          await _db.into(_db.mediaAssets).insert(row);
        }
        if (d.removeMediaIds.isNotEmpty) {
          await (_db.delete(_db.mediaAssets)
                ..where((t) => t.id.isIn(d.removeMediaIds)))
              .go();
        }
      });

      // 事务已提交：删被移除附件的文件是 best-effort（终审 I2 —— 不在补偿
      // 范围内，删除失败只留一个已无行引用的孤儿文件，绝不能反删已入库的新文件）
      for (final (file, thumb) in removedFiles) {
        try {
          await _archive.deleteRel(file);
          if (thumb != null) await _archive.deleteRel(thumb);
        } catch (_) {}
      }

      await _writeManifestQuietly();
    } catch (e) {
      // 补偿（仅限事务提交前失败）：删本次落盘的所有文件
      for (final rel in [...committed, ...staged, ...thumbs]) {
        try {
          await _archive.deleteRel(rel);
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// 删除课：确认弹窗在前（UI 层），此处事务删行→删文件→刷 manifest。
  @override
  Future<void> deleteRecord(String id) async {
    final rows = await mediaOf(id);
    await _db.transaction(() async {
      await (_db.delete(_db.classRecords)..where((t) => t.id.equals(id))).go();
    });
    // 文件删除 best-effort（P2-16）：SAF 权限被收回时不能让删课报错、
    // 剩余文件不删、manifest 不刷；失败只记日志，孤儿留给用户手动清。
    var failedDeletes = 0;
    for (final r in rows) {
      for (final rel in [r.fileName, if (r.thumbName != null) r.thumbName!]) {
        try {
          await _archive.deleteRel(rel);
        } catch (e) {
          failedDeletes++;
          dev.log('删除文件失败 $rel: $e', name: 'wuji');
        }
      }
    }
    if (failedDeletes > 0) {
      dev.log('deleteRecord 有 $failedDeletes 个文件未删除', name: 'wuji');
    }
    await _writeManifestQuietly();
  }

  /// 补齐缺失封面（P2-36）：导入包没有 thumbName、或历史失败的行。
  /// 每次最多 [limit] 条，失败跳过；fire-and-forget，绝不阻塞启动。
  Future<int> backfillMissingThumbs({int limit = 10}) async {
    final maker = thumbMaker;
    if (maker == null) return 0;
    final rows = await (_db.select(_db.mediaAssets)
          ..where((t) => t.type.equals('video') & t.thumbName.isNull())
          ..limit(limit))
        .get();
    final fs = _archive.fs;
    var done = 0;
    for (final r in rows) {
      try {
        final String? abs;
        if (fs is MediaPathResolver) {
          abs = await (fs as MediaPathResolver)
              .toAbsolutePath(r.fileName, paced: true);
        } else {
          abs = null; // SAF/Local 之外的实现不支持取绝对路径
        }
        if (abs == null) continue;
        final rel = await maker(abs);
        if (rel == null) continue;
        await (_db.update(_db.mediaAssets)
              ..where((t) => t.id.equals(r.id)))
            .write(MediaAssetsCompanion(thumbName: Value(rel)));
        done++;
      } catch (e) {
        dev.log('thumb 补生成失败 ${r.fileName.split('/').last}: $e',
            name: 'wuji');
      }
    }
    if (done > 0) await _writeManifestQuietly();
    return done;
  }

  /// 启动对账（规格 §5.2，终审 C2/C3 收窄后的安全版）：
  /// 1) 空库＋存档有 manifest → 导入重建（幂等，事务化）；
  /// 2) 清扫只清 `media/.staging/`（保存流程的确定残留），绝不碰正式命名文件；
  /// 3) manifest 解析/导入任何异常都被吞掉记日志 —— 启动路径绝不因存档问题崩溃。
  Future<void> reconcileOnStartup() async {
    try {
      final records = await allRecords();
      if (records.isEmpty) {
        final manifestJson = await _archive.readManifest();
        if (manifestJson != null) {
          final parsed = parseManifest(manifestJson);
          if (parsed.entries.isNotEmpty) {
            await _importInTransaction(parsed.entries);
          }
        }
      }
      await _archive.sweepOrphans(referencedRels: const {});
      // 存档文件夹对系统媒体库遮蔽：课堂视频/图片只归 App 管，
      // 不出现在系统相册（「保存到相册」才是显式导出）。已有索引项
      // 会在系统下次媒体扫描（通常重启）后消失。
      if (!await _archive.fs.exists('.nomedia')) {
        await _archive.fs.write('.nomedia', const Stream.empty());
      }
    } catch (_) {
      // 启动对账永不致命（终审 I9）：存档不可用时 App 照常打开
    }
  }

  /// manifest → 库重建，单事务（全或无；中断重跑幂等）。
  Future<void> _importInTransaction(List<ManifestEntry> entries) async {
    // 先把媒体文件从存档自身「按基名」解析拷贝是重连场景（源=本存档）——
    // 此时文件已在位，无需复制；只登记缺的行。
    await _taxonomy.ensureBuiltins();
    await repoDbTransaction(() async {
      for (final e in entries) {
        final exists = await (_db.select(_db.classRecords)
              ..where((t) => t.id.equals(e.id)))
            .getSingleOrNull();
        if (exists != null) continue;
        String? sid, tid, stid;
        if ((e.styleName ?? '').isNotEmpty) {
          sid =
              (await _taxonomy.touchByName(TaxonomyKind.style, e.styleName!)).id;
        }
        if ((e.teacherName ?? '').isNotEmpty) {
          tid = (await _taxonomy
                  .touchByName(TaxonomyKind.teacher, e.teacherName!))
              .id;
        }
        if ((e.studioName ?? '').isNotEmpty) {
          stid = (await _taxonomy
                  .touchByName(TaxonomyKind.studio, e.studioName!))
              .id;
        }
        await _db.into(_db.classRecords).insert(ClassRecordsCompanion.insert(
              id: e.id,
              date: e.date,
              styleId: Value(sid),
              teacherId: Value(tid),
              studioId: Value(stid),
              styleName: Value(e.styleName),
              teacherName: Value(e.teacherName),
              studioName: Value(e.studioName),
              sessionCount: Value(e.sessionCount),
              minutesEach: Value(e.minutesEach),
              note: Value(e.note),
              createdAt: e.createdAt ?? DateTime.now(),
              updatedAt: DateTime.now(),
            ));
        for (final m in e.media) {
          final present = await _archive.fs.exists(m.fileName);
          if (!present) continue;
          await _db.into(_db.mediaAssets).insert(MediaAssetsCompanion.insert(
                id: _archive.newId(),
                classId: e.id,
                type: m.type,
                fileName: m.fileName,
                thumbName: Value(m.thumbName),
                durationSec: Value(m.durationSec),
                sizeBytes: Value(m.sizeBytes),
                createdAt: DateTime.now(),
              ));
        }
      }
    });
  }

  Future<void> repoDbTransaction(Future<void> Function() body) =>
      _db.transaction(body);

  /// manifest 写失败不回滚保存（可由下次对账重建），只静默。
  Future<void> _writeManifestQuietly() async {
    try {
      final records = await allRecords();
      final media = await allMedia();
      // 存档切换后 DB 仍指向旧存档（P1-6）：抽样全缺失时拒写，
      // 避免把引用旧路径的全量清单覆写进新存档（会毁掉他档重建依据）
      if (media.isNotEmpty) {
        final sample = media.take(3).toList();
        var missing = 0;
        for (final m in sample) {
          if (!await _archive.exists(m.fileName)) missing++;
        }
        if (missing == sample.length) {
          dev.log('manifest 跳过写入：抽样 ${sample.length} 个文件均不在当前存档',
              name: 'wuji');
          return;
        }
      }
      final json = buildManifestJson(records, media);
      await _archive.writeManifest(json);
    } catch (_) {}
  }
}
