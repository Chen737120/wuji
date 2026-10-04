import 'dart:ui' show Size;

import '../data/db.dart';
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

  // 输入顺序：0=老师（可能带 -ss），1=我的
  final ssTeacher = offset > Duration.zero ? '-ss ${_fmtSec(offset)} ' : '';
  final inputs = '$ssTeacher-i "$teacherPath" -i "$minePath"';

  final filter =
      '[0:v]crop=${lr.width.round()}:${lr.height.round()}:${lr.left.round()}:${lr.top.round()},scale=-2:$outHeight,setsar=1[v0];'
      '[1:v]crop=${rr.width.round()}:${rr.height.round()}:${rr.left.round()}:${rr.top.round()},scale=-2:$outHeight,setsar=1[v1];'
      '[v0][v1]hstack=inputs=2,fps=${_fmtRate(fps)}[v]';

  final audioMap = switch (audio) {
    'teacher' => '-map 0:a',
    'mine' => '-map 1:a',
    _ => '-an',
  };

  final overlap = overlapLength(teacherDur, myDur, offset);

  return '$inputs -filter_complex "$filter" '
      '-map "[v]" $audioMap '
      '-c:v h264_mediacodec -c:a aac -b:a 128k '
      '-t ${_fmtSec(overlap)} '
      '-movflags +faststart';
}

String _fmtRate(double fps) => fps == fps.roundToDouble()
    ? fps.toInt().toString()
    : fps.toStringAsFixed(3);
