import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';
import 'package:uuid/uuid.dart';
import 'archive_fs.dart';

String _mimeForExt(String ext) {
  switch (ext.toLowerCase()) {
    case 'mp4':
      return 'video/mp4';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'json':
      return 'application/json';
    case 'txt':
      return 'text/plain';
    default:
      return 'application/octet-stream';
  }
}

/// Android SAF 存档（规格 §5.1）：用户授权的文件夹（默认「下载/舞记」）。
/// 卸载不清空；相对路径映射为 treeUri 下的子路径。
class SafArchiveFs implements ArchiveFs, MediaPathResolver {
  SafArchiveFs({required this.treeUri});

  final SafUtil _saf = SafUtil();
  final SafStream _stream = SafStream();
  static const _uuid = Uuid();

  /// 存档根目录（「舞记」文件夹）的 tree/document uri。
  final String treeUri;

  final _dirCache = <String, String>{}; // rel(dir) → uri

  List<String> _segments(String rel) =>
      rel.split('/').where((s) => s.isNotEmpty).toList();

  /// 逐级 mkdirp，返回目录 uri（带缓存）。
  Future<String> _dirUri(List<String> segments) async {
    var uri = treeUri;
    var rel = '';
    for (final seg in segments) {
      rel = rel.isEmpty ? seg : '$rel/$seg';
      final cached = _dirCache[rel];
      if (cached != null) {
        uri = cached;
        continue;
      }
      final childDoc = await _saf.child(uri, [seg]);
      var childUri = childDoc?.uri;
      if (childUri == null ||
          await _saf.documentFileFromUri(childUri, true) == null) {
        await _saf.mkdirp(uri, [seg]);
        final recreated = await _saf.child(uri, [seg]);
        childUri = recreated?.uri;
      }
      if (childUri == null) {
        throw FileSystemExceptionOnSaf('无法创建存档子目录: $rel');
      }
      uri = childUri;
      _dirCache[rel] = uri;
    }
    return uri;
  }

  Future<String?> _fileUri(String rel) async {
    final segs = _segments(rel);
    if (segs.isEmpty) return null;
    final dirUri =
        segs.length == 1 ? treeUri : await _dirUri(segs.sublist(0, segs.length - 1));
    final childDoc = await _saf.child(dirUri, [segs.last]);
    final childUri = childDoc?.uri;
    if (childUri == null) return null;
    final doc = await _saf.documentFileFromUri(childUri, false);
    return doc == null ? null : childUri;
  }

  @override
  Future<bool> exists(String rel) async => await _fileUri(rel) != null;

  @override
  Future<void> write(String rel, Stream<List<int>> bytes) async {
    final segs = _segments(rel);
    final dirUri = segs.length == 1
        ? treeUri
        : await _dirUri(segs.sublist(0, segs.length - 1));
    final name = segs.last;
    final ext = name.contains('.') ? name.split('.').last : '';
    final data = await bytes.fold<BytesBuilder>(BytesBuilder(), (b, c) {
      b.add(c);
      return b;
    });
    // 存档内同路径覆写：由上层保证语义（commit 只会写新 uuid 路径）
    await _stream.writeFileBytes(
      dirUri,
      name,
      _mimeForExt(ext),
      data.takeBytes(),
      overwrite: true,
    );
  }

  @override
  Stream<List<int>> read(String rel) async* {
    final uri = await _fileUri(rel);
    if (uri == null) throw FileSystemExceptionOnSaf('文件不存在: $rel');
    await for (final chunk in await _stream.readFileStream(uri)) {
      yield chunk;
    }
  }

  @override
  Future<void> delete(String rel) async {
    final uri = await _fileUri(rel);
    if (uri != null) {
      await _saf.delete(uri, false);
    }
  }

  @override
  Future<void> move(String from, String to) async {
    if (!await exists(from)) return;
    await write(to, read(from));
    await delete(from);
  }

  @override
  Future<List<String>> list(String prefix) async {
    final out = <String>[];
    final segs = _segments(prefix);
    final baseUri = segs.isEmpty ? treeUri : await _dirUri(segs);
    final baseRel = segs.join('/');
    Future<void> walk(String dirUri, String rel) async {
      final children = await _saf.list(dirUri);
      for (final c in children) {
        final childRel = rel.isEmpty ? c.name : '$rel/${c.name}';
        if (c.isDir) {
          await walk(c.uri, childRel);
        } else {
          out.add(childRel);
        }
      }
    }

    await walk(baseUri, baseRel);
    return out..sort();
  }

  @override
  Future<int?> freeBytes() async => null; // SAF 免费空间查询不在本包范围；保存前警告降级

  @override
  Future<String?> toAbsolutePath(String rel) async {
    // SAF 没有真实路径：复制到临时文件，供分享/播放/存相册使用。
    // 不用 saf_stream 的 copyToLocalFile——对 tree-document uri 会挂起；
    // 走 read()（readFileStream，导出/manifest 同款原语，已验证可靠）。
    final uri = await _fileUri(rel);
    if (uri == null) return null;
    final tmp = await getTemporaryDirectory();
    final name = _segments(rel).last;
    final dest = '${tmp.path}/share/${_uuid.v4()}-$name';
    final f = File(dest);
    await f.parent.create(recursive: true);
    final sink = f.openWrite();
    try {
      await sink.addStream(read(rel));
      await sink.flush();
    } finally {
      await sink.close();
    }
    return dest;
  }
}

class FileSystemExceptionOnSaf implements Exception {
  FileSystemExceptionOnSaf(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 首启引导（规格 §5.1）：预定位「下载」，确认后自动建「舞记」子文件夹。
/// 返回「舞记」文件夹的 uri（作为存档根）；取消返回 null。
Future<String?> pickAndEnsureWujiArchive() async {
  final saf = SafUtil();
  const downloadHint =
      'content://com.android.externalstorage.documents/document/primary%3ADownload';
  String? picked;
  try {
    final doc = await saf.pickDirectory(
      initialUri: downloadHint,
      persistablePermission: true,
      writePermission: true,
    );
    picked = doc?.uri;
  } catch (_) {
    final doc =
        await saf.pickDirectory(persistablePermission: true, writePermission: true);
    picked = doc?.uri;
  }
  if (picked == null) return null;
  // 确保「舞记」子文件夹存在（已存在则直接用）
  final wujiDoc = await saf.child(picked, ['舞记']);
  var wujiUri = wujiDoc?.uri;
  if (wujiUri == null ||
      await saf.documentFileFromUri(wujiUri, true) == null) {
    await saf.mkdirp(picked, ['舞记']);
    final recreated = await saf.child(picked, ['舞记']);
    wujiUri = recreated?.uri;
  }
  return wujiUri;
}
