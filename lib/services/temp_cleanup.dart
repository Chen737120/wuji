import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 启动时清理应用缓存里的陈旧临时文件（评审重要项 #2）：
/// - `wuji-export/`：FFmpeg 导出产物目录；
/// - `wuji-import-extract/`：导入解压目录；
/// - `wuji-import-*.zip`：导入用的 zip 副本；
/// - `舞记备份-*.zip`：导出打包副本（分享后未删的残留）；
/// - `wuji-form-thumb/`：新增记录表单的视频封面预览（仅表单展示用）。
/// 只删修改时间早于 [maxAge]（默认 24 小时）的，避免误删进行中的任务。
Future<void> cleanupStaleTemp({
  Duration maxAge = const Duration(hours: 24),
}) async {
  try {
    final tmp = await getTemporaryDirectory();
    final now = DateTime.now();
    for (final e in tmp.listSync(followLinks: false)) {
      final name = e.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last;
      final isOurs = name == 'wuji-export' ||
          name == 'wuji-import-extract' ||
          name == 'wuji-form-thumb' ||
          name.startsWith('wuji-import-') ||
          name.startsWith('舞记备份-');
      if (!isOurs) continue;
      try {
        final age = now.difference(e.statSync().modified);
        if (age <= maxAge) continue;
        if (e is Directory) {
          e.deleteSync(recursive: true);
        } else if (e is File) {
          e.deleteSync();
        }
      } catch (_) {}
    }
  } catch (_) {
    // 清理失败不影响启动
  }
}
