// 舞蹈直拍自动跟踪——NCC 模板跟踪器（纯 Dart 核心＋Isolate 封装＋ffmpeg_kit raw 解码）。
// 算法唯一真源：docs/superpowers/prototypes/fancam-follow/track.dart（逐行照搬）。
// 与原型仅三处差异（Controller ruling）：
//   ① fps 参数化（时间戳 = frame/fps，原型硬编码 30）；
//   ② init 归一化坐标参数化（ds 坐标 = norm×srcW÷DS，原型是命令行全分辨率像素÷DS，语义一致）；
//   ③ 输出 TrackPoint 全分辨率坐标（fx*DS）。
// 另一处与原型 CSV 的差别：首帧（模板抓取帧）也输出 t=0 的初始点（score=1），
// 使输出帧数=输入帧数（Task 2 控制器按帧装载需要 t=0；位置即用户点击处，语义不变）。
// 本文件零 flutter import（isolate 安全）；ffmpeg_kit 仅 decodeRawFrames 用（须在主 isolate 调用）。
// 常量名（PW/PH/SR/DS/COLOR_GATE/REG_PER_PX）照搬原型 track.dart，便于逐行对照评审。
// ignore_for_file: constant_identifier_names
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';

const int W = 320, H = 180; // 跟踪分辨率（源 1/4）
const int PW = 40, PH = 56; // 模板尺寸（ds px，≈全分辨率 160x224 躯干）
const int SR = 12; // 搜索半径（ds px，≈±48px 全分辨率/帧）
const double DS = 4.0;
const double COLOR_GATE = 80; // 候选块 RGB 均值与模板的三通道差和上限（0-255）
const double REG_PER_PX = 0.010; // 距离正则：大位移的分数惩罚/搜索像素
const int frameLen = W * H * 3; // 每帧 RGB24 字节数 = 172800

/// 单帧跟踪结果。t 秒；x/y 全分辨率像素（ds×4）；score 为 NCC 置信度，
/// 全门控帧（所有候选被颜色门控拒绝）时为原型的 -2.0。
class TrackPoint {
  const TrackPoint(this.t, this.x, this.y, this.score);

  final double t;
  final double x;
  final double y;
  final double score;
}

/// 纯核心：吃内存中的 RGB24 帧序列（每帧 W×H×3 = 172800 字节），返回逐帧 TrackPoint。
/// initNorm 为用户点击处相对源画面的归一化坐标（点谁跟谁，位置任意）。
List<TrackPoint> trackRgbFrames({
  required List<Uint8List> frames,
  required double initCxNorm,
  required double initCyNorm,
  required int srcW,
  required int srcH,
  required double fps,
}) {
  final tracker = _NccTracker(
    initCxNorm: initCxNorm,
    initCyNorm: initCyNorm,
    srcW: srcW,
    srcH: srcH,
    fps: fps,
  );
  return [for (final f in frames) tracker.feed(f)];
}

/// NCC 模板跟踪器核心（私有，逐行照搬原型：grab 模板混合、NCC 三重循环、
/// 颜色门控、速度 EMA 0.7/0.3、每 10 帧 blend 0.25、best≥0.5 才更新位置）。
class _NccTracker {
  _NccTracker({
    required double initCxNorm,
    required double initCyNorm,
    required int srcW,
    required int srcH,
    required this.fps,
  })  : fx = initCxNorm * srcW / DS, // 原型：全分辨率像素÷DS；norm×srcW 即全分辨率像素
        fy = initCyNorm * srcH / DS,
        lum = List<double>.filled(W * H, 0);

  final double fps;
  double fx, fy, vx = 0.0, vy = 0.0;
  final List<double> tmpl = List<double>.filled(PW * PH, 0);
  double tMean = 0.0, tStd = 0.0, tR = 0.0, tG = 0.0, tB = 0.0;
  bool haveTmpl = false;
  int frame = 0;
  final List<double> lum; // 亮度平面（复用，避免每帧分配）

