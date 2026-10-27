import 'dart:convert';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';

/// 媒体元信息（导出命令构建的输入：fps/时长/有无音轨）。
class MediaInfo {
  const MediaInfo({
    required this.durationMs,
    required this.width,
    required this.height,
    required this.fps,
    required this.hasAudio,
    this.rotationDegrees = 0,
  });

  final int durationMs;
  final int width;
  final int height;
  final double fps; // 平均帧率
  final bool hasAudio;

  /// 显示方向旋转角（ffprobe `side_data_list[].rotation` 或旧字段
  /// `tags.rotate`，度；竖拍常为 ±90）。
  final int rotationDegrees;

  /// 显示尺寸（video_player / ffmpeg autorotate 后的像素域）：90/270 度时
  /// 宽高交换。打码编辑器与导出滤镜必须用这套值。
  ///
  /// 注意不要把 [width]/[height] 改成显示尺寸——它们是编码尺寸；
  /// compare 需优先取 video_player 显示域（见 compare_page._export 的
  /// resolveSourceSize），probe 值只作控制器未就绪时的回退。
  int get displayWidth => rotationDegrees % 180 == 0 ? width : height;
  int get displayHeight => rotationDegrees % 180 == 0 ? height : width;
}

/// 解析 ffprobe 的媒体信息 JSON（纯函数，宿主可测）。
/// 兼容 `getAllProperties()` 输出：{streams:[...], format:{duration:...}}。
MediaInfo? parseMediaInformationJson(String json) {
  try {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final streams = (map['streams'] as List? ?? const []).cast<Map<String, dynamic>>();
    Map<String, dynamic>? video;
    var hasAudio = false;
    for (final s in streams) {
      if (s['codec_type'] == 'video' && video == null) video = s;
      if (s['codec_type'] == 'audio') hasAudio = true;
    }
    if (video == null) return null;
    final durationSec = double.tryParse(
            '${map['format']?['duration'] ?? video['duration'] ?? ''}') ??
        0.0;
    final width = (video['width'] as num?)?.toInt() ?? 0;
    final height = (video['height'] as num?)?.toInt() ?? 0;
    final fps = _parseRate('${video['avg_frame_rate'] ?? video['r_frame_rate'] ?? ''}');
    return MediaInfo(
      durationMs: (durationSec * 1000).round(),
      width: width,
      height: height,
      fps: fps,
      hasAudio: hasAudio,
      rotationDegrees: _parseRotation(video),
    );
  } catch (_) {
    return null;
  }
}

/// 视频流 rotation：优先 `side_data_list[].rotation`（现代 ffprobe），
/// 回退旧字段 `tags.rotate`；无则 0。
int _parseRotation(Map<String, dynamic> video) {
  int? read(Object? v) {
    if (v is num) return v.round();
    return int.tryParse('${v ?? ''}');
  }

  final side = video['side_data_list'];
  if (side is List) {
    for (final d in side) {
      if (d is! Map) continue;
      final r = read(d['rotation']);
      if (r != null) return r;
    }
  }
  final tags = video['tags'];
  if (tags is Map) {
    final r = read(tags['rotate']);
    if (r != null) return r;
  }
  return 0;
}

/// '30000/1001' → 29.97；'30/1' → 30.0；'0/0' → 0。
double _parseRate(String rate) {
  final parts = rate.split('/');
  if (parts.length != 2) return 0;
  final a = double.tryParse(parts[0]) ?? 0;
  final b = double.tryParse(parts[1]) ?? 0;
  if (b == 0) return 0;
  return a / b;
}

/// 设备端：探测 H.264 硬编编码器是否可用（决定 min / min-gpl 变体，规格 §2）。
Future<bool> hasHardwareH264Encoder() async {
  final session = await FFmpegKit.execute('-hide_banner -encoders');
  final output = (await session.getAllLogsAsString()) ?? '';
  return output.contains('h264_mediacodec');
}

/// 设备端：读取媒体信息。
Future<MediaInfo?> probeMedia(String path) async {
  final session = await FFprobeKit.getMediaInformation(path);
  final info = session.getMediaInformation();
  final props = info?.getAllProperties();
  if (props == null) return null;
  return parseMediaInformationJson(jsonEncode(props));
}
