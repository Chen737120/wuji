import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../data/app_repository.dart' show ClassDraft, ClassSaver;
import '../data/db.dart' show ClassRecord, TaxonomyItem, ClassRecordRowX;
import '../data/taxonomy_repo.dart';
import '../models/models.dart';
import '../reload_bus.dart';
import '../services/abs_path_cache.dart';
import '../services/archive_fs.dart' show MediaPathResolver;
import '../services/media_importer.dart';
import '../theme.dart';
import 'media_viewer_page.dart';
import 'player_page.dart';
import 'sheets/date_sheet.dart';
import 'sheets/duration_sheet.dart';
import 'sheets/style_sheet.dart';
import 'sheets/text_sheet.dart';

/// 新增/编辑课（规格 §3.4）：仿「舞动时光」单页表单。
class RecordFormPage extends StatefulWidget {
  const RecordFormPage(
      {super.key, this.existing, this.importer, this.initialDate});

  final ClassRecord? existing; // 编辑模式
  final MediaImporter? importer; // 测试注入；默认 PluginMediaImporter
  final DateTime? initialDate; // 新增时的默认日期（如日历选中的那天）

  @override
  State<RecordFormPage> createState() => _RecordFormPageState();
}

/// 封面是否还值得自动重试（P2-26）：失败过的键不再触发原生取帧。
bool shouldRetryCover(String key, Set<String> failed) => !failed.contains(key);

class _RecordFormPageState extends State<RecordFormPage> {
  late DateTime _date;
  final _noteController = TextEditingController();
  TaxonomyItem? _style;
  TaxonomyItem? _teacher;
  TaxonomyItem? _studio;
  int _sessions = 1;
  int _minutesEach = 60;

  final _picked = <PickedMedia>[]; // 本次新选
  final _existingMedia = <ExistingMedia>[]; // 编辑模式的旧附件
  final _removedIds = <String>[]; // 编辑时被 ✕ 的旧附件 id
  bool _saving = false;

  // 表单条目封面缓存（2026-10-24 需求）：coverKey → 封面绝对路径。
  // 新选视频=video_thumbnail 生成临时封面（异步，完成即刷新）；
  // 新选图片=原图自身；旧附件=thumbName（图片退 fileName）经 AbsPathCache 解析。
  final _coverPaths = <String, String>{};
  final _coverPending = <String>{}; // 生成中/解析中，防重复触发

  /// 封面失败记忆（P2-26）：损坏视频每次 rebuild 重取帧是秒级原生解码，
  /// 失败过的键不再自动重试；用户重选同一文件时清除（见 _pickMedia）。
  final _coverFailed = <String>{};

  /// 为本次新选的视频生成临时封面（56×42 小图，maxWidth 200 够用）。
  Future<void> _generateVideoCover(String coverKey, String videoPath) async {
    _coverPending.add(coverKey);
    try {
      final bytes = await VideoThumbnail.thumbnailData(
          video: videoPath,
          imageFormat: ImageFormat.JPEG,
          quality: 60,
          maxWidth: 200);
      if (bytes == null || bytes.isEmpty) {
        _coverFailed.add(coverKey); // 失败记忆：不每帧重试（P2-26）
        return;
      }
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/wuji-form-thumb');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final f = File('${dir.path}/${const Uuid().v4()}.jpg');
      await f.writeAsBytes(bytes);
      _coverFailed.remove(coverKey);
      if (mounted) setState(() => _coverPaths[coverKey] = f.path);
    } catch (_) {
      // 测试环境/取帧失败：留图标占位，不阻塞表单；记下失败避免反复重取
      _coverFailed.add(coverKey);
    } finally {
      _coverPending.remove(coverKey);
    }
  }

  /// 解析旧附件封面（SAF 复制有开销，AbsPathCache 进程内去重）。
  Future<void> _resolveCover(String coverKey, String rel) async {
    _coverPending.add(coverKey);
    final resolver = context.read<MediaPathResolver?>();
    try {
      final path = await AbsPathCache.resolve(resolver, rel);
      if (path != null) {
        _coverFailed.remove(coverKey);
        if (mounted) setState(() => _coverPaths[coverKey] = path);
      } else {
        _coverFailed.add(coverKey); // 解析失败记忆（P2-26）
      }
    } catch (_) {
      _coverFailed.add(coverKey);
    } finally {
      _coverPending.remove(coverKey);
    }
  }

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
      _date = widget.initialDate ?? DateTime.now();
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

