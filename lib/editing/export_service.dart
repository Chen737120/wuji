import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_min/statistics.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

/// 导出已取消（用户点取消，或取消请求先于任务启动）。
class ExportCancelled implements Exception {
  @override
  String toString() => 'ExportCancelled';
}

/// 导出失败（FFmpeg 非零退出等）。
class ExportFailed implements Exception {
  ExportFailed(this.message);
  final String message;
  @override
  String toString() => message;
}

/// FFmpeg 命令执行器（窄接口：宿主测试注入 fake，设备端包 FFmpegKit）。
abstract class CommandRunner {
  /// 返回进程退出码，0 = 成功。命令已含输出路径（最后一个参数）。
  Future<int> run(
    String command, {
    void Function(double progress)? onProgress,
    int? expectedDurationMs,
  });

  /// 取消当前/下一个 FFmpeg 会话。
  void cancel();
}

/// 产物搬运（窄接口）：成功=搬进相册并消费临时文件；失败/取消=清半成品。
abstract class FileMover {
  /// 把临时产物保存进相册 `Movies/wuji/`，返回相册内路径（展示用）。
  Future<String> moveToGallery(String tempPath, String fileName);

  /// 幂等清理半成品。
  Future<void> cleanTemp(String path);
}

/// 一次导出任务。[command] 是除输出路径外的完整 FFmpeg 参数串——
/// 输出文件永远是最后一个参数，由 [ExportService] 注入临时路径。
class ExportJob {
  const ExportJob({
    required this.command,
    required this.base,
    this.ext = 'mp4',
    this.expectedDurationMs,
  });

  final String command;
  final String base; // '直拍' | '对比'
  final String ext;
  final int? expectedDurationMs; // 进度分母；null = 不报进度
}

/// 导出管线（规格 §6）：统一进度/取消/半成品清理；成功才进相册。
class ExportService {
  ExportService({
    required this._runner,
    required this._mover,
    this._clock,
    Future<Directory> Function()? tempDirProvider,
  })  : _tempDir = tempDirProvider;

  final CommandRunner _runner;
  final FileMover _mover;
  final DateTime Function()? _clock;
  final Future<Directory> Function()? _tempDir;
  bool _cancelRequested = false;

  /// 用户取消：立即透传给 runner 杀 FFmpeg 会话，并在本次 run 里生效。
  void cancel() {
    _cancelRequested = true;
    _runner.cancel();
  }

  Future<String> run(ExportJob job, {void Function(double p)? onProgress}) async {
    final now = (_clock ?? DateTime.now)();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(now);
    final fileName = '${job.base}_$stamp.${job.ext}';
    final dir = await (_tempDir ?? _defaultTempDir)();
    final temp = '${dir.path}${Platform.pathSeparator}$fileName';
    var moved = false;
    try {
      if (_cancelRequested) throw ExportCancelled();
      var cmd = '${job.command} "$temp"';
      var rc = await _runner.run(cmd,
          onProgress: onProgress,
          expectedDurationMs: job.expectedDurationMs);
      // 硬件编码器（mediacodec）在部分设备/尺寸上会失败：回退软编码 mpeg4
      if (rc != 0 && cmd.contains('-c:v h264_mediacodec')) {
        cmd = cmd.replaceAll('-c:v h264_mediacodec', '-c:v mpeg4 -q:v 4');
        rc = await _runner.run('$cmd "$temp"',
            onProgress: onProgress,
            expectedDurationMs: job.expectedDurationMs);
      }
      if (_cancelRequested) throw ExportCancelled();
      if (rc != 0) {
        // FFmpegKitConfig 在无绑定环境（测试）会抛异步错误，用 zone 兜住
        var logs = '';
        await runZonedGuarded(() async {
          logs = await _lastLogs();
        }, (e, s) {});
        throw ExportFailed('FFmpeg 退出码 $rc${logs.isEmpty ? '' : '：$logs'}');
      }
      moved = true; // 成功：mover 搬进相册并消费临时文件
      return await _mover.moveToGallery(temp, fileName);
    } finally {
      if (!moved) await _mover.cleanTemp(temp); // 失败/取消：清半成品
    }
  }

  /// 最近一次 FFmpeg 会话的错误日志（截尾，便于用户回报真实原因）。
  Future<String> _lastLogs() async {
    try {
      final session = await FFmpegKitConfig.getLastCompletedSession();
      if (session is! FFmpegSession) return '';
      final String? s = await session.getAllLogsAsString();
      if (s == null || s.isEmpty) return '';
      final lines = s.trim().split('\n');
      return lines.length <= 3
          ? lines.join(' | ')
          : lines.sublist(lines.length - 3).join(' | ');
    } catch (_) {
      return '';
    }
  }

  Future<Directory> _defaultTempDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}wuji-export');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }
}

/// 设备端实现：包 FFmpegKit 异步会话。
class FFmpegKitRunner implements CommandRunner {
  @override
  Future<int> run(
    String command, {
    void Function(double progress)? onProgress,
    int? expectedDurationMs,
  }) {
    final completer = Completer<int>();
    FFmpegKit.executeAsync(command, (FFmpegSession session) async {
      final ReturnCode? rc = await session.getReturnCode();
      completer.complete(rc?.getValue() ?? -1);
    }, null, (Statistics statistics) {
      if (onProgress == null ||
          expectedDurationMs == null ||
          expectedDurationMs <= 0) {
        return;
      }
      onProgress((statistics.getTime() / expectedDurationMs).clamp(0.0, 1.0));
    });
    return completer.future;
  }

  @override
  void cancel() => FFmpegKit.cancel();
}

/// 设备端实现：photo_manager 存相册（Movies/wuji/）＋媒体扫描＋删临时。
class GalleryMover implements FileMover {
  static const _relativePath = 'Movies/wuji';

  @override
  Future<String> moveToGallery(String tempPath, String fileName) async {
    await PhotoManager.editor.saveVideo(
      File(tempPath),
      title: fileName,
      relativePath: _relativePath,
    );
    try {
      final f = File(tempPath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    return '$_relativePath/$fileName';
  }

  @override
  Future<void> cleanTemp(String path) async {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

@visibleForTesting
String buildOutputFileName(String base, DateTime now, {String ext = 'mp4'}) =>
    '${base}_${DateFormat('yyyyMMdd_HHmm').format(now)}.$ext';
