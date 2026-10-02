import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/data/db.dart';
import 'package:wuji/services/archive_fs.dart';
import 'package:wuji/services/archive_store.dart';
import 'package:wuji/services/exporter.dart';

ClassRecord rec(String id, String date, String style, {String? note}) {
  return ClassRecord(
    id: id,
    date: date,
    styleName: style,
    sessionCount: 1,
    minutesEach: 90,
    note: note,
    createdAt: DateTime.parse(date),
    updatedAt: DateTime.parse(date),
  );
}

void main() {
  late Directory tmp;
  late ArchiveStore source; // 存档（含媒体）
  late Directory targetDir; // 导出目标

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wuji_export');
    source = ArchiveStore(LocalArchiveFs(tmp.path));
    // 存两节课、4 个媒体文件
    for (final (i, r) in [
      ('r1', '2026-09-30', '爵士', '很棒\n正文'),
      ('r2', '2026-09-24', '韩舞', null),
    ].indexed) {
      final folder = source.mediaRel(DateTime.parse(r.$2), 'u$i', 'mp4');
      await source.fs.write(folder, Stream.value([1, 2, 3, 4]));
      await source.fs.write(folder.replaceAll('.mp4', '_t.jpg'), Stream.value([9]));
    }
    targetDir = Directory('${tmp.path}/out')..createSync();
  });

  tearDown(() async {
    for (var i = 0; i < 5; i++) {
      try {
        await tmp.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
  });

  test('exportZip produces manifest, workbook, folders, media and txt',
      () async {
    final records = [rec('r1', '2026-09-30', '爵士', note: '很棒\n正文'), rec('r2', '2026-09-24', '韩舞')];
    final media = [
      MediaAsset(id: 'm1', classId: 'r1', type: 'video', fileName: 'media/2026-09/u0.mp4', sizeBytes: 4, createdAt: DateTime(2026, 9, 30)),
      MediaAsset(id: 'm2', classId: 'r1', type: 'image', fileName: 'media/2026-09/u0_t.jpg', sizeBytes: 1, createdAt: DateTime(2026, 9, 30)),
      MediaAsset(id: 'm3', classId: 'r2', type: 'video', fileName: 'media/2026-09/u1.mp4', sizeBytes: 4, createdAt: DateTime(2026, 9, 24)),
      MediaAsset(id: 'm4', classId: 'r2', type: 'image', fileName: 'media/2026-09/u1_t.jpg', sizeBytes: 1, createdAt: DateTime(2026, 9, 24)),
    ];
    final exporter = Exporter(source);
    final targetPath = '${targetDir.path}/舞记备份-2026-09-30.zip';
    var progressCalls = 0;
    await exporter.exportZip(
      records,
      media,
      targetPath: targetPath,
      onProgress: (_, _) => progressCalls++,
    );

    final zipBytes = await File(targetPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final names = archive.files.map((f) => f.name).toList();
    expect(names, contains('舞记数据.json'));
    expect(names, contains('舞记总表.xlsx'));
    expect(names.where((n) => n.startsWith('2026-09-30_爵士/') && n.endsWith('.mp4')),
        hasLength(1));
    expect(names.contains('2026-09-30_爵士/感受.txt'), isTrue);
    expect(names.contains('2026-09-24_韩舞/感受.txt'), isTrue);
    expect(progressCalls, greaterThan(0));

    // txt 内容正确
    final txtEntry =
        archive.files.firstWhere((f) => f.name == '2026-09-30_爵士/感受.txt');
    final txt = utf8.decode(txtEntry.content as List<int>);
    expect(txt.contains('很棒'), isTrue);
  });

  test('exportZip cancellation deletes half-built target', () async {
    final records = [rec('r1', '2026-09-30', '爵士')];
    final media = const <MediaAsset>[];
    final exporter = Exporter(source);
    final targetPath = '${targetDir.path}/cancelled.zip';
    await expectLater(
      exporter.exportZip(records, media,
          targetPath: targetPath, cancelled: () => true),
      throwsA(isA<ExportCancelled>()),
    );
    expect(File(targetPath).existsSync(), isFalse);
  });

  test('exportSingleFolder writes media + txt without zip', () async {
    final records = [rec('r1', '2026-09-30', '爵士', note: '很棒')];
    final media = [
      MediaAsset(id: 'm1', classId: 'r1', type: 'video', fileName: 'media/2026-09/u0.mp4', sizeBytes: 4, createdAt: DateTime(2026, 9, 30)),
    ];
    final exporter = Exporter(source);
    await exporter.exportSingleFolder(records.first, media,
        targetDir: targetDir.path);
    final folder = Directory('${targetDir.path}/2026-09-30_爵士');
    expect(folder.existsSync(), isTrue);
    expect(folder.listSync().whereType<File>().where((f) => f.path.endsWith('.mp4')),
        hasLength(1));
    expect(File('${folder.path}/感受.txt').existsSync(), isTrue);
    expect(targetDir.listSync().whereType<File>().any((f) => f.path.endsWith('.zip')),
        isFalse);
  });
}
