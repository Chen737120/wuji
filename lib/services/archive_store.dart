import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import 'archive_fs.dart';

/// 存档层门面：media 路径规则、staging 生命周期、manifest 读写、孤儿清扫。
class ArchiveStore implements MediaLocator {
  ArchiveStore(this.fs, {String? manifestRel})
      : manifestRel = manifestRel ?? '舞记数据.json';

  static const _uuid = Uuid();
  String newId() => _uuid.v4();

  final ArchiveFs fs;

  @override
  Future<bool> exists(String rel) => fs.exists(rel);

  /// 存档清单文件名（规格固定）。
  final String manifestRel;

  /// media/YYYY-MM 日期目录uuid.ext
  String mediaRel(DateTime d, String uuid, String ext) {
    final mm = '${d.year}-${d.month.toString().padLeft(2, '0')}';
    return 'media/$mm/$uuid.${ext.toLowerCase()}';
  }

  /// 相册文件先落 staging，登记成功后 commit 成正式路径。
  Future<String> stageFromPath(String srcPath, {required String ext}) async {
    final tempRel = 'media/.staging/${_uuid.v4()}.${ext.toLowerCase()}';
    final bytes = await File(srcPath).readAsBytes();
    await fs.write(tempRel, Stream<List<int>>.value(bytes));
    return tempRel;
  }

  /// 把 staging 文件转正到 media/YYYY-MM 日期目录，返回正式相对路径。
  Future<String> commit(
      String tempRel, DateTime date, String uuid, String ext) async {
    final finalRel = mediaRel(date, uuid, ext);
    await fs.move(tempRel, finalRel);
    return finalRel;
  }

  /// 幂等丢弃 staging 文件。
  Future<void> discard(String tempRel) async {
    await fs.delete(tempRel);
  }

  Future<void> deleteRel(String rel) async {
    await fs.delete(rel);
  }

  Future<void> writeManifest(String json) =>
      fs.write(manifestRel, Stream<List<int>>.value(utf8.encode(json)));

  Future<String?> readManifest() async {
    if (!await fs.exists(manifestRel)) return null;
    final bytes =
        await fs.read(manifestRel).fold<BytesBuilder>(BytesBuilder(), (b, c) {
      b.add(c);
      return b;
    });
    return utf8.decode(bytes.takeBytes());
  }

  Future<Uint8List> readBytes(String rel) async {
    final b =
        await fs.read(rel).fold<BytesBuilder>(BytesBuilder(), (b, c) {
      b.add(c);
      return b;
    });
    return b.takeBytes();
  }

  /// 启动对账：删除无主媒体文件；.staging 整目录清空（规格 §5.2 第 3 条）。
  Future<void> sweepOrphans({required Set<String> referencedRels}) async {
    final all = await fs.list('media/');
    for (final rel in all) {
      if (rel.startsWith('media/.staging/')) {
        await fs.delete(rel);
        continue;
      }
      if (!referencedRels.contains(rel)) {
        await fs.delete(rel);
      }
    }
  }
}
