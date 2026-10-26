import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/services/archive_fs.dart';
import 'package:wuji/services/archive_store.dart';
import 'package:wuji/services/manifest.dart';
import 'package:wuji/data/db.dart' show ClassRecord, MediaAsset;

/// 只记录写入数据/分块数的假存档后端（验证 stageFromPath 是否流式）。
class _RecordingFs implements ArchiveFs {
  final data = BytesBuilder();
  var chunkCount = 0;
  var totalBytes = 0;

  @override
  Future<void> write(String rel, Stream<List<int>> bytes) async {
    await for (final c in bytes) {
      chunkCount++;
      totalBytes += c.length;
      data.add(c);
    }
  }

  @override
  Future<bool> exists(String rel) async => false;
  @override
  Stream<List<int>> read(String rel) => const Stream.empty();
  @override
  Future<void> delete(String rel) async {}
  @override
  Future<void> move(String from, String to) async {}
  @override
  Future<List<String>> list(String prefix) async => const [];
  @override
  Future<int?> freeBytes() async => null;
}

void main() {
  late Directory tmp;
  late ArchiveStore store;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wuji_test');
    store = ArchiveStore(LocalArchiveFs(tmp.path));
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('mediaRel follows YYYY-MM layout', () {
    expect(store.mediaRel(DateTime(2026, 9, 30), 'abc', 'mp4'),
        'media/2026-09/abc.mp4');
  });

  test('stage/commit/discard lifecycle', () async {
    final src = File('${tmp.path}/src.bin')..writeAsBytesSync([1, 2, 3]);
    final tempRel = await store.stageFromPath(src.path, ext: 'mp4');
    expect(tempRel.startsWith('media/.staging/'), isTrue);
    final finalRel =
        await store.commit(tempRel, DateTime(2026, 10, 2), 'xyz', 'mp4');
    expect(finalRel, 'media/2026-10/xyz.mp4');
    expect(await store.fs.exists(finalRel), isTrue);
    expect(await store.fs.exists(tempRel), isFalse);
    expect(await File('${tmp.path}/$finalRel').readAsBytes(), [1, 2, 3]);
    await store.discard(tempRel); // 幂等：文件已不存在也不抛
  });

  test('stageFromPath 流式拷贝：大文件分块写入，不整读进内存（OOM 回归）', () async {
    final rec = _RecordingFs();
    final streaming = ArchiveStore(rec);
    final size = 2 * 1024 * 1024; // 2MB：openRead 默认 64KB/块 → 必须多块
    final bytes = Uint8List(size);
    for (var i = 0; i < size; i++) {
      bytes[i] = i & 0xFF;
    }
    final src = File('${tmp.path}/big.bin')..writeAsBytesSync(bytes);

    final tempRel = await streaming.stageFromPath(src.path, ext: 'mp4');
    expect(tempRel.startsWith('media/.staging/'), isTrue);
    // 2026-10-26 真机 394MB 视频保存 OOM：旧实现 readAsBytes 整读后单块写出
    expect(rec.chunkCount, greaterThan(1),
        reason: 'stageFromPath 必须流式分块，不能整文件一次性读入');
    expect(rec.totalBytes, size);
    expect(rec.data.takeBytes(), bytes);
  });

  test('manifest write/read roundtrip', () async {
    await store.writeManifest('{"app":"舞记","version":1,"records":[]}');
    expect(await store.readManifest(), contains('舞记'));
  });

  test('orphan sweep keeps formal-named files (user data), clears staging only', () async {
    final keep = 'media/2026-10/keep.mp4';
    final userRenamed = 'media/2026-10/orphan.mp4';
    await store.fs.write(keep, Stream.value([1]));
    await store.fs.write(userRenamed, Stream.value([1]));
    await store.fs.write('media/.staging/x.part', Stream.value([2]));
    await store.sweepOrphans(referencedRels: {keep});
    expect(await store.fs.exists(keep), isTrue);
    expect(await store.fs.exists(userRenamed), isTrue);
    expect(await store.fs.exists('media/.staging/x.part'), isFalse);
  });

  test('orphan sweep clears staging entirely', () async {
    await store.fs.write('media/.staging/x.part', Stream.value([9]));
    await store.sweepOrphans(referencedRels: {});
    expect(await store.fs.exists('media/.staging/x.part'), isFalse);
  });

  test('manifest roundtrip with real rows', () async {
    final now = DateTime(2026, 9, 30, 12);
    final r = ClassRecord(
      id: 'r1',
      date: '2026-09-30',
      styleName: '爵士',
      teacherName: '小鹿',
      sessionCount: 2,
      minutesEach: 90,
      note: '今天很棒\n第二行',
      createdAt: now,
      updatedAt: now,
    );
    final m = MediaAsset(
      id: 'm1',
      classId: 'r1',
      type: 'video',
      fileName: 'media/2026-09/abc.mp4',
      durationSec: 95,
      sizeBytes: 12345,
      createdAt: now,
    );
    final json = buildManifestJson([r], [m]);
    await store.writeManifest(json);
    final parsed = parseManifest(await store.readManifest() ?? '');
    expect(parsed.errors, isEmpty);
    expect(parsed.entries, hasLength(1));
    final e = parsed.entries.single;
    expect(e.id, 'r1');
    expect(e.styleName, '爵士');
    expect(e.sessionCount, 2);
    expect(e.note, '今天很棒\n第二行');
    expect(e.media.single.fileName, 'media/2026-09/abc.mp4');
    expect(e.media.single.durationSec, 95);
  });

  test('parseManifest skips bad dates and collects errors', () {
    const json = '{"app":"舞记","version":1,"records":['
        '{"id":"ok1","date":"2026-09-30","sessionCount":1,"minutesEach":90,"media":[]},'
        '{"id":"bad1","date":"2099-13-40","sessionCount":1,"minutesEach":90,"media":[]},'
        '{"id":"bad2","date":"2026-01-01","sessionCount":99,"minutesEach":90,"media":[]}]}';
    final parsed = parseManifest(json);
    expect(parsed.entries, hasLength(1));
    expect(parsed.entries.single.id, 'ok1');
    expect(parsed.errors, hasLength(2));
  });
}
