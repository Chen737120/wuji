import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import '../data/db.dart' show ClassRecord, MediaAsset;
import '../services/abs_path_cache.dart';
import '../services/archive_fs.dart';
import '../theme.dart';
import '../ui/record_media_picker_page.dart';

/// 剪辑输入源（规格 §4.1/§5.1）：相册或舞记课堂记录里的视频。
class PickedSource {
  const PickedSource({
    required this.path,
    required this.name,
    this.duration,
    this.fromArchive = false,
    this.classId,
  });

  /// FFmpeg 可直接读的路径（相册=originFile 临时拷贝；课堂=存档绝对路径）。
  final String path;
  final String name; // 展示名
  final Duration? duration;
  final bool fromArchive;
  final String? classId; // 来自课堂记录时的课 id
}

/// 按课分组的视频条目（课堂选择页用）。
class ClassVideoGroup {
  const ClassVideoGroup({
    required this.classId,
    required this.date,
    required this.videos,
  });

  final String classId;
  final String date; // yyyy-MM-dd
  final List<MediaAsset> videos; // 仅视频，按创建时间排序
}

/// 纯函数：只含视频附件的课、按日期倒序分组（无视频的课不出现）。
List<ClassVideoGroup> groupVideosByClass(
    List<ClassRecord> records, List<MediaAsset> media) {
  final sorted = [...records]..sort((a, b) => b.date.compareTo(a.date));
  final out = <ClassVideoGroup>[];
  for (final r in sorted) {
    final videos =
        media.where((m) => m.classId == r.id && m.type == 'video').toList();
    if (videos.isEmpty) continue;
    out.add(ClassVideoGroup(classId: r.id, date: r.date, videos: videos));
  }
  return out;
}

/// 统一视频选择底部弹层（规格 §4.1 ①）：两入口。
/// [albumPicker]/[archivePicker] 注入便于测试；默认实现见下。
Future<PickedSource?> showVideoSourceSheet(
  BuildContext context, {
  String title = '选择视频',
  Future<PickedSource?> Function(BuildContext, String? hint)? albumPicker,
  Future<PickedSource?> Function(BuildContext)? archivePicker,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('从相册选', style: TextStyle(fontSize: 14)),
            subtitle: Text('手机相册里的视频',
                style: TextStyle(fontSize: 10, color: AppColors.faint)),
            onTap: () => Navigator.pop(context, 'album'),
          ),
          ListTile(
            leading: const Icon(Icons.video_collection_outlined),
            title: const Text('从舞记课堂选', style: TextStyle(fontSize: 14)),
            subtitle: Text('已导入到课堂记录的视频',
                style: TextStyle(fontSize: 10, color: AppColors.faint)),
            onTap: () => Navigator.pop(context, 'archive'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (!context.mounted) return null;
  if (choice == 'album') {
    return (albumPicker ?? _pickFromAlbum)(context, null);
  }
  if (choice == 'archive') {
    return (archivePicker ?? showRecordMediaPicker)(context);
  }
  return null;
}

/// 相册单选视频（剪辑入口用）：权限+选择器+originFile 解析一体。
Future<PickedSource?> pickSingleVideoFromAlbum(BuildContext context, [String? hint]) async {
  final assets = await AssetPicker.pickAssets(
    context,
    pickerConfig: const AssetPickerConfig(
      maxAssets: 1,
      requestType: RequestType.video,
      themeColor: Color(0xFF3FA26F),
    ),
  );
  if (assets == null || assets.isEmpty) return null;
  final a = assets.single;
  final file = await a.originFile;
  if (file == null) return null;
  return PickedSource(
    path: file.path,
    name: a.title ?? '相册视频',
    duration: a.videoDuration,
  );
}

/// 课堂记录选择页入口（规格 §4.1 ①「从舞记课堂选」）：推入选择页。
Future<PickedSource?> showRecordMediaPicker(BuildContext context) {
  return Navigator.push<PickedSource>(
    context,
    MaterialPageRoute(builder: (_) => const RecordMediaPickerPage()),
  );
}

/// 相册单选视频；大视频取 originFile 有拷贝耗时，期间显示「准备中」遮罩。
Future<PickedSource?> _pickFromAlbum(BuildContext context, String? hint) async {
  final assets = await AssetPicker.pickAssets(
    context,
    pickerConfig: const AssetPickerConfig(
      maxAssets: 1,
      requestType: RequestType.video,
      themeColor: Color(0xFF3FA26F),
    ),
  );
  if (assets == null || assets.isEmpty) return null;
  final asset = assets.single;

  final done = Completer<PickedSource?>();
  if (!context.mounted) return null;
  // 准备中遮罩（不可手动关）：完成由下方逻辑 pop
  unawaited(showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: Colors.white,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(height: 12),
            Text('准备中…',
                style: TextStyle(fontSize: 12, color: AppColors.secondary)),
          ],
        ),
      ),
    ),
  ));
  PickedSource? picked;
  try {
    final file = await asset.originFile;
    if (file != null) {
      picked = PickedSource(
        path: file.path,
        name: asset.title ?? '相册视频',
        duration: asset.videoDuration,
      );
    }
  } catch (_) {
    picked = null;
  }
  if (context.mounted) Navigator.pop(context); // 关遮罩
  done.complete(picked);
  return done.future;
}

/// 供 RecordMediaPickerPage 解析绝对路径（AbsPathCache 进程内缓存）。
Future<String?> resolveSourcePath(
        MediaPathResolver? resolver, String archiveRel) =>
    AbsPathCache.resolve(resolver, archiveRel);
