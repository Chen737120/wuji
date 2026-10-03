import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart' as ar;
import 'package:archive/archive_io.dart';
import '../data/db.dart';
import 'archive_store.dart';
import 'export_naming.dart';

class ExportCancelled implements Exception {
  @override
  String toString() => 'ExportCancelled';
}

/// 导出执行器（规格 §6）：整包 zip（磁盘流式，不整包占内存）/ 单课文件夹。
class Exporter {
  Exporter(this._store);

  final ArchiveStore _store;

  /// 整包导出。结构：舞记数据.json ＋ 逐课文件夹（媒体＋感受.txt）＋ 舞记总表.xlsx。
  /// [cancelled] 返回 true 时删除半成品并抛 [ExportCancelled]。
  Future<void> exportZip(
    List<ClassRecord> records,
    List<MediaAsset> media, {
    required String targetPath,
    void Function(int done, int total)? onProgress,
    bool Function()? cancelled,
  }) async {
    final names = assignFolderNames(records);
    final byClass = <String, List<MediaAsset>>{};
    for (final m in media) {
      byClass.putIfAbsent(m.classId, () => []).add(m);
    }

    final encoder = ZipFileEncoder()..create(targetPath);
    try {
      // 1) 清单（机器可读，导入回血用）
      encoder.addArchiveFile(ar.ArchiveFile.string(
          '舞记数据.json', manifestForExport(records, media)));

      // 2) 逐课：媒体（保留原文件名，重名加序号）＋ 感受.txt
      var done = 0;
      final total = records.length + 2;
      final usedMediaNames = <String, int>{};
      for (final r in records) {
        final folder = names[r.id] ?? folderBaseName(r);
        for (final m in byClass[r.id] ?? const <MediaAsset>[]) {
          final original = m.fileName.split('/').last;
          final key = '$folder/$original';
          final n = (usedMediaNames[key] ?? 0) + 1;
          usedMediaNames[key] = n;
          final name = n == 1 ? original : _withSeq(original, n);
          final bytes = await _store.readBytes(m.fileName);
          encoder.addArchiveFile(
              ar.ArchiveFile('$folder/$name', bytes.length, bytes));
        }
        encoder.addArchiveFile(
            ar.ArchiveFile.string('$folder/感受.txt', feelingsTxt(r)));
        done++;
        onProgress?.call(done, total);
        if (cancelled?.call() ?? false) throw ExportCancelled();
      }

      // 2.5) 封面：thumbs/<uuid>.jpg 原相对路径入包（清单 thumbName 可直接命中，
      //      导入后封面不丢）
      final thumbNames = <String>{
        for (final m in media)
          if (m.thumbName != null) m.thumbName!,
      };
      for (final tn in thumbNames) {
        if (!await _store.exists(tn)) continue;
        final bytes = await _store.readBytes(tn);
        encoder.addArchiveFile(ar.ArchiveFile(tn, bytes.length, bytes));
      }

      // 3) 总表
      final counts = <String, int>{};
      for (final r in records) {
        counts[r.id] = (byClass[r.id] ?? const []).length;
      }
      final workbook = buildWorkbook(records, counts, names);
      encoder.addArchiveFile(
          ar.ArchiveFile('舞记总表.xlsx', workbook.length, workbook));
      done++;
      onProgress?.call(done, total);
      await encoder.close();
    } catch (e) {
      try {
        await encoder.close();
      } catch (_) {}
      final f = File(targetPath);
      if (f.existsSync()) f.deleteSync();
      rethrow;
    }
  }

  /// 单课导出（不打 zip）：目标目录下建「日期_舞种[_老师]」文件夹，放媒体＋感受.txt。
  Future<void> exportSingleFolder(
    ClassRecord record,
    List<MediaAsset> media, {
    required String targetDir,
  }) async {
    final folder = folderBaseName(record);
    final dir = Directory('$targetDir/$folder');
    await dir.create(recursive: true);
    final used = <String, int>{};
    for (final m in media) {
      final name = m.fileName.split('/').last;
      final n = (used[name] ?? 0) + 1;
      used[name] = n;
      final finalName = n == 1 ? name : _withSeq(name, n);
      final bytes = await _store.readBytes(m.fileName);
      await File('${dir.path}/$finalName').writeAsBytes(bytes);
    }
    await File('${dir.path}/感受.txt')
        .writeAsString(feelingsTxt(record), encoding: utf8);
  }

  String _withSeq(String fileName, int n) {
    final dot = fileName.lastIndexOf('.');
    final base = dot < 0 ? fileName : fileName.substring(0, dot);
    final ext = dot < 0 ? '' : fileName.substring(dot);
    return '$base($n)$ext';
  }
}