  @override
  void dispose() {
    // 每次进出表单泄漏一个持有感受全文的 controller（P2-25）
    _noteController.dispose();
    super.dispose();
  }

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
    // 重选同一文件必须清除失败记忆，否则该路径一旦失败就永不重试（P2-26）
    for (final p in result.picked) {
      _coverFailed.remove(p.path);
    }
    if (result.failedNames.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${result.failedNames.length} 个文件读取失败，已跳过')));
    }
  }

  Future<void> _pickDate() async {
    final d = await showDateSheet(context, initial: _date);
    if (d != null) setState(() => _date = d);
  }

  Future<void> _previewPicked(PickedMedia p) async {
    if (p.isVideo) {
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => PlayerPage(fileName: p.path)));
    } else {
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => ImageViewerPage(path: p.path)));
    }
  }

  Future<void> _previewExisting(ExistingMedia em) async {
    final messenger = ScaffoldMessenger.of(context);
    final path =
        await context.read<MediaPathResolver?>()?.toAbsolutePath(em.fileName,
            paced: true); // 播放前的 SAF 拷贝走分块（P2-7）
    if (!mounted) return;
    if (path == null) {
      // 同 P1-13：解析失败不把相对路径交给播放器
      messenger.showSnackBar(
          const SnackBar(content: Text('视频文件已丢失，可从备份导入恢复')));
      return;
    }
    if (em.isVideo) {
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => PlayerPage(fileName: path)));
    } else {
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => ImageViewerPage(path: path)));
    }
  }

  String get _durationLabel => '$_sessions节×$_minutesEach分';

  Future<void> _save() async {
    if (_saving) return;
    // 防重入置位前置（P1-5）：预检/确认框都有 await，晚置位会让双击并发
    // 越过守卫，媒体各用独立 uuid → 附件双份入库
    setState(() => _saving = true);
    final repo = _repo; // await 前捕获（context.read 不能在 await 后用）
    try {
      // 空间预检（规格 §8）：SAF 不可查询时恒 false 自动跳过
      final willWarn = await repo.needsSpaceWarningFor(
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
      await repo.saveDraft(ClassDraft(
        record: record,
        newMedia: [for (final p in _picked) p.toInput()],
        // 快照语义（P2-27）：保存期间用户仍可能删附件，传副本而非引用
        removeMediaIds: [..._removedIds],
      ));
      ReloadBus.instance.bump(); // 统计/记录两页常驻 IndexedStack，广播刷新
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
          // 保存中禁止退出（P2-24）：大视频保存数十秒，一按就丢
          onPressed: _saving ? null : () => Navigator.pop(context),
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
      body: PopScope(
        // 系统返回键同样在保存中禁用（P2-24）
        canPop: !_saving,
        child: ListView(
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
                hintStyle: const TextStyle(color: AppColors.faint),
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
          _mediaTile(
              coverKey: em.thumbName ?? 'old:${em.fileName}',
              title: em.fileName
                  .split(Platform.pathSeparator)
                  .last
                  .split('/')
                  .last,
              isVideo: em.isVideo,
              rel: em.thumbName ?? (em.isVideo ? null : em.fileName),
              onRemove: () {
                setState(() {
                  _existingMedia.remove(em);
                  _removedIds.add(em.id);
                });
              },
              onPreview: () => _previewExisting(em)),
        for (final p in _picked)
          _mediaTile(
              coverKey: p.path,
              title: p.path.split(Platform.pathSeparator).last.split('/').last,
              isVideo: p.isVideo,
              pickedPath: p.path,
              onRemove: () {
                setState(() => _picked.remove(p));
              },
              onPreview: () => _previewPicked(p)),
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

  /// 表单条目：封面小图（有封面显示封面，视频叠播放角标）＋文件名＋移除。
  /// [pickedPath] 本次新选的绝对路径（视频用它生成封面，图片直接显示）；
  /// [rel] 旧附件的封面相对路径（视频无 thumbName 时为 null，留图标占位）。
  Widget _mediaTile({
    required String coverKey,
    required String title,
    required bool isVideo,
    String? pickedPath,
    String? rel,
    required VoidCallback onRemove,
    VoidCallback? onPreview,
  }) {
    String? cover;
    if (pickedPath != null && !isVideo) {
      cover = pickedPath; // 新选图片：原图即封面
    } else {
      cover = _coverPaths[coverKey];
      if (cover == null &&
          !_coverPending.contains(coverKey) &&
          shouldRetryCover(coverKey, _coverFailed)) {
        if (pickedPath != null) {
          _generateVideoCover(coverKey, pickedPath);
        } else if (rel != null) {
          _resolveCover(coverKey, rel);
        }
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPreview,
        child: Row(
        children: [
          Container(
            width: 56,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.hairline, // 软占位色：封面生成前不再黑块
              borderRadius: BorderRadius.circular(6),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: cover == null
                ? Icon(isVideo ? Icons.play_arrow : Icons.image,
                    color: AppColors.faint, size: 18)
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(File(cover),
                          fit: BoxFit.cover,
                          cacheWidth: 200, // 56×42 小图：限解码宽防卡顿
                          errorBuilder: (_, _, _) => Icon(
                              isVideo ? Icons.play_arrow : Icons.image,
                              color: AppColors.faint,
                              size: 18)),
                      if (isVideo)
                        Center(
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(
                                color: Colors.black38,
                                shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: const Icon(Icons.play_arrow,
                                color: Colors.white, size: 13),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
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