  // 原型 grab：模板抓取＋RGB 均值（blend<1 时渐进混合自适应）。
  void grab(List<int> f, double x, double y, [double blend = 1.0]) {
    final x0 = (x - PW / 2).round().clamp(0, W - PW);
    final y0 = (y - PH / 2).round().clamp(0, H - PH);
    var sr = 0, sg = 0, sb = 0;
    for (var i = 0; i < PW * PH; i++) {
      final o = ((y0 + i ~/ PW) * W + x0 + i % PW) * 3;
      final r = f[o].toDouble(), g = f[o + 1].toDouble(), b = f[o + 2].toDouble();
      tmpl[i] = tmpl[i] * (1 - blend) + (0.299 * r + 0.587 * g + 0.114 * b) * blend;
      sr += r.toInt();
      sg += g.toInt();
      sb += b.toInt();
    }
    final n = PW * PH;
    tR = tR * (1 - blend) + sr / n * blend;
    tG = tG * (1 - blend) + sg / n * blend;
    tB = tB * (1 - blend) + sb / n * blend;
    tMean = tmpl.fold<double>(0, (a, b) => a + b) / tmpl.length;
    var s = 0.0;
    for (final v in tmpl) {
      s += (v - tMean) * (v - tMean);
    }
    tStd = sqrt(max(s / tmpl.length, 1e-9));
  }

  /// 喂入一帧，返回该帧 TrackPoint。丢帧沿用是内在行为：best<0.5 时 fx/fy 不动。
  /// 注意 [f] 仅在本次调用内被读取（不持有引用），调用方可复用同一缓冲区。
  TrackPoint feed(List<int> f) {
    for (var i = 0; i < W * H; i++) {
      final o = i * 3;
      lum[i] = 0.299 * f[o] + 0.587 * f[o + 1] + 0.114 * f[o + 2];
    }
    double score;
    if (!haveTmpl) {
      grab(f, fx, fy);
      haveTmpl = true;
      score = 1.0; // 首帧即模板抓取帧，视为完全置信
    } else {
      final px = (fx + vx).clamp(PW / 2 + SR, W - PW / 2 - SR);
      final py = (fy + vy).clamp(PH / 2 + SR, H - PH / 2 - SR);
      // 原型初值 -2.0：全门控帧保持 -2.0（若误初始化为正值会触发位置漂移）
      var best = -2.0, bestEff = -2.0, bdx = 0, bdy = 0;
      for (var dy = -SR; dy <= SR; dy++) {
        final yy0 = (py + dy - PH / 2).round();
        if (yy0 < 0 || yy0 + PH > H) continue;
        for (var dx = -SR; dx <= SR; dx++) {
          final xx0 = (px + dx - PW / 2).round();
          if (xx0 < 0 || xx0 + PW > W) continue;
          var sw = 0.0, sw2 = 0.0, stw = 0.0, sr = 0, sg = 0, sb = 0;
          for (var yy = 0; yy < PH; yy++) {
            final row = (yy0 + yy) * W + xx0;
            final trow = yy * PW;
            for (var xx = 0; xx < PW; xx++) {
              final pxi = row + xx, l = lum[pxi], o = pxi * 3;
              sw += l;
              sw2 += l * l;
              stw += tmpl[trow + xx] * l;
              sr += f[o];
              sg += f[o + 1];
              sb += f[o + 2];
            }
          }
          final n = (PW * PH).toDouble();
          final wMean = sw / n;
          final wStd = sqrt(max(sw2 / n - wMean * wMean, 1e-9));
          final r = (stw - n * tMean * wMean) / (n * tStd * wStd + 1e-9);
          final cGate = (sr / n - tR).abs() + (sg / n - tG).abs() + (sb / n - tB).abs();
          final eff = cGate > COLOR_GATE ? -2.0 : r - REG_PER_PX * sqrt(dx * dx + dy * dy.toDouble());
          if (eff > bestEff) {
            bestEff = eff;
            best = r;
            bdx = dx;
            bdy = dy;
          }
        }
      }
      if (best >= 0.5) {
        fx = px + bdx;
        fy = py + bdy;
        vx = vx * 0.7 + bdx * 0.3;
        vy = vy * 0.7 + bdy * 0.3;
      }
      if (frame % 10 == 0) grab(f, fx, fy, 0.25); // 模板渐进混合自适应
      score = best;
    }
    final pt = TrackPoint(frame / fps, fx * DS, fy * DS, score);
    frame++;
    return pt;
  }
}

