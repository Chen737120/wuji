import 'dart:convert';
import '../data/db.dart' show ClassRecord, MediaAsset;

/// 舞记数据.json（存档清单）：机器可读、全量重建依据（规格 §5.1/§7）。
/// schema version 1；坏条目跳过并收集错误，绝不让导入半途污染库。

class ManifestMedia {
  const ManifestMedia({
    required this.fileName,
    required this.type,
    this.durationSec,
    this.sizeBytes = 0,
    this.thumbName,
  });

  final String fileName;
  final String type; // video | image
  final int? durationSec;
  final int sizeBytes;
  final String? thumbName;

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'type': type,
        'durationSec': durationSec,
        'sizeBytes': sizeBytes,
        'thumbName': thumbName,
      };

  static ManifestMedia fromJson(Map<String, dynamic> j) => ManifestMedia(
        fileName: j['fileName'] as String,
        type: (j['type'] ?? 'video') as String,
        durationSec: j['durationSec'] as int?,
        sizeBytes: (j['sizeBytes'] ?? 0) as int,
        thumbName: j['thumbName'] as String?,
      );
}

class ManifestEntry {
  const ManifestEntry({
    required this.id,
    required this.date, // yyyy-MM-dd（可解析才收）
    this.styleId,
    this.teacherId,
    this.studioId,
    this.styleName,
    this.teacherName,
    this.studioName,
    required this.sessionCount,
    required this.minutesEach,
    this.note,
    this.createdAt,
    this.updatedAt,
    this.media = const [],
  });

  final String id;
  final String date;
  final String? styleId;
  final String? teacherId;
  final String? studioId;
  final String? styleName;
  final String? teacherName;
  final String? studioName;
  final int sessionCount;
  final int minutesEach;
  final String? note;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<ManifestMedia> media;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'styleId': styleId,
        'teacherId': teacherId,
        'studioId': studioId,
        'styleName': styleName,
        'teacherName': teacherName,
        'studioName': studioName,
        'sessionCount': sessionCount,
        'minutesEach': minutesEach,
        'note': note,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'media': media.map((m) => m.toJson()).toList(),
      };
}

String buildManifestJson(List<ClassRecord> records, List<MediaAsset> media) {
  final byClass = <String, List<MediaAsset>>{};
  for (final m in media) {
    byClass.putIfAbsent(m.classId, () => []).add(m);
  }
  final payload = {
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
          'media': [
            for (final m in byClass[r.id] ?? const <MediaAsset>[])
              {
                'fileName': m.fileName,
                'type': m.type,
                'durationSec': m.durationSec,
                'sizeBytes': m.sizeBytes,
                'thumbName': m.thumbName,
              }
          ],
        }
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(payload);
}

class ParseResult {
  const ParseResult({required this.entries, required this.errors});
  final List<ManifestEntry> entries;
  final List<String> errors; // 人读的错误描述（跳过的条目）
}

final _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// 宽松解析：日期不可解析/节数越界的条目跳过并记入 errors（Review Focus #4）。
ParseResult parseManifest(String json) {
  final errors = <String>[];
  final entries = <ManifestEntry>[];
  late final Map<String, dynamic> root;
  try {
    root = jsonDecode(json) as Map<String, dynamic>;
  } on FormatException catch (e) {
    return ParseResult(entries: entries, errors: ['JSON 解析失败: $e']);
  }
  final records = (root['records'] as List? ?? const []);
  for (final raw in records) {
    if (raw is! Map<String, dynamic>) {
      errors.add('跳过非对象条目');
      continue;
    }
    final id = raw['id'] as String?;
    final date = raw['date'] as String?;
    if (id == null || id.isEmpty || date == null || !_dateRe.hasMatch(date)) {
      errors.add('跳过条目（id=$id, date=$date）：id/日期缺失或日期格式非法');
      continue;
    }
    final parsedDate = DateTime.tryParse(date);
    if (parsedDate == null ||
        parsedDate.year.toString().padLeft(4, '0') != date.substring(0, 4) ||
        parsedDate.month != int.parse(date.substring(5, 7)) ||
        parsedDate.day != int.parse(date.substring(8, 10))) {
      errors.add('跳过条目 $id：日期数值非法（$date）');
      continue;
    }
    final sessionCount = raw['sessionCount'] is int
        ? raw['sessionCount'] as int
        : int.tryParse('${raw['sessionCount']}') ?? 1;
    final minutesEach = raw['minutesEach'] is int
        ? raw['minutesEach'] as int
        : int.tryParse('${raw['minutesEach']}') ?? 90;
    if (sessionCount < 1 || sessionCount > 10 || minutesEach < 50 || minutesEach > 180) {
      errors.add('跳过条目 $id：节数/时长越界（$sessionCount 节 × $minutesEach 分钟）');
      continue;
    }
    final mediaList = <ManifestMedia>[];
    for (final m in (raw['media'] as List? ?? const [])) {
      if (m is Map<String, dynamic> && m['fileName'] is String) {
        try {
          mediaList.add(ManifestMedia.fromJson(m));
        } catch (_) {
          errors.add('跳过条目 $id 的一个坏附件');
        }
      } else {
        errors.add('跳过条目 $id 的一个坏附件');
      }
    }
    DateTime? dt(String? s) => s == null ? null : DateTime.tryParse(s);
    entries.add(ManifestEntry(
      id: id,
      date: date,
      styleId: raw['styleId'] as String?,
      teacherId: raw['teacherId'] as String?,
      studioId: raw['studioId'] as String?,
      styleName: raw['styleName'] as String?,
      teacherName: raw['teacherName'] as String?,
      studioName: raw['studioName'] as String?,
      sessionCount: sessionCount,
      minutesEach: minutesEach,
      note: raw['note'] as String?,
      createdAt: dt(raw['createdAt'] as String?),
      updatedAt: dt(raw['updatedAt'] as String?),
      media: mediaList,
    ));
  }
  return ParseResult(entries: entries, errors: errors);
}
