import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'ffmpeg_serial.dart';
import 'mosaic_graph.dart';
import 'mosaic_region.dart';

/// 快照是否仍可展示（P2-2）：删到 0 个区域时必须立刻失效，
/// 否则带马赛克的旧帧会永久盖在画面上。
bool snapshotStillValid({required int regionCount}) => regionCount > 0;

/// 快照是否对应当前时刻（2026-10-29 预览 T1）：位置一变旧快照立即失效，
/// 避免暂停瞬间露出上一位置的打码效果（用户实测"总是初始画面"）。
bool snapshotMatchesPosition({
  required String? path,
  required Duration? snapshotAt,
  required Duration position,
}) => path != null && snapshotAt == position;

/// 快照抽帧命令（spec §6）：静置帧跑真实打码链，所见即所得。
/// 双 -ss：输入侧先定位到 t-1s（现代 ffmpeg 的输入 seek 会解码到精确位置），
/// 输出侧再补 1s——两级配合兜住不同容器/关键帧间隔的 seek 精度差异，
/// 保证抽到的是 at 时刻那一帧。
/// 路径双引号包裹（FFmpegKit 参数解析同 shell 级引用，见
/// export_service.tokenizeFfmpeg 注释；防路径含空格）。
///
/// 时间轴两套口径（v1.5.26 走查 F1）：滤镜图坐标与 [at] 用 **track 时间**
/// （0=trimStart，与编辑器/导出区间一致）；源视频 seek 用
/// `sourceOffset + at`（直拍内嵌时 sourceOffset=trimStart）。
///
/// [sourceDuration] 非空时做片尾钳制（2026-10-28 反馈 #6）：容器 duration
/// 常比可解码末帧大 1~2 帧，at=片尾时输出侧 -ss 落 EOF 附近解不出帧——
/// 源定位点钳到「源时长 − 150ms」内；cap 为负（极短源）取 0 抽首帧降级。
/// **只影响抽帧定位点**，滤镜图仍用原 at（track 口径坐标不动）。
String buildSnapshotCommand({
  required String srcPath,
  required List<MosaicRegion> regions,
  required Duration at,
  required int srcW,
  required int srcH,
  required String outPath,
  Duration sourceOffset = Duration.zero,
  Duration? sourceDuration,
}) {
  final (graph, out) = buildMosaicGraph(regions,
      srcW: srcW, srcH: srcH, inputLabel: '0:v', at: at);
  const back = Duration(seconds: 1);
  var sourceAt = sourceOffset + at;
  if (sourceDuration != null) {
    const guard = Duration(milliseconds: 150);
    final cap = sourceDuration - guard;
    if (sourceAt > cap) sourceAt = cap > Duration.zero ? cap : Duration.zero;
  }
  final inSeek = sourceAt >= back ? sourceAt - back : Duration.zero;
  final outSeek = sourceAt >= back ? back : sourceAt;
  String s(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(3);
  return '-y -ss ${s(inSeek)} -i "$srcPath" -ss ${s(outSeek)} '
      '-filter_complex "$graph" -map "[$out]" -frames:v 1 "$outPath"';
}

/// 快照固定目录 `<cache>/wuji-mosaic/`（Android 上 Directory.systemTemp
/// 可能不可写，用 path_provider 缓存目录；不存在则创建）。
Future<Directory> mosaicSnapshotDir() async {
  final base = await getTemporaryDirectory();
  final dir = Directory('${base.path}${Platform.pathSeparator}wuji-mosaic');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

/// 快照目录整目录清理（页面 dispose 时调用；best-effort 吞异常）。
Future<void> deleteMosaicSnapshotDir() async {
  try {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}wuji-mosaic');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  } catch (_) {
    // 清理失败不影响主流程（缓存目录系统可回收）
  }
}

/// 生成快照 jpg；失败返回 null（UI 降级显示框线＋轻提示，spec §6）。
/// [sourceDuration] 非空时透传 [buildSnapshotCommand] 做片尾钳制。
/// 首次失败自动用 at−200ms 静默重试一次（2026-10-28 反馈 #6：兜住 EOF
/// 等边界；显示 200ms 前的真实打码帧，用户无感），仍失败才返回 null。
Future<String?> captureMosaicSnapshot({
  required String srcPath,
  required List<MosaicRegion> regions,
  required Duration at,
  required int srcW,
  required int srcH,
  Duration sourceOffset = Duration.zero,
  Duration? sourceDuration,
}) async {
  if (regions.isEmpty) return null;
  final Directory dir;
  try {
    dir = await mosaicSnapshotDir();
  } catch (_) {
    return null; // 临时目录不可用 → 降级
  }

  // 单次尝试：outPath 每次按时间戳生成（重试时天然不同名，写新删旧由 UI 层管）
  Future<String?> attempt(Duration a) async {
    final outPath = '${dir.path}${Platform.pathSeparator}'
        'snap-${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      // 完整命令打 logcat/console：Scudo 崩溃发生在 FFmpegKit 命令解析期
      // (init_complex_filtergraph)，崩溃时需要当时命令做重放定位
      final cmd = buildSnapshotCommand(
          srcPath: srcPath,
          regions: regions,
          at: a,
          srcW: srcW,
          srcH: srcH,
          outPath: outPath,
          sourceOffset: sourceOffset,
          sourceDuration: sourceDuration);
      // ignore: avoid_print
      print('WUJI_SNAPSHOT $cmd');
      // 全局串行闸（缺陷 3 缓解）：与导出命令互斥，快照不得在导出命令
      // 解析/执行窗口内并发起跑（native abort 无法 Dart 捕获，只能防）
      final session = await ffmpegGate.run(() => FFmpegKit.execute(cmd));
      // 注：isValueSuccess 是方法（本包 3.6.7 非 getter），brief 的
      // `rc?.isValueSuccess != true` 是 tear-off 比较恒真，此处按方法调用。
      final rc = await session.getReturnCode();
      if (rc?.isValueSuccess() != true || !File(outPath).existsSync()) {
        return null;
      }
    } catch (_) {
      return null; // FFmpegKit 未初始化/平台异常 → 降级，不阻断编辑
    }
    return outPath;
  }

  final first = await attempt(at);
  if (first != null) return first;
  const retryBack = Duration(milliseconds: 200);
  final retryAt = at >= retryBack ? at - retryBack : Duration.zero;
  return attempt(retryAt);
}
