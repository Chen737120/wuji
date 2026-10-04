import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';
import '../data/app_repository.dart';
import '../data/taxonomy_repo.dart';
import '../reload_bus.dart';
import '../services/archive_fs.dart';
import '../services/archive_store.dart';
import '../services/importer.dart';
import '../services/manifest.dart';
import '../services/saf_archive.dart';
import '../theme.dart';

/// 导入备份（规格 §7）：选 zip 或文件夹 → 预览 → 执行 → 报告。
class ImportPage extends StatefulWidget {
  const ImportPage({super.key});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  bool _busy = false;
  String _status = '';
  ImportPlan? _plan;
  String? _planWarning;
  ArchiveFs? _pendingSourceFs;

  AppRepository get _repo => context.read<AppRepository>();
  ArchiveStore get _store => context.read<ArchiveStore>();
  TaxonomyRepo get _taxonomy => TaxonomyRepo(_repo.db);

  Future<void> _pickZip() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final saf = SafUtil();
      final doc = await saf.pickFile(mimeTypes: const ['application/zip']);
      if (doc == null) {
        setState(() => _busy = false);
        return;
      }
      setState(() => _status = '读取压缩包…');
      final tmp = await getTemporaryDirectory();
      final localZip =
          '${tmp.path}/wuji-import-${DateTime.now().millisecondsSinceEpoch}.zip';
      // 不用 saf_stream 的 copyToLocalFile（部分 uri 形态会挂起），流式自拷
      final zipSink = File(localZip).openWrite();
      try {
        await zipSink.addStream(await SafStream().readFileStream(doc.uri));
        await zipSink.flush();
      } finally {
        await zipSink.close();
      }
      final extractDir = Directory('${tmp.path}/wuji-import-extract');
      if (extractDir.existsSync()) extractDir.deleteSync(recursive: true);
      await extractArchiveToDisk(
          ZipDecoder().decodeBuffer(InputFileStream(localZip)), extractDir.path);
      await _prepareSource(LocalArchiveFs(extractDir.path));
    } catch (e) {
      setState(() {
        _busy = false;
        _status = '读取失败：$e';
      });
    }
  }

  Future<void> _pickFolder() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final saf = SafUtil();
      final doc = await saf.pickDirectory(persistablePermission: true);
      if (doc == null) {
        setState(() => _busy = false);
        return;
      }
      setState(() => _status = '读取文件夹…');
      await _prepareSource(SafArchiveFs(treeUri: doc.uri));
    } catch (e) {
      setState(() {
        _busy = false;
        _status = '读取失败：$e';
      });
    }
  }

  Future<void> _prepareSource(ArchiveFs sourceFs) async {
    _pendingSourceFs = sourceFs;
    final manifestJson = await sourceFs.exists('舞记数据.json')
        ? await _readAllText(sourceFs, '舞记数据.json')
        : null;
    List<ManifestEntry> entries;
    String warning = '';
    if (manifestJson != null) {
      final parsed = parseManifest(manifestJson);
      entries = parsed.entries;
      if (parsed.errors.isNotEmpty) {
        warning = '跳过 ${parsed.errors.length} 条异常数据';
      }
    } else {
      final all = await sourceFs.list('');
      final folders = <String>{};
      for (final rel in all) {
        final segs = rel.split('/');
        if (segs.length > 1) folders.add(segs.first);
      }
      entries = parseFolderFallback(folders.toList());
      if (entries.isEmpty) {
        setState(() {
          _busy = false;
          _status = '没有找到舞记的备份内容';
        });
        return;
      }
      warning = '未找到清单文件，按文件夹名识别（节数/时长按默认值）';
    }
    final existing = await _repo.allRecords();
    final plan = planImport(entries, existing);
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _planWarning = warning;
      _busy = false;
      _status = '';
    });
  }

  Future<String> _readAllText(ArchiveFs fs, String rel) async {
    final bytes = await _readAllBytes(fs, rel);
    // 清单/感受均为 UTF-8；fromCharCodes 会把多字节中文拆成乱码
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<List<int>> _readAllBytes(ArchiveFs fs, String rel) async {
    final b = <int>[];
    await for (final c in fs.read(rel)) {
      b.addAll(c);
    }
    return b;
  }

  Future<void> _confirm() async {
    if (_plan == null || _plan!.isEmpty) return;
    final total =
        _plan!.toCreate.fold<int>(0, (a, e) => a + e.media.length) +
            _plan!.toPatch.fold<int>(0, (a, e) => a + e.media.length);
    setState(() {
      _busy = true;
      _status = total > 0
          ? '导入中 0/$total…（大视频需要一些时间，请保持屏幕常亮）'
          : '导入中…';
    });
    try {
      final report = await executeImport(_plan!,
          sourceFs: _pendingSourceFs!,
          archive: _store,
          repo: _repo,
          taxonomy: _taxonomy, onProgress: (done, t) {
        if (mounted) {
          setState(() => _status = '导入中 $done/$t…（请保持屏幕常亮）');
        }
      });
      ReloadBus.instance.bump();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(report.toString())));
      Navigator.pop(context);
    } catch (e) {
      setState(() {
        _busy = false;
        _status = '导入失败：$e（可重试，已成功的部分会自动跳过）';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final plan = _plan;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
            onPressed: () => Navigator.pop(context)),
        centerTitle: true,
        title: const Text('导入备份',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) ...[
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(height: 10),
            Center(
                child: Text(_status,
                    style:
                        TextStyle(fontSize: 12, color: AppColors.secondary))),
          ] else if (plan == null) ...[
            const Text('选择要导入的备份',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('支持「导出」生成的 zip 包，或解压后的文件夹。\n导入会合并进现有记录：已有的课只补回视频，不会重复。',
                style: TextStyle(fontSize: 11, color: AppColors.secondary, height: 1.7)),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              onPressed: _pickZip,
              child: const Text('选择 zip 包'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.hairline),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              onPressed: _pickFolder,
              child: const Text('选择文件夹（含重装后重连存档）',
                  style: TextStyle(fontSize: 13)),
            ),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_status,
                  style: TextStyle(fontSize: 11, color: AppColors.secondary)),
            ],
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan.describe(),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  if (_planWarning!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(_planWarning!,
                        style: TextStyle(
                            fontSize: 10, color: AppColors.secondary)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              onPressed: plan.isEmpty ? null : _confirm,
              child: const Text('开始导入'),
            ),
          ],
        ],
      ),
    );
  }
}
