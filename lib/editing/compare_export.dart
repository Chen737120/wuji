import 'dart:ui' show Size;

import 'overlap.dart';
import 'side_transform.dart';

String _fmtSec(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(3);

/// 构建同屏对比导出的 FFmpeg 命令（规格 §4.2）。
///
/// 布局：每侧 crop=取样矩形 → scale=-2:720 → hstack=inputs=2。
/// 时长：重叠区间 `[max(0,offset), min(teacherDur, myDur+offset))`，
/// 输出 `-t <重叠时长>`；offset>0（我的延后）时老师输入加 `-ss offset`。
/// 音频：teacher→`-map 0:a`；mine→`-map 1:a`；none→`-an`。
/// 帧率：`fps=min(30, teacherFps)`。
String buildCompareCommand({
  required String teacherPath,
  required String minePath,
  required Duration offset,
  required Duration teacherDur,
  required Duration myDur,
  required SideTransform left,
  required SideTransform right,
  required Size leftSrc,
  required Size rightSrc,
  required String audio, // teacher | mine | none
  required double fpsCap,
  int outHeight = 720,
}) {
  final lr = left.toSourceRect(leftSrc, outHeight.toDouble());
  final rr = right.toSourceRect(rightSrc, outHeight.toDouble());

  final fps = fpsCap < 30 ? fpsCap : 30.0;

  // 对齐语义（与时间微调文案一致）：offset>0 = 我的视频延后 X 秒 =
  // 我的流前面补 X 秒首帧静帧（tpad）；offset<0 = 老师流补静帧。
  // 这样输出的同一时刻：老师内容 t，我的内容 t-offset ✓
  final offMs = offset.inMilliseconds;
  final tpadTeacher =
      offset < Duration.zero ? 'tpad=start_duration=${_fmtSec(-offset)},' : '';
  final tpadMine =
      offset > Duration.zero ? 'tpad=start_duration=${_fmtSec(offset)},' : '';

  final inputs = '-i "$teacherPath" -i "$minePath"';

  final filter =
      '[0:v]${tpadTeacher}crop=${lr.width.round()}:${lr.height.round()}:${lr.left.round()}:${lr.top.round()},scale=-2:$outHeight,setsar=1[v0];'
      '[1:v]${tpadMine}crop=${rr.width.round()}:${rr.height.round()}:${rr.left.round()}:${rr.top.round()},scale=-2:$outHeight,setsar=1[v1];'
      '[v0][v1]hstack=inputs=2,fps=${_fmtRate(fps)}[v]';

  // 音频与视频对齐同步延后：对应声轨用 adelay 补同样时长
  final String audioPart;
  switch (audio) {
    case 'teacher':
      audioPart = offMs > 0
          ? ';[0:a]adelay=$offMs:all=1[a]'
          : ';[0:a]anull[a]';
    case 'mine':
      audioPart = offMs < 0
          ? ';[1:a]adelay=${-offMs}:all=1[a]'
          : ';[1:a]anull[a]';
    default:
      audioPart = '';
  }
  final audioMap = audio == 'none' ? '-an' : '-map "[a]"';

  final overlap = overlapLength(teacherDur, myDur, offset);

  return '$inputs -filter_complex "$filter$audioPart" '
      '-map "[v]" $audioMap '
      '-c:v h264_mediacodec -c:a aac -b:a 128k '
      '-t ${_fmtSec(overlap)} '
      '-movflags +faststart';
}

String _fmtRate(double fps) => fps == fps.roundToDouble()
    ? fps.toInt().toString()
    : fps.toStringAsFixed(3);
