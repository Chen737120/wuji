import 'keyframes.dart';

/// 构建舞蹈直拍导出的 FFmpeg 命令（规格 §5.3）。
///
/// - crop：[track.cropExpr]（单帧常量、多帧分段线性）；
/// - 不放大规则（Review Focus #3）：输出高 = min(outH=720, 当前框像素高)；
///   多帧时框高变化 → 取**最小框像素高**作为输出高（全程不放大）；
/// - 帧率跟源（不设 fps 滤镜）；音频＝源完整原声 AAC；无音轨源 → `-an`。
String buildFancamCommand({
  required String srcPath,
  required KeyframeTrack track,
  required int srcW,
  required int srcH,
  bool hasAudio = true,
  int outH = 720,
}) {
  if (track.frames.isEmpty) {
    throw ArgumentError('track has no keyframes');
  }

  // 不放大：输出高 = 框像素高里的最小值与 outH 取小
  var outHeight = outH;
  for (final f in track.frames) {
    final pixelH = (f.box.h * srcH).round();
    if (pixelH < outHeight) outHeight = pixelH;
  }
  outHeight = outHeight.clamp(1, outH);

  final cropExpr = track.cropExpr(srcW, srcH, outH: outHeight);
  final audioPart = hasAudio ? '-c:a aac -b:a 128k' : '-an';

  return '-i "$srcPath" '
      '-vf "$cropExpr,scale=-2:$outHeight,setsar=1" '
      '-c:v h264_mediacodec $audioPart '
      '-movflags +faststart';
}
