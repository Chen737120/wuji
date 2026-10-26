import 'fancam_export.dart' show videoBitrateFor;
import 'ffmpeg_probe.dart' show MediaInfo;
import 'mosaic_graph.dart' show buildMosaicGraph;
import 'mosaic_region.dart';

/// 独立打码导出命令（spec §5.3）：
/// 分辨率/帧率保持源（无全帧 scale）；编码 mediacodec＋码率分档；
/// 音频 AAC 48kHz 立体声标准化——probe 不含音频编码信息，且直拍注释
/// 记录过特殊采样率在 mediacodec 收尾的已知失败（spec L1 修订口径）；
/// 无音轨源走 -an。
///
/// [regions] 为空时滤镜图直通但 `-map "[…]"` 无合法输出标签，调用方
///（宿主 UI）须先拦下空区域导出。
String buildMosaicExportCommand({
  required String srcPath,
  required List<MosaicRegion> regions,
  required MediaInfo info,
}) {
  // 滤镜输入是 autorotate 后的画面：区域坐标域/码率分档都按 display 尺寸
  //（竖拍 rotation=±90 时宽高与编码尺寸相反，F3）
  final (graph, out) = buildMosaicGraph(regions,
      srcW: info.displayWidth, srcH: info.displayHeight, inputLabel: '0:v');
  return '-y -i "$srcPath" '
      '-filter_complex "$graph" '
      '-map "[$out]" '
      '${info.hasAudio ? '-map 0:a:0? ' : ''}'
      '-c:v h264_mediacodec -pix_fmt yuv420p '
      '-b:v ${videoBitrateFor(info.displayHeight)} '
      '${info.hasAudio ? '-c:a aac -ar 48000 -ac 2 -b:a 128k' : '-an'} '
      '-movflags +faststart';
}

/// 4K 判定（F12）：按 **display 尺寸**长边 ≥3840。旧实现只判
/// `height > 2160`，正好 2160 的 4K 横屏漏判；竖拍 2160×3840 也要判到。
bool is4kMedia(MediaInfo info) =>
    info.displayWidth >= 3840 || info.displayHeight >= 3840;

/// 打码导出前提示口径（spec §7）：4K 或时长超 5 分钟。
bool mosaicExportNeedsNotice(MediaInfo info) =>
    is4kMedia(info) || info.durationMs > 300000;
