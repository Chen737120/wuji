import 'dart:ui' show Size;

import 'side_transform.dart';

String _fmtSec(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(3);

/// 构建同屏对比导出的 FFmpeg 命令（规格 §4.2）。
///
/// 对齐语义（与时间微调文案一致）：
/// - offset>0（我的延后 X 秒）→ 老师输入 `-ss X`，老师开头剪掉、我的不变；
/// - offset<0（我的提前 |X| 秒）→ 我的输入 `-ss |X|`，我的开头剪掉、老师不变。
/// - 开头两路都有真实画面（无补帧/黑屏）；
/// - 总长 = 未被剪辑一侧的完整时长：先结束的一侧用 `tpad=stop_duration`
///   冻结末帧补齐（允许的末尾竞争延长），`-t` 兜底取齐。
///
/// 布局：每侧 crop=取样矩形 → scale=-2:720 → hstack=inputs=2。
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
  required double containerAspect, // 画面微调预览容器宽高比（WYSIWYG 基准）
  int outHeight = 720,
}) {
  final lr = left.toSourceRect(leftSrc, containerAspect);
  final rr = right.toSourceRect(rightSrc, containerAspect);

  final fps = fpsCap < 30 ? fpsCap : 30.0;

  final offMs = offset.inMilliseconds;
  final ssTeacher = offMs > 0 ? '-ss ${_fmtSec(offset)} ' : '';
  final ssMine =
      offMs < 0 ? '-ss ${_fmtSec(Duration(milliseconds: -offMs))} ' : '';

  // 总长 = 未被剪辑一侧的完整时长；offset=0 时取两侧较长者
  final total = offMs > 0
      ? myDur
      : offMs < 0
          ? teacherDur
          : (teacherDur > myDur ? teacherDur : myDur);

  // 各侧裁剪后的剩余时长；比 total 短的部分在末尾冻结补齐
  final remainTeacher =
      offMs > 0 ? teacherDur - offset : teacherDur;
  final remainMine = offMs < 0 ? myDur + offset : myDur;
  final extTeacherMs = total.inMilliseconds - remainTeacher.inMilliseconds;
  final extMineMs = total.inMilliseconds - remainMine.inMilliseconds;
  final tpadTeacher = extTeacherMs > 0
      ? 'tpad=stop_duration=${_fmtSec(Duration(milliseconds: extTeacherMs))},'
      : '';
  final tpadMine = extMineMs > 0
      ? 'tpad=stop_duration=${_fmtSec(Duration(milliseconds: extMineMs))},'
      : '';

  final inputs = '$ssTeacher-i "$teacherPath" $ssMine-i "$minePath"';

  final filter =
      '[0:v]${tpadTeacher}crop=${lr.width.round()}:${lr.height.round()}:${lr.left.round()}:${lr.top.round()},scale=-2:$outHeight,setsar=1[v0];'
      '[1:v]${tpadMine}crop=${rr.width.round()}:${rr.height.round()}:${rr.left.round()}:${rr.top.round()},scale=-2:$outHeight,setsar=1[v1];'
      '[v0][v1]hstack=inputs=2,fps=${_fmtRate(fps)}[v]';

  final audioMap = switch (audio) {
    'teacher' => '-map 0:a',
    'mine' => '-map 1:a',
    _ => '-an',
  };

  return '-y $inputs -filter_complex "$filter" '
      '-map "[v]" $audioMap '
      '-c:v h264_mediacodec -pix_fmt yuv420p '
      '-c:a aac -ar 48000 -ac 2 -b:a 128k '
      '-t ${_fmtSec(total)} '
      '-movflags +faststart';
}

String _fmtRate(double fps) => fps == fps.roundToDouble()
    ? fps.toInt().toString()
    : fps.toStringAsFixed(3);
