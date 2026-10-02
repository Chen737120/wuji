import 'package:drift/drift.dart' hide isNull;
import '../data/app_repository.dart';
import '../data/db.dart';
import '../data/taxonomy_repo.dart';
import '../models/models.dart';
import 'archive_fs.dart';
import 'archive_store.dart';
import 'manifest.dart';

/// 导入匹配键：日期＋名称快照＋节数×时长。
bool _sameClass(ClassRecord r, ManifestEntry e) =>
    r.date == e.date &&
    r.styleName == e.styleName &&
    r.teacherName == e.teacherName &&
    r.studioName == e.studioName &&
    r.sessionCount == e.sessionCount &&
    r.minutesEach == e.minutesEach;

class ImportPlan {
  const ImportPlan({
    required this.toCreate,
    required this.toPatch,
    required this.skippedCount,
  });

  /// 库里没有的课（将新建）
  final List<ManifestEntry> toCreate;
  /// 库里已有的课（将补回附件）
  final List<ManifestEntry> toPatch;
  final int skippedCount;

  bool get isEmpty => toCreate.isEmpty && toPatch.isEmpty;

  String describe() {
    final patchMedia = toPatch.fold<int>(0, (a, e) => a + e.media.length);
    final parts = <String>[
      if (skippedCount > 0) '跳过 $skippedCount 条异常数据，',
      '发现 ${toCreate.length + toPatch.length} 节课',
      if (toCreate.isNotEmpty) '新建 ${toCreate.length} 节',
      if (toPatch.isNotEmpty) '${toPatch.length} 节已有（补回 $patchMedia 个附件）',
    ];
    final base = parts.join(' → ');
    return skippedCount > 0 ? '跳过 $skippedCount 条异常数据；$base' : base;
  }
}

ImportPlan planImport(
    List<ManifestEntry> incoming, List<ClassRecord> existing,
    {int skippedCount = 0}) {
  final toCreate = <ManifestEntry>[];
  final toPatch = <ManifestEntry>[];
  for (final e in incoming) {
    final match = existing.where((r) => _sameClass(r, e)).toList();
    if (match.isEmpty) {
      toCreate.add(e);
    } else {
      toPatch.add(e);
    }
  }
  return ImportPlan(
      toCreate: toCreate, toPatch: toPatch, skippedCount: skippedCount);
}

/// 幂等键：源文件基名＋字节数（同一备份重复导入不再翻倍）。
String _mediaKey(String sourceBasename, int sizeBytes) =>
    '$sourceBasename:$sizeBytes';

String baseNameOf(String rel) => rel.split('/').last;

