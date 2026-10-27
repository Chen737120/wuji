import 'dart:developer' as dev;
import 'dart:io';

import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:uuid/uuid.dart';
import 'archive_store.dart';

/// 设备端缩略图生成器：视频首帧 → 存档 thumbs/uuid.jpg，返回相对路径。
/// 失败时返回 null（保存流程容忍，UI 用占位；失败原因记 log，便于排查 4K/HEVC）。
Future<String?> Function(String sourcePath) deviceThumbMaker(
    ArchiveStore store) {
  return (sourcePath) async {
    final base = sourcePath.split(Platform.pathSeparator).last;
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: sourcePath,
        imageFormat: ImageFormat.JPEG,
        quality: 60,
        // 宽高同时限制：插件 Java 侧先全分辨率解码再缩放，
        // maxWidth-only 对大视频更容易 OOM 失败（P2-36）
        maxWidth: 360,
        maxHeight: 360,
      );
      if (bytes == null || bytes.isEmpty) {
        dev.log('thumb 失败 $base: 空结果', name: 'wuji');
        return null;
      }
      final rel = 'thumbs/${const Uuid().v4()}.jpg';
      await store.fs.write(rel, Stream<List<int>>.value(bytes));
      return rel;
    } catch (e) {
      dev.log('thumb 失败 $base: $e', name: 'wuji');
      return null;
    }
  };
}
