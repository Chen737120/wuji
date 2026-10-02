import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:uuid/uuid.dart';
import 'archive_store.dart';

/// 设备端缩略图生成器：视频首帧 → 存档 thumbs/uuid.jpg，返回相对路径。
/// 失败时返回 null（保存流程容忍，UI 用占位）。
Future<String?> Function(String sourcePath) deviceThumbMaker(
    ArchiveStore store) {
  return (sourcePath) async {
    final bytes = await VideoThumbnail.thumbnailData(
      video: sourcePath,
      imageFormat: ImageFormat.JPEG,
      quality: 60,
    );
    if (bytes == null || bytes.isEmpty) return null;
    final rel = 'thumbs/${const Uuid().v4()}.jpg';
    await store.fs.write(rel, Stream<List<int>>.value(bytes));
    return rel;
  };
}