/// 解码视频为 raw 临时文件（`<cache>/wuji-track/`，Task 4 页面侧创建并负责最终清理），
/// 供 [startTracking] 逐帧读取。返回 outPath。
///
/// [duration] 是**输出侧**时长限制（`-t` 放在 `-i` 之后）：只解码修剪区间，
/// 否则长源视频会一直解码到结尾（v1.5.26 走查 F4：10 分钟源剪 40 秒会写
/// 约 3GB raw）。[fps] 不进命令，仅供调用方语义/预期帧数。
/// 失败抛异常（携带 ffmpeg 日志）。
Future<String> decodeRawFrames({
  required String videoPath,
  required Duration ss,
  required Duration duration,
  required double fps,
  required String outPath,
}) async {
  // ffmpeg 不会自动建目录：确保父目录存在（recursive 对已存在目录是幂等 no-op）。
  Directory(outPath).parent.createSync(recursive: true);
  final session = await FFmpegKit.execute(buildDecodeRawCommand(
    videoPath: videoPath,
    ss: ss,
    duration: duration,
    outPath: outPath,
  ));
  // 注：isValueSuccess 是方法（本包 3.6.7 非 getter，见 mosaic_snapshot.dart 踩坑注释）。
  final rc = await session.getReturnCode();
  if (rc?.isValueSuccess() != true) {
    final logs = await session.getAllLogsAsString();
    throw Exception('fancam decodeRawFrames 失败 rc=$rc: $logs');
  }
  return outPath;
}

/// raw 解码命令（纯函数可测）：
/// `-y -ss <ss> -i "<path>" -vf scale=320:180,format=rgb24 -t <duration> -f rawvideo "<out>"`。
/// **`-t` 必须在 `-i` 之后**（输出时长限制）；放到 `-i` 前面会变成输入
/// 限制，只读源文件前 duration 秒，与修剪起点错位。
String buildDecodeRawCommand({
  required String videoPath,
  required Duration ss,
  required Duration duration,
  required String outPath,
}) {
  String s(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(3);
  return '-y -ss ${s(ss)} -i "$videoPath" '
      '-vf scale=$W:$H,format=rgb24 -t ${s(duration)} -f rawvideo "$outPath"';
}

/// 一次跟踪运行：[done] 完成（成功=轨迹，失败/取消=null）；[cancel] 立即终止
/// （isolate.kill ＋删 raw ＋done 完成 null——Review Focus #4：不能只置标志位）。
class TrackingRun {
  TrackingRun._(this.done, this._onCancel);

  final Future<List<TrackPoint>?> done;
  final void Function() _onCancel;
  bool _cancelled = false;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel();
  }
}

