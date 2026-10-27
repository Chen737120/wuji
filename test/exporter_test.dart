import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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

  test('exportSingleFolder 流式拷贝：大文件字节一致（P1-3）', () async {
    // ~4MB 确定性字节：证明逐块读写不改变内容
    final big = Uint8List(4 * 1024 * 1024);
    for (var i = 0; i < big.length; i++) {
      big[i] = (i * 31 + 7) & 0xff;
    }
    const rel = 'media/2026-09/big.mp4';
    await source.fs.write(rel, Stream.value(big));
    final exporter = Exporter(source);
    final record = rec('r9', '2026-09-30', '爵士');
    await exporter.exportSingleFolder(
      record,
      [
        MediaAsset(
            id: 'm9',
            classId: 'r9',
            type: 'video',
            fileName: rel,
            sizeBytes: big.length,
            createdAt: DateTime(2026, 9, 30)),
      ],
      targetDir: targetDir.path,
    );
    final out = File('${targetDir.path}/2026-09-30_爵士/big.mp4');
    expect(out.existsSync(), isTrue);
    final written = await out.readAsBytes();
    expect(written.length, big.length);
    expect(written, equals(big));
  });

  test('exportSingleFolder 读取中途失败：删除半成品并上抛（P1-3）', () async {
    final exporter = Exporter(ArchiveStore(_FailingReadFs()));
    final record = rec('r8', '2026-09-30', '爵士');
    await expectLater(
      exporter.exportSingleFolder(
        record,
        [
          MediaAsset(
              id: 'm8',
              classId: 'r8',
              type: 'video',
              fileName: 'media/2026-09/broken.mp4',
              sizeBytes: 10,
              createdAt: DateTime(2026, 9, 30)),
        ],
        targetDir: targetDir.path,
      ),
      throwsA(isA<FileSystemException>()),
    );
    final folder = Directory('${targetDir.path}/2026-09-30_爵士');
    expect(folder.existsSync(), isTrue);
    // 半成品 mp4 不得留下（感受.txt 在媒体循环后才写，也不存在）
    expect(folder.listSync().whereType<File>(), isEmpty);
  });
}

/// 读取时先吐一块再抛异常：模拟 SAF 拷贝中途断开。
class _FailingReadFs implements ArchiveFs {
  @override
  Stream<List<int>> read(String rel) async* {
    yield [1, 2, 3];
    throw const FileSystemException('read failed mid-stream');
  }

  @override
  Future<bool> exists(String rel) async => true;

  @override
  Future<void> write(String rel, Stream<List<int>> bytes) async {}

  @override
  Future<void> delete(String rel) async {}

  @override
  Future<void> move(String from, String to) async {}

  @override
  Future<List<String>> list(String prefix) async => const [];

  @override
  Future<int?> freeBytes() async => null;
}
