import 'dart:io';

/// 附件文件是否存在于存档（详情页"文件已丢失"态用；widget 测试可注入假实现）。
abstract class MediaLocator {
  Future<bool> exists(String rel);
}

/// 存档相对路径 → 可被系统分享/存相册的绝对文件路径。
/// LocalFs 直接映射；SAF 模式由设备端先复制到临时文件再返回（T12 接线）。
/// [paced]：SAF 拷贝统一走 readFileBytes 分块（原生 IO 线程读、256KB/块，
/// P2-7）；置 true 时块间额外让出 UI 线程 2ms，供预热等后台批量场景使用。
abstract class MediaPathResolver {
  Future<String?> toAbsolutePath(String rel, {bool paced = false});
}

/// 存档文件夹的文件系统抽象。
/// 测试/降级用 [LocalArchiveFs]（dart:io），设备端用 SafArchiveFs（SAF，T12 接线）。
/// 所有路径均为存档文件夹内的相对路径（正斜杠），如 `media/2026-09/uuid.mp4`。
abstract class ArchiveFs {
  Future<bool> exists(String rel);
  Future<void> write(String rel, Stream<List<int>> bytes);
  Stream<List<int>> read(String rel);
  Future<void> delete(String rel);
  Future<void> move(String from, String to);
  Future<List<String>> list(String prefix);
  Future<int?> freeBytes();
}

class LocalArchiveFs implements ArchiveFs, MediaPathResolver {
  LocalArchiveFs(this.root);

  final String root; // 绝对路径

  File _file(String rel) => File('$root/${rel.replaceAll('/', Platform.pathSeparator)}');
  Directory _dir(String rel) =>
      Directory('$root/${rel.replaceAll('/', Platform.pathSeparator)}');

  @override
  Future<bool> exists(String rel) async => _file(rel).exists();

  @override
  Future<void> write(String rel, Stream<List<int>> bytes) async {
    final f = _file(rel);
    await f.parent.create(recursive: true);
    final sink = f.openWrite(mode: FileMode.write);
    await sink.addStream(bytes);
    await sink.flush();
    await sink.close();
  }

  @override
  Stream<List<int>> read(String rel) => _file(rel).openRead();

  @override
  Future<void> delete(String rel) async {
    final f = _file(rel);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<void> move(String from, String to) async {
    final src = _file(from);
    if (!await src.exists()) return;
    final dst = _file(to);
    await dst.parent.create(recursive: true);
    await src.rename(dst.path);
  }

  @override
  Future<List<String>> list(String prefix) async {
    final out = <String>[];
    final baseDir = _dir(prefix);
    if (!await baseDir.exists()) return out;
    await for (final e in baseDir.list(recursive: true, followLinks: false)) {
      if (e is File) {
        final p = e.path.substring(root.length + 1).replaceAll('\\', '/');
        out.add(p);
      }
    }
    return out..sort();
  }

  @override
  Future<int?> freeBytes() async => null; // Local 实现不提供；设备端由 SAF 查询

  @override
  Future<String?> toAbsolutePath(String rel, {bool paced = false}) async =>
      '$root/${rel.replaceAll('/', Platform.pathSeparator)}';
}
