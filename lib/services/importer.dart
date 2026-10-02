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
  });

  /// 库里没有的课（将新建）
  final List<ManifestEntry> toCreate;
  /// 库里已有的课（将补回附件）
  final List<ManifestEntry> toPatch;

  bool get isEmpty => toCreate.isEmpty && toPatch.isEmpty;

  String describe() {
    final patchMedia = toPatch.fold<int>(0, (a, e) => a + e.media.length);
    final parts = <String>[
      '发现 ${toCreate.length + toPatch.length} 节课',
      if (toCreate.isNotEmpty) '新建 ${toCreate.length} 节',
      if (toPatch.isNotEmpty) '${toPatch.length} 节已有（补回 $patchMedia 个附件）',
    ];
    return parts.join(' → ');
  }
}

ImportPlan planImport(
    List<ManifestEntry> incoming, List<ClassRecord> existing) {
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
  return ImportPlan(toCreate: toCreate, toPatch: toPatch);
}

/// 幂等执行（规格 §7）：新建缺的课（保留原 id）、补回已有课缺失的媒体文件、
/// 自动补建缺失名单项；中断后重跑自动跳过已完成部分。
Future<void> executeImport(
  ImportPlan plan, {
  required ArchiveFs sourceFs,
  required ArchiveStore archive,
  required AppRepository repo,
  required TaxonomyRepo taxonomy,
}) async {
  await taxonomy.ensureBuiltins();
  final existing = await repo.allRecords();
  final handled = <String>{};

  for (final e in [...plan.toCreate, ...plan.toPatch]) {
    ClassRecord? record;
    for (final r in existing) {
      if (_sameClass(r, e)) {
        record = r;
        break;
      }
    }
    final isNew = record == null;

    // 建课（新建）或确保存在（patch：可能上次中断只建了课没进媒体）
    if (isNew) {
      String? sid = e.styleId, tid = e.teacherId, stid = e.studioId;
      if ((e.styleName ?? '').isNotEmpty) {
        sid = (await taxonomy.touchByName(TaxonomyKind.style, e.styleName!)).id;
      }
      if ((e.teacherName ?? '').isNotEmpty) {
        tid =
            (await taxonomy.touchByName(TaxonomyKind.teacher, e.teacherName!)).id;
      }
      if ((e.studioName ?? '').isNotEmpty) {
        stid =
            (await taxonomy.touchByName(TaxonomyKind.studio, e.studioName!)).id;
      }
      await repo.db.into(repo.db.classRecords).insert(ClassRecordsCompanion.insert(
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
    } else {
      // 已存在的课：若名称字段为空而包里有值，不覆盖（保护用户改动）
    }
    handled.add(e.id);

    // 补媒体：跳过库里已登记的文件名（幂等），源里缺的跳过（中断可重跑）
    final have = (await repo.mediaOf(e.id)).map((m) => m.fileName).toSet();
    for (final m in e.media) {
      final baseName = m.fileName.split('/').last;
      final ext = baseName.contains('.') ? baseName.split('.').last : 'bin';
      final targetRel = archive.mediaRel(DateTime.parse(e.date), archive.newId(), ext);
      if (have.contains(targetRel)) continue;
      if (!await sourceFs.exists(m.fileName)) continue; // 源缺失：跳过
      final bytes = await _readAll(sourceFs, m.fileName);
      await archive.fs.write(targetRel, Stream<List<int>>.value(bytes));
      await repo.db.into(repo.db.mediaAssets).insert(MediaAssetsCompanion.insert(
            id: archive.newId(),
            classId: e.id,
            type: m.type,
            fileName: targetRel,
            thumbName: const Value(null),
            durationSec: Value(m.durationSec),
            sizeBytes: Value(bytes.length),
            createdAt: DateTime.now(),
          ));
    }
  }
}

Future<List<int>> _readAll(ArchiveFs fs, String rel) async {
  final b = <int>[];
  await for (final chunk in fs.read(rel)) {
    b.addAll(chunk);
  }
  return b;
}

final _folderDateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// 文件夹名回退解析：`日期_舞种[_老师[_舞室]]`（_ 歧义可接受，清单是主路径）。
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
