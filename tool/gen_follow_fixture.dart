// 一次性开发脚本（本脚本提交；产物 raw/抽帧在 build/、CSV 在 testdata/ 均已 git-ignore）。
// 生成三素材跟踪 CSV fixture（Task 2 三素材指标回归用，skip-if-missing 语义见控制器测试用例6）：
//   便携 ffmpeg 解码 testdata/fancam-motion-demo/{src,src3,src4}.mp4 → 320×180 RGB24 raw
//   → T1 核心 trackRgbFrames（lib/editing/fancam_tracker.dart）
//   → testdata/fancam-follow/track_v{1,3,4}.csv
//     行格式 `t秒,x全分辨率,y全分辨率,score`（4 列逗号分隔，与原型 gen_d5 _load 兼容）；
//     首行含 t=0（T1 语义：模板抓取帧 score=1；原型 track.dart CSV 缺该行，逐帧对齐时
//     本文件第 j+1 行 = 原型第 j 行）。
// 身份核验（代理断言，真实目检留走查会话）：
//   ① 轨迹连续性：相邻帧位移 >100px 即失败（搜索半径 ±12ds=±48px 全分辨率/帧的物理上限）；
//   ② score 分布打印（<0.6 占比、全门控帧占比）；
//   ③ 每 4s 抽帧按跟踪位置画框（drawbox）到 build/fancam-id/，供人工目检；
//   ④ 与原型已交付 CSV（testdata/fancam-motion-demo/track_v*.csv，第八轮颜色门控版、
//      已做过 9 检查点身份核验）逐帧比对——若逐帧一致则身份核验结论直接继承原型。
// 运行（PC，经 flutter test 而非 dart run——T1 fancam_tracker.dart 顶层 import ffmpeg_kit
// flutter 插件，纯 dart VM 编译不了；flutter test VM 可编译且本脚本只用 Process.run，
// 不触碰平台通道。需本机 ffmpeg 路径与 testdata 素材，见 test 壳的门闩）：
//   WUJI_GEN_FIXTURE=1 flutter test test/editing/fancam_follow_fixture_gen_test.dart
// init 点（全分辨率像素；目检 build/fancam-fixture/first_*.jpg 选定，与原型一致——
// 原型 CSV 首行位置即 init 附近，本脚本 dump 首帧复认落在目标躯干上）：
//   v1 src.mp4  (646,375)  C 位金发舞者（白帽黑 T）胸口，归一化 (646/1280, 375/720)
//   v3 src3.mp4 (460,375)  黄衣舞者胸口              归一化 (460/1280, 375/720)
//   v4 src4.mp4 (755,430)  白背心舞者胸口            归一化 (755/1280, 430/720)
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:wuji/editing/fancam_tracker.dart';

const String ffmpeg = r'C:/Users/chen/tools/ffmpeg/ffmpeg-9.0.2-essentials_build/bin/ffmpeg.exe';
const int srcW = 1280, srcH = 720;
const double fps = 30;

class Fixture {
  const Fixture(this.name, this.video, this.outCsv, this.protoCsv,
      this.initPx, this.initPy, this.boxW, this.boxH);

  final String name; // v1 / v3 / v4
  final String video; // 源视频
  final String outCsv; // 生成目标
  final String protoCsv; // 原型已核验 CSV（对照）
  final double initPx, initPy; // init 全分辨率像素
  final int boxW, boxH; // 身份抽帧画框尺寸（回归 Conf 的框）
}

const List<Fixture> fixtures = [
  Fixture('v1', 'testdata/fancam-motion-demo/src.mp4',
      'testdata/fancam-follow/track_v1.csv',
      'testdata/fancam-motion-demo/track_v1.csv', 646, 375, 340, 604),
  Fixture('v3', 'testdata/fancam-motion-demo/src3.mp4',
      'testdata/fancam-follow/track_v3.csv',
      'testdata/fancam-motion-demo/track_v3.csv', 460, 375, 340, 604),
  Fixture('v4', 'testdata/fancam-motion-demo/src4.mp4',
      'testdata/fancam-follow/track_v4.csv',
      'testdata/fancam-motion-demo/track_v4.csv', 755, 430, 272, 484),
];

Future<void> main() async => generateAll();

/// 生成全部 fixture（供 test 壳调用）。
Future<void> generateAll() async {
  Directory('testdata/fancam-follow').createSync(recursive: true);
  Directory('build/fancam-fixture').createSync(recursive: true);
  Directory('build/fancam-id').createSync(recursive: true);
  for (final fx in fixtures) {
    await _runFixture(fx);
  }
  print('全部 fixture 生成完成。');
}

