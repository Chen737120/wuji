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

import '../services/photo_bridge.dart';
import 'ffmpeg_probe.dart' show probeMedia;
import 'ffmpeg_serial.dart' show ffmpegGate;

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
  /// 返回进程退出码，0 = 成功。参数已含输出路径（最后一个参数）。
  Future<int> run(
    List<String> args, {
    void Function(double progress)? onProgress,
    int? expectedDurationMs,
  });

  /// 取消当前/下一个 FFmpeg 会话。
  void cancel();
}

/// 把命令串按空白拆成参数数组（评审建议：executeWithArguments 数组形式
/// 天然免注入）。双引号是 shell 级引用、拆完丢弃；单引号是 ffmpeg filter
/// 层引用（如 x='…'）、原样保留在参数内容里。
@visibleForTesting
List<String> tokenizeFfmpeg(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  var inSingle = false;
  var inDouble = false;
  var hasToken = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (inSingle) {
      if (c == '\'') {
        inSingle = false;
      } else {
        buf.write(c);
      }
    } else if (inDouble) {
      if (c == '"') {
        inDouble = false;
      } else {
        buf.write(c);
      }
    } else if (c == ' ' || c == '\t') {
      if (hasToken) {
        out.add(buf.toString());
        buf.clear();
        hasToken = false;
      }
    } else if (c == '"') {
      inDouble = true;
      hasToken = true;
    } else if (c == '\'') {
      inSingle = true;
      hasToken = true;
    } else {
      buf.write(c);
      hasToken = true;
    }
  }
  if (hasToken) out.add(buf.toString());
  return out;
}

/// 输出校验（窄接口）：探测文件是否含视频流。rc==0 但编码器静默零包
/// （AVD mediacodec 实测：成片仅 AAC、UI 零报错）时，半成品不得当成功
/// 搬进相册。设备端用 FFprobeKit（[defaultProbeHasVideoStream]），测试注入 fake。
typedef OutputVideoProbe = Future<bool> Function(String path);

