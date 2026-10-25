import 'dart:io';
import 'dart:math' as math;

import 'keyframes.dart';
import 'mosaic_graph.dart';
import 'mosaic_region.dart';

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
/// - 帧率跟源（不设 fps 滤镜）；音频＝源完整原声 AAC；无音轨源 → `-an`；
/// - 打码（Task 7）：[regions] 非空时 `-vf` 切 `-filter_complex`——
///   [buildMosaicGraph] 串联打码（split/crop/效果/overlay）后再接
///   crop/scale，**打码在前、裁剪在后**（spec §5.2：裁剪改坐标域，
///   打码区域坐标为源画面系，须在裁剪前生效）；空列表命令与无打码
///   版本逐字节一致（零回归）。`-ss` 前置使滤镜 t 从 0 起，与关键帧
///   时间轴相对修剪起点的语义一致（spec §8）；filter_complex 下显式
///   `-map "[vout]" -map 0:a?`（可选 map，无音轨源无害）。
String buildFancamCommand({
  required String srcPath,
  required KeyframeTrack track,
  required int srcW,
  required int srcH,
  List<MosaicRegion> regions = const [],
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

  // 视频段：空 regions 走原 -vf 链（与旧版逐字节一致，零回归）；非空时
  // filter_complex——buildMosaicGraph(inputLabel: '0:v') 输出自动带方括号、
  // 返回 outLabel 裸名，链尾接 crop/scale 产出 [vout] 并显式 map。
  final String videoPart;
  if (regions.isEmpty) {
    videoPart = '-vf "$cropExpr,scale=$outW:$outHeight,setsar=1" ';
  } else {
    final (graph, out) = buildMosaicGraph(
      regions,
      srcW: srcW,
      srcH: srcH,
      inputLabel: '0:v',
    );
    videoPart = '-filter_complex "$graph;[$out]$cropExpr,'
        'scale=$outW:$outHeight,setsar=1[vout]" -map "[vout]" -map 0:a? ';
  }
  return '-y $trimPart-i "$srcPath" $durPart'
      '$videoPart'
      '-c:v $videoCodec -pix_fmt yuv420p -b:v $videoBitrate $audioPart '
      '-movflags +faststart';
}

/// 构建自动跟踪（sendcmd 驱动）导出的 FFmpeg 命令。
///
/// 与 [buildFancamCommand] 的差异仅在裁剪来源：手动版把逐帧 crop 表达式
/// 内联进滤镜参数（受 ~4KB 单滤镜参数硬限制）；跟随版滤镜链只含
/// `sendcmd=f=<cmdsPath>` 命令文件路径——每帧两行、无长度限制，文件内容
/// 由 `FollowSession.buildSendCmd()` 生成，落盘由调用方页面负责
/// （`getTemporaryDirectory()/wuji-export/follow-<millis>.txt`），本函数只引用路径。
/// 其余与手动同口径：
/// - x0/y0 = [centers] 首帧偶数化左上角（`(x−cropW/2).round() & ~1`，与
///   sendcmd 首帧行同式，避免首帧闪跳）；
/// - 输出尺寸 [fancamOutputSize]（不放大＋16 对齐）、码率 [videoBitrateFor]、
///   音频段（hasAudio ? AAC 标准化 : -an）、编码器与 trim 拼装（`-ss` 前置
///   → 滤镜 t 从 0 起，sendcmd 时间相对修剪起点，与 centers 时间轴一致）；
/// - 打码同手动（spec §5.2）：[regions] 非空时 [buildMosaicGraph] 串联在前、
///   sendcmd/crop/scale 在后，`-map "[vout]" -map 0:a?`。
String buildFancamFollowCommand({
  required String srcPath,
  required String cmdsPath,
  required int cropW,
  required int cropH,
  required int srcW,
  required int srcH,
  required List<({double t, double x, double y})> centers,
  bool hasAudio = true,
  int outH = 1080,
  Duration trimStart = Duration.zero,
  Duration? trimEnd,
  List<MosaicRegion> regions = const [],
}) {
  if (centers.isEmpty) {
    throw ArgumentError('centers has no frames');
  }

  final (outW, outHeight) = fancamOutputSize(cropW, cropH, outH: outH);
  final x0 = (centers.first.x - cropW / 2).round() & ~1;
  final y0 = (centers.first.y - cropH / 2).round() & ~1;
  final followSeg =
      'sendcmd=f=$cmdsPath,crop=$cropW:$cropH:$x0:$y0,'
      'scale=$outW:$outHeight,setsar=1';

  // 以下与 buildFancamCommand 同源（音频标准化 / 码率分档 / 平台硬编 /
  // trim 拼装），保持两条导出路径口径一致。
  final audioPart =
      hasAudio ? '-c:a aac -ar 48000 -ac 2 -b:a 128k' : '-an';
  final videoBitrate = videoBitrateFor(outHeight);
  final videoCodec = Platform.isIOS ? 'h264_videotoolbox' : 'h264_mediacodec';

  final trimPart = trimStart > Duration.zero
      ? '-ss ${(trimStart.inMilliseconds / 1000).toStringAsFixed(3)} '
      : '';
  final durPart = trimEnd != null
      ? '-t ${((trimEnd - trimStart).inMilliseconds / 1000).toStringAsFixed(3)} '
      : '';

  final String videoPart;
  if (regions.isEmpty) {
    videoPart = '-vf "$followSeg" ';
  } else {
    final (graph, out) = buildMosaicGraph(
      regions,
      srcW: srcW,
      srcH: srcH,
      inputLabel: '0:v',
    );
    videoPart = '-filter_complex "$graph;[$out]$followSeg[vout]" '
        '-map "[vout]" -map 0:a? ';
  }
  return '-y $trimPart-i "$srcPath" $durPart'
      '$videoPart'
      '-c:v $videoCodec -pix_fmt yuv420p -b:v $videoBitrate $audioPart '
      '-movflags +faststart';
}

/// 按输出高的视频码率分档（直拍/对比/打码共用）：1080p 级 16M，720p 级 10M，
/// 更小 6M。设了 -b:v 后 mediacodec 才会按高码率编码。
String videoBitrateFor(int outHeight) =>
    outHeight >= 1000 ? '16M' : (outHeight >= 700 ? '10M' : '6M');