Future<void> _runFixture(Fixture fx) async {
  print('== ${fx.name}: ${fx.video}');
  final rawPath = 'build/fancam-fixture/raw_${fx.name}.raw';
  await _decode(fx.video, rawPath);
  final bytes = File(rawPath).readAsBytesSync();
  final frameLen = W * H * 3;
  if (bytes.length % frameLen != 0) {
    throw StateError('${fx.name}: raw 大小 ${bytes.length} 不是 $frameLen 的倍数');
  }
  final n = bytes.length ~/ frameLen;
  // 零拷贝视图切帧（feed 只读不持有引用）
  final frames = <Uint8List>[
    for (var i = 0; i < n; i++)
      Uint8List.sublistView(bytes, i * frameLen, (i + 1) * frameLen),
  ];
  print('  解码 $n 帧');
  final pts = trackRgbFrames(
    frames: frames,
    initCxNorm: fx.initPx / srcW,
    initCyNorm: fx.initPy / srcH,
    srcW: srcW,
    srcH: srcH,
    fps: fps,
  );

  // ---- 身份核验代理断言 ----
  var maxJump = 0.0;
  var low = 0, gated = 0, scoreSum = 0.0;
  var scoreMin = 2.0;
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i];
    scoreSum += p.score;
    if (p.score < scoreMin) scoreMin = p.score;
    if (p.score < 0.6) low++;
    if (p.score <= -2.0) gated++;
    if (i > 0) {
      final jx = (p.x - pts[i - 1].x).abs();
      final jy = (p.y - pts[i - 1].y).abs();
      if (jx > maxJump) maxJump = jx;
      if (jy > maxJump) maxJump = jy;
    }
  }
  print('  score: min=${scoreMin.toStringAsFixed(3)} '
      'mean=${(scoreSum / pts.length).toStringAsFixed(3)} '
      '<0.6 占 ${(low * 100 / pts.length).toStringAsFixed(1)}% '
      '全门控(-2) 占 ${(gated * 100 / pts.length).toStringAsFixed(1)}%');
  if (maxJump > 100) {
    throw StateError('${fx.name}: 轨迹跳变 ${maxJump.round()}px > 100px/帧，跟踪疑似丢失');
  }
  print('  连续性: 最大相邻帧位移 ${maxJump.toStringAsFixed(1)}px（≤100 代理断言通过）');

  // ---- 写 CSV ----
  final buf = StringBuffer();
  for (final p in pts) {
    buf.write('${p.t.toStringAsFixed(4)},${p.x.toStringAsFixed(1)},'
        '${p.y.toStringAsFixed(1)},${p.score.toStringAsFixed(3)}\n');
  }
  File(fx.outCsv).writeAsStringSync(buf.toString());
  print('  写 ${fx.outCsv}（${pts.length} 行，含 t=0）');

  // ---- 与原型 CSV 逐帧对照（身份核验继承依据）----
  final proto = File(fx.protoCsv);
  if (proto.existsSync()) {
    final pl = proto
        .readAsLinesSync()
        .map((l) => l.split(','))
        .where((p) => p.length >= 4)
        .toList();
    var maxDx = 0.0, maxDy = 0.0, sumD = 0.0, cmp = 0;
    // 本文件第 j+1 行（t=帧 j+1）↔ 原型第 j 行（原型跳过模板抓取帧）
    for (var j = 0; j < pl.length && j + 1 < pts.length; j++) {
      final dx = (pts[j + 1].x - double.parse(pl[j][1])).abs();
      final dy = (pts[j + 1].y - double.parse(pl[j][2])).abs();
      if (dx > maxDx) maxDx = dx;
      if (dy > maxDy) maxDy = dy;
      sumD += dx + dy;
      cmp++;
    }
    print('  原型对照 $cmp 帧: max|Δx|=${maxDx.toStringAsFixed(1)} '
        'max|Δy|=${maxDy.toStringAsFixed(1)} 平均|Δ|=${(sumD / cmp).toStringAsFixed(2)}px');
  } else {
    print('  原型 CSV 缺失（${fx.protoCsv}），跳过对照');
  }

  // ---- 每 4s 抽帧画框（身份目检素材，输出 build/fancam-id/）----
  for (var t = 0; t <= n / fps - 0.5; t += 4) {
    final idx = (t * fps).floor().clamp(0, pts.length - 1);
    // 画框=控制器语义：中心−半宽（clamp 进画面，负值 drawbox 行为不保证）
    final x = (pts[idx].x - fx.boxW / 2).round().clamp(0, srcW - fx.boxW);
    final y = (pts[idx].y - fx.boxH / 2).round().clamp(0, srcH - fx.boxH);
    final out = 'build/fancam-id/${fx.name}_t${t.toString().padLeft(2, '0')}.jpg';
    await _drawBox(fx.video, t, x, y, fx.boxW, fx.boxH, out);
  }
  File(rawPath).deleteSync();
}

Future<void> _decode(String video, String outRaw) async {
  final r = await Process.run(ffmpeg, [
    '-y', '-v', 'error', '-ss', '0', '-i', video,
    '-vf', 'scale=$W:$H,format=rgb24', '-f', 'rawvideo', outRaw,
  ]);
  if (r.exitCode != 0) {
    throw StateError('ffmpeg 解码失败(${r.exitCode}): ${r.stderr}');
  }
}

Future<void> _drawBox(String video, int t, int x, int y, int w, int h,
    String out) async {
  final r = await Process.run(ffmpeg, [
    '-y', '-v', 'error', '-ss', '$t', '-i', video, '-frames:v', '1',
    // 注：厚度参数必须用 t（width 是 w 的别名，会覆盖框宽变成竖线——已踩坑）
    '-vf', 'drawbox=x=$x:y=$y:w=$w:h=$h:color=red:t=6',
    '-q:v', '2', out,
  ]);
  if (r.exitCode != 0) {
    throw StateError('ffmpeg 抽帧失败 t=$t(${r.exitCode}): ${r.stderr}');
  }
}