/// 设备端默认实现：probeMedia 非空即含视频流（parseMediaInformationJson
/// 对无视频流的输入返回 null）。probe 自身异常按无视频流处理——
/// 静默成功不可接受，误报失败的代价只是重试/明确报错。
Future<bool> defaultProbeHasVideoStream(String path) async {
  try {
    return await probeMedia(path) != null;
  } catch (_) {
    return false;
  }
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
    OutputVideoProbe? probeHasVideo,
    Future<Directory> Function()? tempDirProvider,
  })  : _probeHasVideo = probeHasVideo ?? defaultProbeHasVideoStream,
        _tempDir = tempDirProvider;

  final CommandRunner _runner;
  final FileMover _mover;
  final DateTime Function()? _clock;
  final OutputVideoProbe _probeHasVideo;
  final Future<Directory> Function()? _tempDir;
  bool _cancelRequested = false;

  /// 用户取消：立即透传给 runner 杀 FFmpeg 会话，并在本次 run 里生效。
  void cancel() {
    _cancelRequested = true;
    _runner.cancel();
  }

  Future<String> run(ExportJob job,
      {void Function(double p)? onProgress, bool autoSave = true}) async {
    final now = (_clock ?? DateTime.now)();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(now);
    final fileName = '${job.base}_$stamp.${job.ext}';
    final dir = await (_tempDir ?? _defaultTempDir)();
    final temp = '${dir.path}${Platform.pathSeparator}$fileName';
    final existed = File(temp);
    if (existed.existsSync()) existed.deleteSync(); // FFmpeg 不覆盖已有文件
    var moved = false;
    // FFmpeg 导出（直拍/对比）期间屏幕常亮
    await PhotoManagerBridge.setKeepScreenOn(true);
    try {
      if (_cancelRequested) throw ExportCancelled();
      // 数组形式执行（评审建议）：文件名含引号/特殊字符也不会破坏命令
      var args = tokenizeFfmpeg('${job.command} $temp');
      var rc = await _runner.run(args,
          onProgress: onProgress,
          expectedDurationMs: job.expectedDurationMs);
      // 缺陷 2 修复：rc==0 不等于成片可用。AVD/部分设备上 mediacodec 会
      // 静默产出零包（退出码 0、成片仅音频轨、UI 零报错），搬运前必须用
      // FFprobe 校验输出含视频流（probe 在 mover 之前，半成品走 finally 清理）。
      var videoOk = false;
      if (rc == 0 && !_cancelRequested) {
        videoOk = await _probeHasVideo(temp);
      }
      // 硬件编码器（Android=mediacodec / iOS=videotoolbox）在部分设备/尺寸
      // 上会失败（非零退出），或成功但无视频流（静默零包）：均回退软编码
      // mpeg4 一轮。回退前必须删掉第一次运行可能写出的半成品——FFmpeg
      // 遇到已存在输出文件会问 Overwrite? 并以退出码 1 退出。
      // 用户取消（FFmpegKit 取消会话返回非零 rc）不算硬编失败：不回退，
      // 否则点「取消」后还会完整跑一轮 mpeg4 软编才抛 ExportCancelled
      //（Task 6 打码为首个带取消按钮的导出流，据此补此守卫）
      final hw = args.contains('h264_mediacodec')
          ? 'h264_mediacodec'
          : (args.contains('h264_videotoolbox') ? 'h264_videotoolbox' : null);
      if ((rc != 0 || !videoOk) && hw != null && !_cancelRequested) {
        await _dumpLogs(rc != 0 ? 'ROUND1(hw)' : 'ROUND1(hw-novideo)', rc);
        final half = File(temp);
        if (half.existsSync()) half.deleteSync();
        // args 已含输出路径（最后一个参数），只替换编码器两个 token——
        // 再次追加会变成两个输出文件（历史 "already exists" 根因）
        final ci = args.indexOf(hw);
        args = [...args.sublist(0, ci), '-c:v', 'mpeg4', '-q:v', '4', ...args.sublist(ci + 1)];
        rc = await _runner.run(args,
            onProgress: onProgress,
            expectedDurationMs: job.expectedDurationMs);
        videoOk = false;
        if (rc == 0 && !_cancelRequested) {
          videoOk = await _probeHasVideo(temp);
        }
      }
      if (_cancelRequested) throw ExportCancelled();
      if (rc != 0 || !videoOk) {
        // FFmpegKitConfig 在无绑定环境（测试）会抛异步错误，用 zone 兜住
        var (tail, full) = ('', '');
        await runZonedGuarded(() async {
          (tail, full) = await _lastLogs(tailLines: 15);
        }, (e, s) {});
        _dumpLines('FAIL', full);
        throw ExportFailed(rc != 0
            ? 'FFmpeg 退出码 $rc${tail.isEmpty ? '' : '：$tail'}'
            : '导出结果无视频流（编码器未产出画面），已重试仍失败');
      }
      if (!autoSave) {
        // 延迟入相册（直拍成片预览确认环节）：返回临时路径，
        // 由调用方在用户「完成」后调 [saveToGallery]；此处不清理
        moved = true;
        return temp;
      }
      moved = true; // 成功：mover 搬进相册并消费临时文件
      return await _mover.moveToGallery(temp, fileName);
    } finally {
      await PhotoManagerBridge.setKeepScreenOn(false);
      if (!moved) await _mover.cleanTemp(temp); // 失败/取消：清半成品
    }
  }

  /// 把 [run(autoSave: false)] 产出的临时成片存进相册（预览确认后调用）。
  Future<String> saveToGallery(String tempPath, String fileName) =>
      _mover.moveToGallery(tempPath, fileName);

  /// 回退发生时把第一轮的完整日志逐行打进 logcat（release 保留 print）。
  Future<void> _dumpLogs(String tag, int rc) async {
    var (_, full) = ('', '');
    await runZonedGuarded(() async {
      (_, full) = await _lastLogs(tailLines: 0);
    }, (e, s) {});
    _dumpLines(tag, full, rc: rc);
  }

  void _dumpLines(String tag, String full, {int? rc}) {
    if (full.isEmpty) return;
    // ignore: avoid_print
    print('WUJI_EXPORT $tag rc=$rc lines=${full.split('\n').length}');
    var i = 0;
    for (final line in full.split('\n')) {
      i++;
      if (i > 400) break; // 防炸 logcat
      // ignore: avoid_print
      print('WUJI_EXPORT $tag[$i] $line');
    }
  }

  /// 最近一次 FFmpeg 会话的错误日志，返回 (弹窗截尾, 全量)。
  /// 全量日志落盘 cache/wuji-export/last-failure.log
  /// （aac "Conversion failed" 类问题真实原因在尾部几行之前，必须留全量）。
  Future<(String, String)> _lastLogs({int tailLines = 3}) async {
    try {
      final session = await FFmpegKitConfig.getLastCompletedSession();
      if (session is! FFmpegSession) return ('', '');
      final String? s = await session.getAllLogsAsString();
      if (s == null || s.isEmpty) return ('', '');
      final trimmed = s.trim();
      try {
        final dir = await _defaultTempDir();
        File('${dir.path}${Platform.pathSeparator}last-failure.log')
            .writeAsStringSync(trimmed, flush: true);
      } catch (_) {}
      final lines = trimmed.split('\n');
      final tail = lines.length <= tailLines
          ? lines.join(' | ')
          : lines.sublist(lines.length - tailLines).join(' | ');
      return (tail, trimmed);
    } catch (_) {
      return ('', '');
    }
  }

  Future<Directory> _defaultTempDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}wuji-export');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }
}

/// 设备端实现：包 FFmpegKit 异步会话（数组形式，免 shell 拼接注入）。
/// 经全局 [ffmpegGate] 串行——与快照重拍（mosaic_snapshot）互斥，
/// 杜绝两条 FFmpeg 命令在 native 解析/释放滤镜图窗口重叠
/// （冒烟缺陷 3 Scudo 崩溃的产品层缓解）。
class FFmpegKitRunner implements CommandRunner {
  @override
  Future<int> run(
    List<String> args, {
    void Function(double progress)? onProgress,
    int? expectedDurationMs,
  }) {
    return ffmpegGate.run(() {
      final completer = Completer<int>();
      FFmpegKit.executeWithArgumentsAsync(args.toList(),
          (FFmpegSession session) async {
        final ReturnCode? rc = await session.getReturnCode();
        completer.complete(rc?.getValue() ?? -1);
      }, null, (Statistics statistics) {
        if (onProgress == null ||
            expectedDurationMs == null ||
            expectedDurationMs <= 0) {
          return;
        }
        onProgress(
            (statistics.getTime() / expectedDurationMs).clamp(0.0, 1.0));
      });
      return completer.future;
    });
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
