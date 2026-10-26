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
  ///
  /// **流式拷贝**：大视频（真机实测 394MB）整文件 `readAsBytes` 会直接
  /// OOM（2026-10-26 用户报告「保存失败」的表层文案，logcat 实证
  /// `保存失败: Out of Memory`）。`openRead` 按块交给后端流式写。
  Future<String> stageFromPath(String srcPath, {required String ext}) async {
    final tempRel = 'media/.staging/${_uuid.v4()}.${ext.toLowerCase()}';
    await fs.write(tempRel, File(srcPath).openRead());
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

  /// 启动对账（终审 C3 收窄）：只清 `media/.staging/`（保存流程的确定残留区）。
  /// 存档里正式命名但未被 DB 引用的文件一律不动 —— 那可能是用户改名/放入的
  /// 文件，App 替用户删除违背「手动删才是真删」的约定；硬崩溃残留的正式命名
  /// 孤儿文件宁留勿删（可手动清理）。
  Future<void> sweepOrphans({required Set<String> referencedRels}) async {
    final all = await fs.list('media/');
    for (final rel in all) {
      if (rel.startsWith('media/.staging/')) {
        await fs.delete(rel);
      }
    }
  }
}