/// 执行导入（规格 §7，幂等）：
/// - 媒体按「基名索引」在源里解析（同时兼容存档布局 media/YYYY-MM/uuid.ext
///   与导出包布局 日期_舞种_xxx/原文件名 —— 终审 C1）；
/// - 已入库课按 (基名,字节数) 跳过已补附件（终审 I1）；
/// - 全部 DB 写入在单个事务内（终审 C2：中断不会留下半套库）；
/// - 源缺失的附件跳过，重跑自动补齐。
Future<ImportReport> executeImport(
  ImportPlan plan, {
  required ArchiveFs sourceFs,
  required ArchiveStore archive,
  required AppRepository repo,
  required TaxonomyRepo taxonomy,
}) async {
  await taxonomy.ensureBuiltins();
  final existing = await repo.allRecords();
  final existingById = {for (final r in existing) r.id: r};

  // 源文件基名索引（终审 C1）：基名 → 源相对路径列表
  final allSourceFiles = await sourceFs.list('');
  final byBasename = <String, List<String>>{};
  for (final rel in allSourceFiles) {
    byBasename.putIfAbsent(baseNameOf(rel), () => []).add(rel);
  }

  var createdCount = 0;
  var patchedCount = 0;
  var mediaCopied = 0;

  // 先拷文件（幂等），再一次性事务登记 DB（终审 C2）
  final dbRows = <(ClassRecordsCompanion?, List<MediaAssetsCompanion>)>[];

  for (final e in [...plan.toCreate, ...plan.toPatch]) {
    ClassRecord? record = existingById[e.id];
    if (record == null) {
      // 按匹配键再找一次（导出包里的 id 可能因重装重建过）
      for (final r in existing) {
        if (_sameClass(r, e)) {
          record = r;
          break;
        }
      }
    }

    // 幂等参照：该课已登记附件的 (基名,字节数) 集合
    final haveKeys = <String>{};
    if (record != null) {
      for (final m in await repo.mediaOf(record.id)) {
        // sourceName 是导入时留存的源基名（uuid 落盘名不携带该信息）
        haveKeys.add(_mediaKey(m.sourceName ?? baseNameOf(m.fileName), m.sizeBytes));
      }
    }

    final newMediaRows = <MediaAssetsCompanion>[];
    for (final m in e.media) {
      final key = _mediaKey(baseNameOf(m.fileName), m.sizeBytes);
      if (haveKeys.contains(key)) continue; // 终审 I1：确定性幂等
      String? sourceRel;
      if (await sourceFs.exists(m.fileName)) {
        sourceRel = m.fileName; // 存档重连：路径原样存在
      } else {
        for (final candidate in byBasename[baseNameOf(m.fileName)] ?? const <String>[]) {
          if (await sourceFs.exists(candidate)) {
            sourceRel = candidate;
            break;
          }
        }
      }
      if (sourceRel == null) continue; // 源缺失：跳过，重跑可补

      final bytes = await _readAll(sourceFs, sourceRel);
      final targetRel =
          archive.mediaRel(DateTime.parse(e.date), archive.newId(), _extOf(baseNameOf(m.fileName)));
      await archive.fs.write(targetRel, Stream<List<int>>.value(bytes));
      newMediaRows.add(MediaAssetsCompanion.insert(
        id: archive.newId(),
        classId: e.id,
        type: m.type,
        fileName: targetRel,
        sourceName: Value(baseNameOf(m.fileName)),
        thumbName: const Value(null),
        durationSec: Value(m.durationSec),
        sizeBytes: Value(bytes.length),
        createdAt: DateTime.now(),
      ));
      mediaCopied++;
      haveKeys.add(key);
    }

    if (record == null) {
      String? sid = e.styleId, tid = e.teacherId, stid = e.studioId;
      if ((e.styleName ?? '').isNotEmpty) {
        sid = (await taxonomy.touchByName(TaxonomyKind.style, e.styleName!)).id;
      }
      if ((e.teacherName ?? '').isNotEmpty) {
        tid = (await taxonomy
                .touchByName(TaxonomyKind.teacher, e.teacherName!))
            .id;
      }
      if ((e.studioName ?? '').isNotEmpty) {
        stid =
            (await taxonomy.touchByName(TaxonomyKind.studio, e.studioName!)).id;
      }
      dbRows.add((
        ClassRecordsCompanion.insert(
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
        ),
        newMediaRows,
      ));
      createdCount++;
    } else {
      dbRows.add((null, newMediaRows));
      patchedCount++;
    }
  }

  // 单事务登记：要么全部入库，要么全部不入（中断重跑幂等）
  if (dbRows.isNotEmpty) {
    await repo.db.transaction(() async {
      for (final (recordRow, mediaRows) in dbRows) {
        if (recordRow != null) {
          await repo.db.into(repo.db.classRecords).insert(recordRow);
        }
        for (final row in mediaRows) {
          await repo.db.into(repo.db.mediaAssets).insert(row);
        }
      }
    });
  }

  return ImportReport(
    created: createdCount,
    patched: patchedCount,
    mediaCopied: mediaCopied,
    skipped: plan.skippedCount,
  );
}

class ImportReport {
  const ImportReport({
    required this.created,
    required this.patched,
    required this.mediaCopied,
    required this.skipped,
  });
  final int created;
  final int patched;
  final int mediaCopied;
  final int skipped;

  @override
  String toString() =>
      '导入完成：新建 $created 节 · 补回附件 $mediaCopied 个 · 跳过 $skipped 条';
}

String _extOf(String fileName) =>
    fileName.contains('.') ? fileName.split('.').last : 'bin';

Future<List<int>> _readAll(ArchiveFs fs, String rel) async {
  final b = <int>[];
  await for (final chunk in fs.read(rel)) {
    b.addAll(chunk);
  }
  return b;
}

/// 文件夹名回退解析：`日期_舞种[_老师[_舞室]]`（_ 歧义可接受，清单是主路径）。
final _folderDateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

List<ManifestEntry> parseFolderFallback(List<String> folderNames) {
  final out = <ManifestEntry>[];
  for (final name in folderNames) {
    final segs = name.split('_');
    if (segs.isEmpty || !_folderDateRe.hasMatch(segs.first)) continue;
    if (DateTime.tryParse(segs.first) == null) continue;
    out.add(ManifestEntry(
      id: 'folder:$name',
      date: segs.first,
      styleName: segs.length > 1 ? segs[1] : null,
      teacherName: segs.length > 2 ? segs[2] : null,
      studioName: segs.length > 3 ? segs.sublist(3).join('_') : null,
      sessionCount: 1,
      minutesEach: 90,
      media: const [],
    ));
  }
  return out;
}
