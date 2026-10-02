import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import '../data/db.dart';

/// 导出命名与文本产物（规格 §6.1）。

/// 清洗文件/文件夹名非法字符（规格：`/\:*?"<>|` → `-`）。
String sanitizeSegment(String seg) {
  final cleaned = seg.replaceAll(RegExp(r'[/\\:*?"<>|]'), '-').trim();
  return cleaned.isEmpty ? '-' : cleaned;
}

/// 文件夹名 = 日期_舞种[_老师[_舞室]]（未填段省略）。
String folderBaseName(ClassRecord r) {
  final parts = <String>[
    r.date,
    if (r.styleName?.isNotEmpty ?? false) sanitizeSegment(r.styleName!),
    if (r.teacherName?.isNotEmpty ?? false) sanitizeSegment(r.teacherName!),
    if (r.studioName?.isNotEmpty ?? false) sanitizeSegment(r.studioName!),
  ];
  return parts.join('_');
}

/// 同键文件夹加序号（_2、_3…），保持入参顺序稳定。
Map<String, String> assignFolderNames(List<ClassRecord> records) {
  final used = <String, int>{};
  final out = <String, String>{};
  for (final r in records) {
    final base = folderBaseName(r);
    final n = (used[base] ?? 0) + 1;
    used[base] = n;
    out[r.id] = n == 1 ? base : '${base}_$n';
  }
  return out;
}

/// 感受.txt（UTF-8）：标题行 → 信息块 → 感受全文（未写标注）。
String feelingsTxt(ClassRecord r) {
  final note = r.note?.trim() ?? '';
  final hasNote = note.isNotEmpty;
  final title = hasNote ? note.split('\n').first.trim() : '本课未写感受';
  final lines = <String>[
    title,
    '',
    '日期：${r.date}',
    '时长：${r.sessionCount}节 × ${r.minutesEach}分钟（共${r.totalMinutes}分钟）',
    if (r.styleName?.isNotEmpty ?? false) '舞种：${r.styleName}',
    if (r.teacherName?.isNotEmpty ?? false) '老师：${r.teacherName}',
    if (r.studioName?.isNotEmpty ?? false) '舞室：${r.studioName}',
    '',
    hasNote ? note : '（本课未写感受）',
  ];
  return lines.join('\n');
}

/// 舞记总表.xlsx：每课一行。
Uint8List buildWorkbook(List<ClassRecord> records, Map<String, int> mediaCounts,
    Map<String, String> folderNames) {
  final excel = Excel.createExcel();
  final sheet = excel['舞记总表'];
  sheet.appendRow([
    TextCellValue('日期'),
    TextCellValue('节数'),
    TextCellValue('每节时长'),
    TextCellValue('总时长'),
    TextCellValue('舞种'),
    TextCellValue('老师'),
    TextCellValue('舞室'),
    TextCellValue('感受'),
    TextCellValue('附件数'),
    TextCellValue('文件夹名'),
  ]);
  for (final r in records) {
    final note = (r.note ?? '').trim();
    sheet.appendRow([
      TextCellValue(r.date),
      IntCellValue(r.sessionCount),
      IntCellValue(r.minutesEach),
      IntCellValue(r.totalMinutes),
      TextCellValue(r.styleName ?? ''),
      TextCellValue(r.teacherName ?? ''),
      TextCellValue(r.studioName ?? ''),
      TextCellValue(note),
      IntCellValue(mediaCounts[r.id] ?? 0),
      TextCellValue(folderNames[r.id] ?? folderBaseName(r)),
    ]);
  }
  // 删除多余的默认 Sheet1
  if (excel.sheets.containsKey('Sheet1') && excel.sheets.length > 1) {
    excel.rename('Sheet1', 'Sheet1_tmp');
    excel.delete('Sheet1_tmp');
  }
  return Uint8List.fromList(excel.encode()!);
}

/// 测试辅助：解码工作簿为 header + 行字典。
({List<String> header, List<Map<String, String>> rows}) decodeWorkbook(
    Uint8List bytes) {
  final excel = Excel.decodeBytes(bytes);
  final sheetName = excel.tables.keys.first;
  final sheet = excel.tables[sheetName]!;
  final rows = sheet.rows;
  String cellText(dynamic cell) {
    final v = cell?.value;
    if (v == null) return '';
    return v.toString();
  }

  final header = rows.first.map(cellText).toList();
  final out = <Map<String, String>>[];
  for (final row in rows.skip(1)) {
    final map = <String, String>{};
    for (var i = 0; i < header.length; i++) {
      map[header[i]] = i < row.length ? cellText(row[i]) : '';
    }
    out.add(map);
  }
  return (header: header, rows: out);
}

/// 导出包内的机器可读清单（与存档清单同构，见 manifest.dart）。
String manifestForExport(List<ClassRecord> records, List<MediaAsset> media) {
  final byClass = <String, List<Map<String, Object?>>>{};
  for (final m in media) {
    byClass.putIfAbsent(m.classId, () => []).add({
      'fileName': m.fileName,
      'type': m.type,
      'durationSec': m.durationSec,
      'sizeBytes': m.sizeBytes,
      'thumbName': m.thumbName,
    });
  }
  return const JsonEncoder.withIndent('  ').convert({
    'app': '舞记',
    'version': 1,
    'records': [
      for (final r in records)
        {
          'id': r.id,
          'date': r.date,
          'styleId': r.styleId,
          'teacherId': r.teacherId,
          'studioId': r.studioId,
          'styleName': r.styleName,
          'teacherName': r.teacherName,
          'studioName': r.studioName,
          'sessionCount': r.sessionCount,
          'minutesEach': r.minutesEach,
          'note': r.note,
          'createdAt': r.createdAt.toIso8601String(),
          'updatedAt': r.updatedAt.toIso8601String(),
          'media': byClass[r.id] ?? const <Map<String, Object?>>[],
        }
    ],
  });
}
