import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../data/app_repository.dart' show ClassSaver;
import '../data/db.dart' show MediaAsset;
import '../editing/media_source_picker.dart';
import '../services/abs_path_cache.dart';
import '../services/archive_fs.dart';
import '../theme.dart';
import 'widgets/media_thumb.dart';

/// 课堂记录视频选择页（规格 §4.1 ①「从舞记课堂选」）：
/// 按课分组列视频（封面缩略图＋时长），点击即选回。
class RecordMediaPickerPage extends StatefulWidget {
  const RecordMediaPickerPage({super.key});

  @override
  State<RecordMediaPickerPage> createState() => _RecordMediaPickerPageState();
}

class _RecordMediaPickerPageState extends State<RecordMediaPickerPage> {
  List<ClassVideoGroup> _groups = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saver = context.read<ClassSaver>();
    final records = await saver.allRecords();
    // 一次查询取回全部附件（评审建议：替代逐课 N+1 查询）
    final byClass = await saver.mediaByClass();
    final media = <MediaAsset>[
      for (final list in byClass.values) ...list,
    ];
    if (!mounted) return;
    setState(() {
      _groups = groupVideosByClass(records, media);
      _loaded = true;
    });
  }

  Future<void> _pick(ClassVideoGroup group, MediaAsset video) async {
    final messenger = ScaffoldMessenger.of(context);
    final resolver = context.read<MediaPathResolver?>();
    final path = await AbsPathCache.resolve(resolver, video.fileName);
    if (!mounted) return;
    if (path == null) {
      // 解析失败不 pop：把相对路径带走会让上层播放必然 Source error（P1-13）
      messenger.showSnackBar(
          const SnackBar(content: Text('视频文件已丢失，可从备份导入恢复')));
      return;
    }
    Navigator.pop(
      context,
      PickedSource(
        path: path,
        name: '${group.date} ${_groupTitle(group)}',
        fromArchive: true,
        classId: group.classId,
      ),
    );
  }

  String _groupTitle(ClassVideoGroup group) {
    final d = DateTime.parse(group.date);
    return DateFormat('M月d日').format(d);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
            onPressed: () => Navigator.pop(context)),
        centerTitle: true,
        title: const Text('从舞记课堂选',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _groups.isEmpty
              ? Center(
                  child: Text('课堂记录里还没有视频',
                      style: TextStyle(fontSize: 12, color: AppColors.faint)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final g in _groups) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 6),
                        child: Text(_groupHeader(g.date),
                            style: TextStyle(
                                fontSize: 12, color: AppColors.secondary)),
                      ),
                      for (final v in g.videos)
                        ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          leading: MediaThumb(rel: v.thumbName),
                          title: Text(_itemTitle(g),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12)),
                          subtitle: v.durationSec == null
                              ? null
                              : Text('${v.durationSec! ~/ 60}:${(v.durationSec! % 60).toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                      fontSize: 10, color: AppColors.faint)),
                          onTap: () => _pick(g, v),
                        ),
                    ],
                  ],
                ),
    );
  }

  /// 条目可读标题（uuid 文件名人类读不懂）：M月d日 · 舞种 · 老师
  String _itemTitle(ClassVideoGroup g) {
    final parts = [
      _groupTitle(g),
      if (g.styleName != null && g.styleName!.isNotEmpty) g.styleName!,
      if (g.teacherName != null && g.teacherName!.isNotEmpty) g.teacherName!,
    ];
    return parts.join(' · ');
  }

  String _groupHeader(String date) {
    final d = DateTime.parse(date);
    return '${d.year}年${d.month}月${d.day}日';
  }
}
