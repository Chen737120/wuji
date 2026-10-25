import 'dart:io';
import 'dart:math' as math;

import 'keyframes.dart';

/// 16 宏块对齐（最近取整，下限 16）。
///
/// mediacodec 编码面按 16 的倍数编码：非 16 倍数的输出会被 pad 到宏块
/// 边界、再用 SPS conformance window 裁回显示尺寸。裁剪信号本身是标准的
/// （相册/系统播放器遵循），但部分设备的 TextureView 播放路径不应用该
/// 裁剪——padding 区被一起渲染：右侧垃圾色度列=绿条、底部零值行=黑条
/// （2026-10-12 真机实证：278×534 的成片编码面为 288×544，右裁10底裁10，
/// 用户报告"成片预览右缘绿条+底部黑条，相册播放正常"）。v1.5.23 的
/// 偶数对齐防不了它（278×534 本就是偶数），必须 16 对齐让编码面=显示面，
/// padding 从根上消失。
int align16(int v) => math.max(16, ((v + 8) ~/ 16) * 16);

/// 导出输出尺寸：不放大规则（高取 crop 原生高与 [outH] 的较小者）+
/// 16 宏块对齐；宽按 crop 高宽比缩放后同样对齐（纵横比偏差 ≤ ~1.5%，
/// 不可感知）。预览参数单与导出命令共用，保证参数单即真实输出。
(int, int) fancamOutputSize(int cropW, int cropH, {int outH = 1080}) {
  final h = align16(math.min(outH, cropH));
  final w = align16((cropW * h / cropH).round());
  return (w, h);
}

/// 构建舞蹈直拍导出的 FFmpeg 命令（规格 §5.3）。
///
/// - 修剪（2026-10-05 需求 #3）：[trimStart]/[trimEnd] 输入侧裁剪，
///   关键帧时间轴已相对修剪起点（-ss 在 -i 前，滤镜时间 t 从 0 起）；
/// - crop：[track.cropExpr]（单帧常量；多帧 = 固定最大框 + x/y 逐帧跟随）；
/// - 不放大规则（Review Focus #3）：输出高 = min(outH=1080, 固定框像素高)，
///   且输出宽高 **16 宏块对齐**（[fancamOutputSize]，v1.5.24 起）；
/// - 帧率跟源（不设 fps 滤镜）；音频＝源完整原声 AAC；无音轨源 → `-an`。
String buildFancamCommand({
  required String srcPath,
  required KeyframeTrack track,
  required int srcW,
  required int srcH,
  bool hasAudio = true,
  int outH = 1080,
  Duration trimStart = Duration.zero,
  Duration? trimEnd,
}) {
  if (track.frames.isEmpty) {
    throw ArgumentError('track has no keyframes');
  }

  final (cropW, cropH) = track.fixedCropSize(srcW, srcH);
  final (outW, outHeight) = fancamOutputSize(cropW, cropH, outH: outH);

  final cropExpr = track.cropExpr(srcW, srcH);
  // 音频显式标准化（docx 排查建议）：aac 48kHz 立体声，避免源特殊采样率
  // 在编码收尾阶段触发 "2 frames left in the queue on closing" 类失败
  final audioPart =
      hasAudio ? '-c:a aac -ar 48000 -ac 2 -b:a 128k' : '-an';

  // 视频码率显式给定（2026-10-08 需求 #1）：mediacodec 不给 -b:v 时按编码器
  // 默认低码率出片，放大看毛边明显；按输出高分档给到高质量码率
  // （1080p≈16Mbps ≈ 0.25bpp@30fps，与相册原图放大观感对齐）
  final videoBitrate = videoBitrateFor(outHeight);

  // 硬件编码器按平台：Android=mediacodec；iOS=VideoToolbox（ffmpeg_kit
  // min 变体内建，同为硬编；失败时 ExportService 回退 mpeg4 软编兜底）
  final videoCodec = Platform.isIOS ? 'h264_videotoolbox' : 'h264_mediacodec';

  final trimPart = trimStart > Duration.zero
      ? '-ss ${(trimStart.inMilliseconds / 1000).toStringAsFixed(3)} '
      : '';
  final durPart = trimEnd != null
      ? '-t ${((trimEnd - trimStart).inMilliseconds / 1000).toStringAsFixed(3)} '
      : '';

  return '-y $trimPart-i "$srcPath" $durPart'
      '-vf "$cropExpr,scale=$outW:$outHeight,setsar=1" '
      '-c:v $videoCodec -pix_fmt yuv420p -b:v $videoBitrate $audioPart '
      '-movflags +faststart';
}

/// 按输出高的视频码率分档（直拍/对比/打码共用）：1080p 级 16M，720p 级 10M，
/// 更小 6M。设了 -b:v 后 mediacodec 才会按高码率编码。
String videoBitrateFor(int outHeight) =>
    outHeight >= 1000 ? '16M' : (outHeight >= 700 ? '10M' : '6M');
