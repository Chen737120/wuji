import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../data/app_repository.dart' show ClassDraft, ClassSaver;
import '../data/db.dart' show ClassRecord, TaxonomyItem, ClassRecordRowX;
import '../data/taxonomy_repo.dart';
import '../models/models.dart';
import '../services/media_importer.dart';
import '../theme.dart';
import 'sheets/duration_sheet.dart';
import 'sheets/style_sheet.dart';
import 'sheets/text_sheet.dart';

/// 新增/编辑课（规格 §3.4）：仿「舞动时光」单页表单。
class RecordFormPage extends StatefulWidget {
  const RecordFormPage({super.key, this.existing, this.importer});

  final ClassRecord? existing; // 编辑模式
  final MediaImporter? importer; // 测试注入；默认 PluginMediaImporter

  @override
  State<RecordFormPage> createState() => _RecordFormPageState();
}

class _RecordFormPageState extends State<RecordFormPage> {
  late DateTime _date;
  final _noteController = TextEditingController();
  TaxonomyItem? _style;
  TaxonomyItem? _teacher;
  TaxonomyItem? _studio;
  int _sessions = 1;
  int _minutesEach = 90;

  final _picked = <PickedMedia>[]; // 本次新选
  final _existingMedia = <ExistingMedia>[]; // 编辑模式的旧附件
  final _removedIds = <String>[]; // 编辑时被 ✕ 的旧附件 id
  bool _saving = false;

