import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';
import 'package:share_plus/share_plus.dart';
import '../data/app_repository.dart' show ClassSaver;
import '../data/db.dart';
import '../services/archive_store.dart';
import '../services/exporter.dart';
import '../services/stats.dart' show StatRange;
import '../theme.dart';

/// 按时间段导出预览页（规格 §3.7）：筛选 → 封面预览列表 → 合计 → 导出。
class ExportPreviewPage extends StatefulWidget {
  const ExportPreviewPage({super.key});

  @override
  State<ExportPreviewPage> createState() => _ExportPreviewPageState();
}

class _ExportPreviewPageState extends State<ExportPreviewPage> {
  List<ClassRecord> _all = [];
  Map<String, List<MediaAsset>> _media = {};
  StatRange _range = StatRange.all;
  DateTime? _customStart;
  DateTime? _customEnd;
  bool _loaded = false;
  bool _exporting = false;
  String _progress = '';

  ClassSaver get _saver => context.read<ClassSaver>();
  ArchiveStore get _store => context.read<ArchiveStore>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await _saver.allRecords();
    final media = <String, List<MediaAsset>>{};
    for (final r in records) {
      media[r.id] = await _saver.mediaOf(r.id);
    }
    if (!mounted) return;
    setState(() {
      _all = records;
      _media = media;
      _loaded = true;
    });
  }

  List<ClassRecord> get _filtered {
    final now = DateTime.now();
    bool inRange(DateTime d) {
      switch (_range) {
        case StatRange.all:
          return true;
        case StatRange.last30:
          final start = DateTime(now.year, now.month, now.day)
              .subtract(const Duration(days: 29));
          return !d.isBefore(start);
        case StatRange.last365:
          final start = DateTime(now.year, now.month, now.day)
              .subtract(const Duration(days: 364));
          return !d.isBefore(start);
        case StatRange.custom:
          final dayStart = DateTime(_customStart!.year, _customStart!.month,
              _customStart!.day);
          final dayEnd = DateTime(_customEnd!.year, _customEnd!.month,
              _customEnd!.day, 23, 59, 59);
          return !d.isBefore(dayStart) && !d.isAfter(dayEnd);
      }
    }

    return _all.where((r) => inRange(r.dateAsDateTime)).toList();
  }

  (int, int, int) get _totals {
    final records = _filtered;
    var attachments = 0;
    var bytes = 0;
    for (final r in records) {
      final m = _media[r.id] ?? const <MediaAsset>[];
      attachments += m.length;
      bytes += m.fold<int>(0, (a, x) => a + x.sizeBytes);
    }
    return (records.length, attachments, bytes);
  }

  Future<void> _pickCustomRange() async {
    final initial = DateTime.now();
    final first = await showDatePicker(
        context: context,
        initialDate: initial.subtract(const Duration(days: 30)),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: '选择开始日期');
    if (first == null || !mounted) return;
    final last = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: first,
        lastDate: DateTime(2100),
        helpText: '选择结束日期');
    if (last == null || !mounted) return;
    setState(() {
      _customStart = first;
      _customEnd = last;
      _range = StatRange.custom;
    });
  }

  Future<void> _export() async {
    if (_exporting) return;
    final records = _filtered;
    if (records.isEmpty) return;
    setState(() {
      _exporting = true;
      _progress = '准备中…';
    });
    try {
      final media = <MediaAsset>[for (final r in records) ...(_media[r.id] ?? const <MediaAsset>[])];
      final exporter = Exporter(_store);
      final tmp = await getTemporaryDirectory();
      final localZip =
          '${tmp.path}/舞记备份-${DateTime.now().toIso8601String().substring(0, 10)}.zip';
      await exporter.exportZip(records, media, targetPath: localZip,
          onProgress: (done, total) {
        if (mounted) setState(() => _progress = '打包中 $done/$total');
      });
      // 优先：让用户选目标文件夹（SAF），复制进去；取消则走系统分享
      String? doneMsg;
      try {
        final saf = SafUtil();
        final doc = await saf.pickDirectory(
            persistablePermission: false, writePermission: true);
        if (doc?.uri != null) {
          await SafStream().pasteLocalFile(localZip, doc!.uri,
              localZip.split(Platform.pathSeparator).last, 'application/zip',
              overwrite: true);
          doneMsg = '已保存到所选文件夹';
        }
      } catch (_) {}
      doneMsg ??= '已打包，选择保存位置';
      final file = XFile(localZip);
      if (doneMsg.startsWith('已打包')) {
        await SharePlus.instance.share(ShareParams(files: [file], text: '舞记备份'));
      } else {
        try {
          await File(localZip).delete();
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(doneMsg)));
        Navigator.pop(context);
      }
    } on ExportCancelled {
      if (mounted) setState(() => _exporting = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$e')));
        setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final records = _filtered;
    final (nRecords, nMedia, bytes) = _totals;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
            onPressed: () => Navigator.pop(context)),
        centerTitle: true,
        title: const Text('按时间段导出',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Row(
                    children: [
                      for (final (label, range) in [
                        ('全部', StatRange.all),
                        ('近1月', StatRange.last30),
                        ('近1年', StatRange.last365),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: GestureDetector(
                            onTap: () => setState(() => _range = range),
                            child: _chip(label, _range == range),
                          ),
                        ),
                      GestureDetector(
                        onTap: _pickCustomRange,
                        child: _chip('自定义', _range == StatRange.custom),
                      ),
                    ],
                  ),
                ),
                if (_range == StatRange.custom && _customStart != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                          '${_fmtDate(_customStart!)} ～ ${_fmtDate(_customEnd!)}',
                          style: TextStyle(fontSize: 10, color: AppColors.faint)),
                    ),
                  ),
                Expanded(
                  child: records.isEmpty
                      ? Center(
                          child: Text('该时间段没有课程',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.faint)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          itemCount: records.length,
                          itemBuilder: (context, i) {
                            final r = records[i];
                            final m = _media[r.id] ?? const <MediaAsset>[];
                            final title = (r.note?.trim().isNotEmpty ?? false)
                                ? r.note!.split('\n').first.trim()
                                : '${r.dateAsDateTime.month}/${r.dateAsDateTime.day} ${r.styleName ?? '舞蹈'}课';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.hairline),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 52,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: AppColors.ink,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                        m.isNotEmpty && m.first.type == 'video'
                                            ? Icons.play_arrow
                                            : Icons.image,
                                        color: AppColors.bg,
                                        size: 16),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 2),
                                        Text(
                                            '${r.dateAsDateTime.month}/${r.dateAsDateTime.day} · ${r.styleName ?? ''}'
                                            '${r.teacherName == null ? '' : ' · ${r.teacherName}'}',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: AppColors.faint)),
                                      ],
                                    ),
                                  ),
                                  Text('${m.length} 个附件',
                                      style: TextStyle(
                                          fontSize: 10, color: accent)),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                SafeArea(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    decoration: const BoxDecoration(
                      color: AppColors.bg,
                      border: Border(top: BorderSide(color: AppColors.hairline)),
                    ),
                    child: Row(
                      children: [
                        Text('$nRecords 节 · $nMedia 个附件 · ${_human(bytes)}',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.secondary)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              shape: const StadiumBorder(),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10),
                            ),
                            onPressed:
                                (_exporting || records.isEmpty) ? null : _export,
                            child: Text(_exporting ? _progress : '导出',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}年${d.month}月${d.day}日';

  String _human(num bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '约 ${kb.round()} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '约 ${mb.round()} MB';
    return '约 ${(mb / 1024).toStringAsFixed(1)} GB';
  }

  Widget _chip(String label, bool selected) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? AppColors.ink : AppColors.faint)),
        const SizedBox(height: 3),
        Container(
          height: 2,
          width: 28,
          decoration: BoxDecoration(
            color: selected ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ],
    );
  }
}