/// 后台 Isolate 跟踪：逐帧读 raw 文件喂核心，onProgress 每 ≥24 帧报一次
/// （分母 = raw 文件大小÷每帧字节数）。正常结束由 isolate 侧删除 raw（finally 语义）；
/// cancel 路径由主侧删除——两条路径互斥，双删时吞异常。
TrackingRun startTracking({
  required String rawPath,
  required double initCxNorm,
  required double initCyNorm,
  required int srcW,
  required int srcH,
  required double fps,
  void Function(double p)? onProgress,
}) {
  final completer = Completer<List<TrackPoint>?>();
  final port = ReceivePort();
  final exitPort = ReceivePort();
  Isolate? isolate;
  var cancelled = false;

  port.listen((msg) {
    if (msg is double) {
      if (!cancelled) onProgress?.call(msg);
    } else if (cancelled) {
      // 迟到的结果（cancel 后 isolate 恰好完成）：丢弃，由 exit 端口完成 null
    } else if (!completer.isCompleted) {
      completer.complete(msg as List<TrackPoint>?);
      port.close();
    }
  });

  // cancel 路径：删除 raw（重试覆盖 Windows 句柄回收窗口；Linux/Android 首次即成），
  // 删除定局（成功或放弃——残留于 cache 由系统回收，不阻塞取消）后完成 done=null。
  void deleteRawThenComplete(int attempt) {
    try {
      final f = File(rawPath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      if (attempt < 10) {
        Timer(Duration(milliseconds: 50 * (attempt + 1)), () => deleteRawThenComplete(attempt + 1));
        return;
      }
    }
    if (!completer.isCompleted) completer.complete(null);
    port.close();
  }

  // isolate 终止信号（kill 或正常退出都会发）。
  // 注意不能用主 port 的 onDone：对端 isolate 被 kill 不产生端口关闭事件。
  // 且 exit 消息不保证 VM 已回收 isolate 的文件句柄（Windows 锁）——删除需退避重试。
  exitPort.listen((_) {
    exitPort.close();
    if (cancelled) deleteRawThenComplete(0);
    // 非 cancel 的正常退出：入口 finally 必发结果消息，由结果分支完成。
  });

  Isolate.spawn(
    _trackEntry,
    _TrackRequest(
      send: port.sendPort,
      rawPath: rawPath,
      initCxNorm: initCxNorm,
      initCyNorm: initCyNorm,
      srcW: srcW,
      srcH: srcH,
      fps: fps,
    ),
    onExit: exitPort.sendPort,
  ).then((iso) {
    if (cancelled || completer.isCompleted) {
      iso.kill(priority: Isolate.immediate); // spawn 期间已取消/已结束，立刻回收
    } else {
      isolate = iso;
    }
  }).catchError((Object _) {
    // spawn 失败：isolate 从未存在，exit 端口不会有消息，此处收尾
    //（cancel 路径的 raw 已由 onCancel 立即删——文件从未被打开）。
    exitPort.close();
    if (!completer.isCompleted) completer.complete(null);
  });

  return TrackingRun._(
    completer.future,
    () {
      cancelled = true;
      try {
        isolate?.kill(priority: Isolate.immediate);
      } catch (_) {}
      try {
        File(rawPath).deleteSync(); // isolate 尚未打开文件时立即删；句柄被锁时由 exit 端口兜底再删
      } catch (_) {}
      // done 完成 null 统一在 exit 端口（isolate 终止信号）：
      // 保证 await done 返回时删除已发生；spawn 在途时由上方 then 分支 kill → exit。
    },
  );
}

class _TrackRequest {
  const _TrackRequest({
    required this.send,
    required this.rawPath,
    required this.initCxNorm,
    required this.initCyNorm,
    required this.srcW,
    required this.srcH,
    required this.fps,
  });

  final SendPort send;
  final String rawPath;
  final double initCxNorm;
  final double initCyNorm;
  final int srcW;
  final int srcH;
  final double fps;
}

/// Isolate 入口：无论成败都发一次结果消息（成功=轨迹 / 失败=null），
/// 并在 finally 删除 raw（正常结束路径的唯一删除点；cancel 时本函数已被 kill）。
Future<void> _trackEntry(_TrackRequest req) async {
  List<TrackPoint>? result;
  try {
    result = await _readAndTrack(req);
  } catch (_) {
    result = null;
  } finally {
    try {
      File(req.rawPath).deleteSync();
    } catch (_) {}
    req.send.send(result);
  }
}

Future<List<TrackPoint>?> _readAndTrack(_TrackRequest req) async {
  final file = File(req.rawPath);
  final total = (await file.length()) ~/ frameLen;
  if (total <= 0) return null;
  final tracker = _NccTracker(
    initCxNorm: req.initCxNorm,
    initCyNorm: req.initCyNorm,
    srcW: req.srcW,
    srcH: req.srcH,
    fps: req.fps,
  );
  final buf = Uint8List(frameLen); // 每帧复用（feed 不持有帧引用）
  final points = <TrackPoint>[];
  var lastReported = -1;
  // 每帧单独 open/close（开销 ~µs 级，NCC 每帧 ~10ms 才是大头）：句柄锁窗口缩到
  // 单帧之内，cancel 被 kill 后文件能尽快删除（Windows 下长期持锁会阻塞删除）。
  for (var i = 0; i < total; i++) {
    final raf = await file.open();
    try {
      await raf.setPosition(i * frameLen);
      var got = 0;
      while (got < frameLen) {
        final n = await raf.readInto(buf, got);
        if (n <= 0) return null; // 文件比 total 帧短 → 失败
        got += n;
      }
    } finally {
      await raf.close();
    }
    points.add(tracker.feed(buf));
    if (i - lastReported >= 24) {
      lastReported = i;
      req.send.send((i + 1) / total);
    }
  }
  req.send.send(1.0);
  return points;
}
