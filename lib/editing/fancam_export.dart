import 'dart:io';

import 'keyframes.dart';

/// 构建舞蹈直拍导出的 FFmpeg 命令（规格 §5.3）。
///
/// - 修剪（2026-10-05 需求 #3）：[trimStart]/[trimEnd] 输入侧裁剪，
///   关键帧时间轴已相对修剪起点（-ss 在 -i 前，滤镜时间 t 从 0 起）；
/// - crop：[track.cropExpr]（单帧常量；多帧 = 固定最大框 + x/y 逐帧跟随）；
/// - 不放大规则（Review Focus #3）：输出高 = min(outH=1080, 固定框像素高)，
///   且**偶数化**（h264_mediacodec 不接受奇数尺寸）；
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

  final (_, cropH) = track.fixedCropSize(srcW, srcH);
  var outHeight = outH;
  if (cropH < outHeight) outHeight = cropH;
  outHeight = outHeight & ~0x1; // 偶数化
  outHeight = outHeight.clamp(2, outH);

  final cropExpr = track.cropExpr(srcW, srcH);
  // 音频显式标准化（docx 排查建议）：aac 48kHz 立体声，避免源特殊采样率
  // 在编码收尾阶段触发 "2 frames left in the queue on closing" 类失败
  final audioPart =
      hasAudio ? '-c:a aac -ar 48000 -ac 2 -b:a 128k' : '-an';

  // 视频码率显式给定（2026-10-08 需求 #1）：mediacodec 不给 -b:v 时按编码器
  // 默认低码率出片，放大看毛边明显；按输出高分档给到高质量码率
  // （1080p≈16Mbps ≈ 0.25bpp@30fps，与相册原图放大观感对齐）
  final videoBitrate = _videoBitrate(outHeight);

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
      '-vf "$cropExpr,scale=-2:$outHeight,setsar=1" '
      '-c:v $videoCodec -pix_fmt yuv420p -b:v $videoBitrate $audioPart '
      '-movflags +faststart';
}

/// 按输出高的视频码率分档（直拍/对比共用）：1080p 级 16M，720p 级 10M，
/// 更小 6M。设了 -b:v 后 mediacodec 才会按高码率编码。
String _videoBitrate(int outHeight) =>
    outHeight >= 1000 ? '16M' : (outHeight >= 700 ? '10M' : '6M');
