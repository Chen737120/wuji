import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/app_repository.dart' show ClassSaver;
import '../data/db.dart' show ClassRecord, MediaAsset, ClassRecordRowX;
import '../reload_bus.dart';
import '../services/abs_path_cache.dart';
import '../services/archive_fs.dart' show MediaLocator, MediaPathResolver;
import '../services/archive_store.dart' show ArchiveStore;
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/export_naming.dart';
import '../services/exporter.dart';
import '../services/photo_bridge.dart';
import '../theme.dart';
import 'player_page.dart';
import 'record_form_page.dart';

/// 课堂详情页（规格 §3.5）。
class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.classId});

  final String classId;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  ClassRecord? _record;
  List<MediaAsset> _media = [];
  Set<String> _missing = {};
  bool _loaded = false;
  int _page = 0;

  ClassSaver get _saver => context.read<ClassSaver>();
  MediaLocator get _locator => context.read<MediaLocator>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final matches = await _saver
        .allRecords()
        .then((rs) => rs.where((r) => r.id == widget.classId).toList());
    final record = matches.isEmpty ? null : matches.single;
    final media = await _saver.mediaOf(widget.classId);
    final missing = <String>{};
    for (final m in media) {
      if (!await _locator.exists(m.fileName)) missing.add(m.fileName);
    }
    if (!mounted) return;
    setState(() {
      _record = record;
      _media = media;
      _missing = missing;
      _loaded = true;
    });
  }

  String get _meta {
    final r = _record!;
    final d = r.dateAsDateTime;
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return [
      '${d.month}月${d.day}日 ${weekdays[d.weekday - 1]}',
      if (r.styleName?.isNotEmpty ?? false) r.styleName!,
      '${r.sessionCount}节×${r.minutesEach}分',
      if (r.teacherName?.isNotEmpty ?? false) r.teacherName!,
      if (r.studioName?.isNotEmpty ?? false) r.studioName!,
    ].join(' · ');
  }

  Future<void> _confirmDelete() async {
    final n = _media.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('删除这节课？', style: TextStyle(fontSize: 16)),
        content: Text('将删除 $n 个视频/图片，不可恢复。',
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('确认删除',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _saver.deleteRecord(widget.classId);
      ReloadBus.instance.bump(); // 统计/记录两页立即反映删除结果
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败：$e')));
      }
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _saveToAlbum() async {
    final messenger = ScaffoldMessenger.of(context);
    var saved = 0;
    var failed = 0;
    Object? lastErr;
    for (final m in _media) {
      if (_missing.contains(m.fileName)) continue;
      try {
        final path = await _absolutePath(m.fileName);
        if (path == null) {
          failed++;
          continue;
        }
        if (m.type == 'video') {
          await PhotoManagerBridge.saveVideo(path);
        } else {
          await PhotoManagerBridge.saveImage(path);
        }
        saved++;
      } catch (e) {
        failed++;
        lastErr = e;
      }
    }
    messenger.showSnackBar(SnackBar(
        content: Text(failed == 0
            ? '已保存 $saved 个到相册'
            : '已保存 $saved 个到相册，$failed 个失败${lastErr == null ? '' : '：$lastErr'}')));
  }

  Future<String?> _absolutePath(String rel) async {
    // SAF 模式下先复制到临时文件再存相册（T12 注入转换器；当前 LocalFs 直接映射）
    return context.read<MediaPathResolver?>()?.toAbsolutePath(rel) ?? rel;
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, color: AppColors.secondary),
            onSelected: (v) {
              if (v == 'delete') _confirmDelete();
              if (v == 'album') _saveToAlbum();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'album', child: Text('保存到相册', style: TextStyle(fontSize: 13))),
              PopupMenuItem(value: 'delete', child: Text('删除这节课', style: TextStyle(fontSize: 13))),
            ],
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _record == null
              ? Center(
                  child: Text('这节课不存在',
                      style: TextStyle(fontSize: 12, color: AppColors.faint)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    Text(_record!.note?.split('\n').first.trim().isNotEmpty == true
                        ? _record!.note!.split('\n').first.trim()
                        : recordTitleOf(_record!),
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700, height: 1.5)),
                    const SizedBox(height: 6),
                    Text(_meta,
                        style: TextStyle(fontSize: 11, color: AppColors.secondary)),
                    const SizedBox(height: 12),
                    _mediaArea(accent),
                    const SizedBox(height: 14),
                    if (_feelingsBody().isNotEmpty) ...[
                      const Text('课堂感受',
                          style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 2,
                              color: AppColors.secondary)),
                      const SizedBox(height: 6),
                      Text(_feelingsBody(),
                          style: const TextStyle(
                              fontSize: 13, height: 1.9, color: AppColors.ink)),
                      const SizedBox(height: 14),
                    ],
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.hairline),
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: () async {
                            await Navigator.push(context,
                                MaterialPageRoute(builder: (_) => RecordFormPage(existing: _record)));
                            if (context.mounted) _load();
                          },
                          child: Text('编辑',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.secondary)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: accent.withValues(alpha: .5)),
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: _exportThis,
                          child: Text('导出这一课',
                              style: TextStyle(fontSize: 12, color: accent)),
                        ),
                      ),
                    ]),
                  ],
                ),
    );
  }

  /// 感受正文 = note 去掉首行（首行已是标题，不重复展示）。
  String _feelingsBody() {
    final lines = (_record!.note ?? '').split('\n');
    if (lines.length < 2) return '';
    return lines.skip(1).join('\n').trim();
  }

  Future<void> _exportThis() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final exporter = Exporter(context.read<ArchiveStore>());
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/wuji-export');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      await exporter.exportSingleFolder(
          _record!, _media.where((m) => !_missing.contains(m.fileName)).toList(),
          targetDir: dir.path);
      final folderName = folderBaseName(_record!);
      // 终审 I6：Android 分享不支持目录 —— 打成 zip 再分享
      final zipPath = '${tmp.path}/$folderName.zip';
      final enc = ZipFileEncoder()..create(zipPath);
      await enc.addDirectory(Directory('${dir.path}/$folderName'));
      await enc.close();
      await SharePlus.instance
          .share(ShareParams(files: [XFile(zipPath)], text: folderName));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  /// 视频 → thumbs 封面、图片 → 原图；解析失败/无封面时回退图标。
  Widget _coverImage(String? rel, IconData fallbackIcon) {
    if (rel == null) {
      return Icon(fallbackIcon, color: AppColors.bg, size: 40);
    }
    return FutureBuilder<String?>(
      future: AbsPathCache.resolve(context.read<MediaPathResolver?>(), rel),
      builder: (context, snap) {
        final path = snap.data;
        if (path == null) {
          return Icon(fallbackIcon, color: AppColors.bg, size: 40);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(File(path),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, _, _) =>
                  Icon(fallbackIcon, color: AppColors.bg, size: 40)),
        );
      },
    );
  }

  Widget _mediaArea(Color accent) {
    if (_media.isEmpty) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.hairline),
        ),
        alignment: Alignment.center,
        child: Text('这节课没有视频/图片',
            style: TextStyle(fontSize: 12, color: AppColors.faint)),
      );
    }
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PageView.builder(
            itemCount: _media.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) {
              final m = _media[i];
              final missing = _missing.contains(m.fileName);
              return GestureDetector(
                onTap: (m.type == 'video' && !missing)
                    ? () async {
                        final nav = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (ctx) => const AlertDialog(
                            backgroundColor: Colors.white,
                            content: Row(
                              children: [
                                CircularProgressIndicator(strokeWidth: 2),
                                SizedBox(width: 16),
                                Expanded(
                                  child: Text('正在打开视频…\n大文件首次打开需要一点时间',
                                      style: TextStyle(
                                          fontSize: 12, height: 1.6)),
                                ),
                              ],
                            ),
                          ),
                        );
                        try {
                          final path =
                              await context.read<MediaPathResolver?>()?.toAbsolutePath(m.fileName) ??
                                  m.fileName;
                          nav.pop();
                          if (!context.mounted) return;
                          await Navigator.push(context,
                              MaterialPageRoute(builder: (_) => PlayerPage(fileName: path)));
                        } catch (e) {
                          nav.pop();
                          messenger.showSnackBar(SnackBar(
                              content: Text('视频打开失败：$e')));
                        }
                      }
                    : null,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: missing
                      ? Text('文件已丢失（可从云盘备份导入）',
                          style: TextStyle(
                              fontSize: 11, color: Colors.white.withValues(alpha: .7)))
                      : m.type == 'video'
                          ? _coverImage(m.thumbName, Icons.play_arrow)
                          : _coverImage(m.fileName, Icons.image),
                ),
              );
            },
          ),
        ),
        if (_media.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _media.length; i++)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _page ? accent : AppColors.hairline,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 卡片标题兜底（复用 records_page 的语义，避免 UI 互相依赖，此处独立实现）。
String recordTitleOf(ClassRecord r) {
  final d = r.dateAsDateTime;
  final style = (r.styleName == null || r.styleName!.isEmpty) ? '舞蹈' : r.styleName!;
  return '${d.month}/${d.day} $style课';
}