  ClassSaver get _repo => context.read<ClassSaver>();
  MediaImporter get _importer => widget.importer ?? const PluginMediaImporter();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _date = e.dateAsDateTime;
      _sessions = e.sessionCount;
      _minutesEach = e.minutesEach;
      _noteController.text = e.note ?? '';
      _style = e.styleName == null ? null : _fakeItem(TaxonomyKind.style, e.styleName!);
      _teacher = e.teacherName == null ? null : _fakeItem(TaxonomyKind.teacher, e.teacherName!);
      _studio = e.studioName == null ? null : _fakeItem(TaxonomyKind.studio, e.studioName!);
      _loadExistingMedia();
    } else {
      _date = DateTime.now();
    }
  }

  TaxonomyItem _fakeItem(TaxonomyKind kind, String name) => TaxonomyItem(
        id: '',
        kind: kind.dbValue,
        name: name,
        isBuiltin: false,
        sortOrder: 0,
        lastUsedAt: null,
        isActive: true,
      );

  Future<void> _loadExistingMedia() async {
    final rows = await _repo.mediaOf(widget.existing!.id);
    if (!mounted) return;
    setState(() {
      _existingMedia
        ..clear()
        ..addAll(rows.map((r) => ExistingMedia(
              id: r.id,
              fileName: r.fileName,
              thumbName: r.thumbName,
              isVideo: r.type == 'video',
            )));
    });
  }

  Future<void> _pickMedia() async {
    final result = await _importer.pick(context);
    if (result.picked.isEmpty) {
      if (result.failedNames.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${result.failedNames.length} 个文件读取失败：${result.failedNames.join('、')}')));
      }
      return;
    }
    setState(() => _picked.addAll(result.picked));
    if (result.failedNames.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${result.failedNames.length} 个文件读取失败，已跳过')));
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = d);
  }

  String get _durationLabel => '$_sessions节×$_minutesEach分';

  Future<void> _save() async {
    if (_saving) return;
    // 空间预检（规格 §8）：SAF 不可查询时恒 false 自动跳过
    final willWarn = await _repo.needsSpaceWarningFor(
        _picked.map((p) => p.toInput()).toList());
    if (willWarn && mounted) {
      final goOn = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('手机空间可能不够', style: TextStyle(fontSize: 15)),
          content: const Text('剩余空间小于所选视频/图片的总大小，保存可能失败。仍要保存吗？',
              style: TextStyle(fontSize: 13)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('仍要保存', style: TextStyle(color: Theme.of(context).colorScheme.primary))),
          ],
        ),
      );
      if (goOn != true) return;
    }
    setState(() => _saving = true);
    try {
      final id = widget.existing?.id ?? _newUuid();
      final record = ClassRecord(
        id: id,
        date: DateFormat('yyyy-MM-dd').format(_date),
        styleName: _style?.name,
        teacherName: _teacher?.name,
        studioName: _studio?.name,
        sessionCount: _sessions,
        minutesEach: _minutesEach,
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _repo.saveDraft(ClassDraft(
        record: record,
        newMedia: [for (final p in _picked) p.toInput()],
        removeMediaIds: _removedIds,
      ));
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      debugPrint('保存失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static const _uuid = Uuid();
  String _newUuid() => _uuid.v4();

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.faint),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.existing == null ? '记录一节课' : '编辑这节课',
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 2)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: Text(DateFormat('M月d日').format(_date),
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _mediaArea(),
          const SizedBox(height: 10),
          Row(
            children: [
              _fieldBox('♪', '舞种', _style?.name, selected: _style != null,
                  onTap: () async {
                final it = await showStyleSheet(context, _taxonomyRepo);
                if (it != null) setState(() => _style = it);
              }),
              const SizedBox(width: 6),
              _fieldBox('🕐', '时长', _durationLabel, selected: true,
                  onTap: () async {
                final r = await showDurationSheet(context,
                    sessions: _sessions, minutesEach: _minutesEach);
                if (r != null) {
                  setState(() {
                    _sessions = r.$1;
                    _minutesEach = r.$2;
                  });
                }
              }),
              const SizedBox(width: 6),
              _fieldBox('👤', '老师', _teacher?.name ?? '选填',
                  selected: _teacher != null, onTap: () async {
                final it = await showTextSheet(context, _taxonomyRepo,
                    TaxonomyKind.teacher, title: '授课老师', hint: '老师名字');
                if (it != null) setState(() => _teacher = it);
              }),
              const SizedBox(width: 6),
              _fieldBox('📍', '舞室', _studio?.name ?? '选填',
                  selected: _studio != null, onTap: () async {
                final it = await showTextSheet(context, _taxonomyRepo,
                    TaxonomyKind.studio, title: '舞室名称', hint: '舞室名称');
                if (it != null) setState(() => _studio = it);
              }),
            ],
          ),
          const SizedBox(height: 10),
          const Text('记录你的感受',
              style: TextStyle(fontSize: 11, letterSpacing: 2, color: AppColors.secondary)),
          const SizedBox(height: 6),
          TextField(
            controller: _noteController,
            maxLines: 5,
            minLines: 3,
            decoration: InputDecoration(
              hintText: '这节课的感觉、突破、想记下来的瞬间…',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.hairline),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中…' : '保存',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text('只记感受不选视频也可以保存 · 选填项都可留空',
                style: TextStyle(fontSize: 9, color: AppColors.faint)),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  TaxonomyRepo get _taxonomyRepo => TaxonomyRepo(_repo.db);

  Widget _mediaArea() {
    final hasMedia = _picked.isNotEmpty || _existingMedia.isNotEmpty;
    if (!hasMedia) {
      return GestureDetector(
        onTap: _pickMedia,
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: .4),
                width: 1.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('＋',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w300,
                      color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 4),
              const Text('视频 / 图片',
                  style: TextStyle(fontSize: 12, color: AppColors.secondary)),
              const SizedBox(height: 2),
              Text('支持多选',
                  style: TextStyle(fontSize: 10, color: AppColors.faint)),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final em in _existingMedia)
          _mediaTile(em.fileName, em.thumbName, em.isVideo, () {
            setState(() {
              _existingMedia.remove(em);
              _removedIds.add(em.id);
            });
          }),
        for (final p in _picked)
          _mediaTile(p.path, null, p.isVideo, () {
            setState(() => _picked.remove(p));
          }),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _pickMedia,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('继续添加', style: TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  Widget _mediaTile(String pathOrRel, String? thumb, bool isVideo,
      VoidCallback onRemove) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Icon(isVideo ? Icons.play_arrow : Icons.image,
                color: AppColors.bg, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(pathOrRel.split(Platform.pathSeparator).last.split('/').last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: AppColors.faint),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }

  Widget _fieldBox(String icon, String label, String? value,
      {required bool selected, required VoidCallback onTap}) {
    final accent = Theme.of(context).colorScheme.primary;
    final display = value ?? '选填';
    final filled = selected && display != '选填';
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: filled ? accent : AppColors.hairline, width: filled ? 1.2 : 1),
          ),
          child: Column(
            children: [
              Text('$icon $label',
                  style:
                      const TextStyle(fontSize: 9, color: AppColors.faint)),
              const SizedBox(height: 3),
              Text(display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      color: filled ? accent : AppColors.secondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class ExistingMedia {
  ExistingMedia({
    required this.id,
    required this.fileName,
    required this.thumbName,
    required this.isVideo,
  });
  final String id;
  final String fileName;
  final String? thumbName;
  final bool isVideo;
}
