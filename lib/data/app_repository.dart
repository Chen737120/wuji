import 'package:drift/drift.dart';
import 'db.dart';
import 'taxonomy_repo.dart';
import '../models/models.dart';
import '../services/archive_store.dart';
import '../services/manifest.dart';

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
  Future<List<ClassRecord>> allRecords();
  Future<void> deleteRecord(String id);
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

      // 事务后删被移除附件的文件
      for (final (file, thumb) in removedFiles) {
        await _archive.deleteRel(file);
        if (thumb != null) await _archive.deleteRel(thumb);
      }

      await _writeManifestQuietly();
    } catch (e) {
      // 补偿：删本次落盘的所有文件
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
    for (final r in rows) {
      await _archive.deleteRel(r.fileName);
      if (r.thumbName != null) await _archive.deleteRel(r.thumbName!);
    }
    await _writeManifestQuietly();
  }

  /// 启动对账（规格 §5.2 第 3 条，安全顺序）：
  /// 1) 空库＋存档有 manifest → 先导入登记（manifest 是权威，先建引用再清扫）；
  /// 2) 空库＋无 manifest → 不清扫（存档内容未知，绝不销毁无法核对的数据）；
  /// 3) 非空库 → 清理无主媒体（上次保存失败的残留）。
  Future<void> reconcileOnStartup() async {
    final records = await allRecords();
    if (records.isEmpty) {
      final manifestJson = await _archive.readManifest();
      if (manifestJson == null) return;
      final parsed = parseManifest(manifestJson);
      if (parsed.entries.isEmpty) return;
      await _importFromManifest(parsed.entries);
    }
    final refs = (await allMedia()).map((m) => m.fileName).toSet();
    await _archive.sweepOrphans(referencedRels: refs);
  }

  /// manifest → 库重建（幂等：已存在 id 跳过）。T14 导入复用。
  Future<void> _importFromManifest(List<ManifestEntry> entries) async {
    await _taxonomy.ensureBuiltins();
    for (final e in entries) {
      final exists = await (_db.select(_db.classRecords)
            ..where((t) => t.id.equals(e.id)))
          .getSingleOrNull();
      if (exists != null) continue;
      String? sid, tid, stid;
      if ((e.styleName ?? '').isNotEmpty) {
        sid = (await _taxonomy.touchByName(TaxonomyKind.style, e.styleName!)).id;
      }
      if ((e.teacherName ?? '').isNotEmpty) {
        tid = (await _taxonomy.touchByName(TaxonomyKind.teacher, e.teacherName!)).id;
      }
      if ((e.studioName ?? '').isNotEmpty) {
        stid = (await _taxonomy.touchByName(TaxonomyKind.studio, e.studioName!)).id;
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
            updatedAt: e.updatedAt ?? DateTime.now(),
          ));
      for (final m in e.media) {
        // 只登记存档里确实存在的文件；缺失的记为丢文件态（详情页显示丢失）
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
    await _writeManifestQuietly();
  }

  /// manifest 写失败不回滚保存（可由下次对账重建），只静默。
  Future<void> _writeManifestQuietly() async {
    try {
      final json = buildManifestJson(await allRecords(), await allMedia());
      await _archive.writeManifest(json);
    } catch (_) {}
  }
}
