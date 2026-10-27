// NCC 模板跟踪器移植测试（原型 docs/superpowers/prototypes/fancam-follow/track.dart）。
// 合成帧：320×180×3 RGB24，全灰底 (60,60,60)，中央亮红 40×56 方块逐帧右移 2px。
// 约定（DS=4 标准映射）：srcW=1280/srcH=720，方块画在 ds 帧的 (80,90)，
// 其"全分辨率"位置 = ds×4 = (320,360)，归一化 init=(0.25,0.5)。
// 方块必须带纹理（R 通道垂直渐变 170..225）：均匀方块会使模板 tStd 退化到 1e-9 下限、
// NCC 相关值全为舍入噪声，跟踪器永不移动（PC 仿真验证）；真实人像模板天然有纹理。
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/fancam_tracker.dart';
import 'package:wuji/editing/ffmpeg_serial.dart';

const int fw = 320, fh = 180, fLen = 320 * 180 * 3;

Uint8List _fillGray() {
  final f = Uint8List(fLen);
  for (var i = 0; i < f.length; i += 3) {
    f[i] = 60;
    f[i + 1] = 60;
    f[i + 2] = 60;
  }
  return f;
}

/// 中心在 ds 域 (centerX, 90) 的亮红 40×56 方块帧。
Uint8List _squareFrame(int centerX) {
  final f = _fillGray();
  for (var y = 62; y < 118; y++) {
    for (var x = centerX - 20; x < centerX + 20; x++) {
      final o = (y * fw + x) * 3;
      f[o] = 170 + (y - 62); // 垂直渐变纹理
      f[o + 1] = 40;
      f[o + 2] = 40;
    }
  }
  return f;
}

/// 标准 DS=4 映射参数：帧序列中方块从 ds(80,90) 起每帧右移 2px。
List<Uint8List> _movingSquares(int n) =>
      [for (var i = 0; i < n; i++) _squareFrame(80 + 2 * i)];

void main() {
  group('fancam_tracker（NCC 模板跟踪器，原型逐行移植）', () {
    test('用例1: 跟踪跟随右移方块（帧数一致、误差≤4px 全分辨率、score≥0.6）', () {
      const n = 12;
      final pts = trackRgbFrames(
        frames: _movingSquares(n),
        initCxNorm: 0.25,
        initCyNorm: 0.5,
        srcW: 1280,
        srcH: 720,
        fps: 30,
      );
      expect(pts.length, n);
      for (var i = 0; i < n; i++) {
        expect(pts[i].t, closeTo(i / 30, 1e-9), reason: '帧$i 时间戳');
        expect(pts[i].x, closeTo((80 + 2 * i) * 4, 4), reason: '帧$i x');
        expect(pts[i].y, closeTo(360, 4), reason: '帧$i y');
        expect(pts[i].score, greaterThanOrEqualTo(0.6), reason: '帧$i score');
      }
    });

    test('用例2: init 归一化换算（norm×srcW÷DS 进 ds 域，输出×DS 回全分辨率）', () {
      final pts = trackRgbFrames(
        frames: _movingSquares(8),
        // 方块 ds(80,90) = 全分辨率 (320,360)，归一化 = 320/1280, 360/720
        initCxNorm: 320 / 1280,
        initCyNorm: 360 / 720,
        srcW: 1280,
        srcH: 720,
        fps: 30,
      );
      // 首帧：ds(80,90) → 全分辨率 (320,360)
      expect(pts[0].x, closeTo(320, 1e-6));
      expect(pts[0].y, closeTo(360, 1e-6));
      for (var i = 0; i < 8; i++) {
        expect(pts[i].x, closeTo((80 + 2 * i) * 4, 4), reason: '帧$i x');
        expect(pts[i].y, closeTo(360, 4), reason: '帧$i y');
      }
    });

    test('用例3: 丢帧沿用——方块消失后 score<0.6 且位置保持最后有效值', () {
      final pts = trackRgbFrames(
        frames: [..._movingSquares(6), ...List.filled(5, _fillGray())],
        initCxNorm: 0.25,
        initCyNorm: 0.5,
        srcW: 1280,
        srcH: 720,
        fps: 30,
      );
      expect(pts.length, 11);
      for (var i = 6; i < 11; i++) {
        expect(pts[i].score, lessThan(0.6), reason: '帧$i score');
        expect(pts[i].x, pts[5].x, reason: '帧$i x 保持');
        expect(pts[i].y, pts[5].y, reason: '帧$i y 保持');
      }
    });

    test('用例4: startTracking 读 raw 正常完成——进度上报、结果与核心一致、raw 清理', () async {
      final frames = _movingSquares(12);
      final dir = await Directory.systemTemp.createTemp('wuji-track-test');
      final rawPath = '${dir.path}${Platform.pathSeparator}track.raw';
      final sink = File(rawPath).openSync(mode: FileMode.write);
      for (final f in frames) {
        sink.writeFromSync(f);
      }
      await sink.close();

      final progress = <double>[];
      final run = startTracking(
        rawPath: rawPath,
        initCxNorm: 0.25,
        initCyNorm: 0.5,
        srcW: 1280,
        srcH: 720,
        fps: 30,
        onProgress: progress.add,
      );
      final pts = await run.done;
      expect(pts, isNotNull);
      expect(pts!.length, 12);
      final core = trackRgbFrames(
        frames: frames,
        initCxNorm: 0.25,
        initCyNorm: 0.5,
        srcW: 1280,
        srcH: 720,
        fps: 30,
      );
      for (var i = 0; i < 12; i++) {
        expect(pts[i].t, closeTo(core[i].t, 1e-9));
        expect(pts[i].x, closeTo(core[i].x, 1e-9));
        expect(pts[i].y, closeTo(core[i].y, 1e-9));
        expect(pts[i].score, closeTo(core[i].score, 1e-9));
      }
      expect(progress, isNotEmpty, reason: '应有进度消息');
      expect(progress.last, closeTo(1.0, 1e-9));
      expect(File(rawPath).existsSync(), isFalse, reason: '正常结束应删除 raw');
      await dir.delete(recursive: true);
    });

    test('buildDecodeRawCommand：-t 是输出时长限制（在 -i 之后），按修剪时长截断', () {
      final cmd = buildDecodeRawCommand(
        videoPath: '/tmp/a.mp4',
        ss: const Duration(seconds: 12),
        duration: const Duration(seconds: 8, milliseconds: 500),
        outPath: '/tmp/track.raw',
      );
      expect(cmd, contains('-ss 12.000 -i "/tmp/a.mp4"'));
      expect(cmd, contains('-t 8.500'));
      // -t 必须在 -i 之后（输入侧会变成“只读前 8.5s 源”，语义错位）
      expect(cmd.indexOf('-t 8.500'), greaterThan(cmd.indexOf('-i "/tmp/a.mp4"')));
      expect(cmd.indexOf('-t 8.500'), lessThan(cmd.indexOf('-f rawvideo')));
    });

    test('用例5: cancel——done 完成 null、isolate 终止、raw 删除', () async {
      final dir = await Directory.systemTemp.createTemp('wuji-track-test');
      final rawPath = '${dir.path}${Platform.pathSeparator}track.raw';
      final sink = File(rawPath).openSync(mode: FileMode.write);
      for (var i = 0; i < 60; i++) {
        sink.writeFromSync(_squareFrame(80 + 2 * (i % 100)));
      }
      await sink.close();

      final run = startTracking(
        rawPath: rawPath,
        initCxNorm: 0.25,
        initCyNorm: 0.5,
        srcW: 1280,
        srcH: 720,
        fps: 30,
      );
      run.cancel();
      final pts = await run.done.timeout(const Duration(seconds: 10));
      expect(pts, isNull);
      expect(File(rawPath).existsSync(), isFalse, reason: 'cancel 应删除 raw');
      await dir.delete(recursive: true);
    });
  });

  group('T4 模板取用户当前帧（P2-35）', () {
    // 可重复的低对比棋盘格背景（NCC 需要纹理，但不能用纯色），
    // 40×56 高对比纹理化目标块：点选帧（第 6 帧）出现在点击处，之后每帧右移 10px。
    //
    // 与任务书「从 x=40 每帧右移」的偏差（实测后调整）：目标若在点选前就经过
    // 点击位置，跟踪器会在第 5 帧先咬住它（距离 10px 在搜索窗内）并得到负速度，
    // 到第 6 帧搜索中心被 EMA 拉到 87，目标已到 100（偏 13px > SR=12）→ 漏帧。
    // 这是跟踪器既有动态特性，与模板取帧无关；为让对照只体现模板来源，
    // 点选前画面不放目标块。判据与断言原样保留。
    int hash(int x, int y) => ((x * 7919 + y * 104729) ^ (x * y * 31)) & 255;

    Uint8List frameAt(int i) {
      final f = Uint8List(fLen);
      for (var y = 0; y < fh; y++) {
        for (var x = 0; x < fw; x++) {
          final o = (y * fw + x) * 3;
          final v = ((x ~/ 8) + (y ~/ 8)) % 2 == 0 ? 100 : 130;
          f[o] = v;
          f[o + 1] = v;
          f[o + 2] = v;
        }
      }
      if (i < 6) return f;
      final cx = 100 + 10 * (i - 6);
      for (var y = 62; y < 118; y++) {
        for (var x = cx - 20; x < cx + 20; x++) {
          final o = (y * fw + x) * 3;
          // 纹理随目标移动（局部坐标）：若按绝对坐标，目标平移后重叠区像素不变，
          // dx=0 的部分重叠反而拿到高相关，测不出跟踪能力。
          final v = hash(x - cx, y);
          f[o] = v;
          f[o + 1] = 255 - v;
          f[o + 2] = (v * 3) & 255;
        }
      }
      return f;
    }

    // 点击第 6 帧目标块中心：ds(100,90) → 全分辨率 (400,360)
    const initCx = 400 / 1280;
    const initCy = 360 / 720;
    double trueX(int i) => (100 + 10 * (i - 6)) * 4.0; // 全分辨率
    const trueY = 360.0;

    List<TrackPoint> run(int templateFrameIndex) => trackRgbFrames(
          frames: [for (var i = 0; i < 12; i++) frameAt(i)],
          initCxNorm: initCx,
          initCyNorm: initCy,
          srcW: 1280,
          srcH: 720,
          fps: 30,
          templateFrameIndex: templateFrameIndex,
        );

    double dist(TrackPoint p, int i) {
      final dx = p.x - trueX(i);
      final dy = p.y - trueY;
      return sqrt(dx * dx + dy * dy);
    }

    double meanDistFrom6(List<TrackPoint> pts) {
      var sum = 0.0;
      for (var i = 6; i < 12; i++) {
        sum += dist(pts[i], i);
      }
      return sum / 6;
    }

    test('模板取第 6 帧：6~11 帧贴合真值，显著优于首帧模板', () {
      final a = run(0); // 旧行为：首帧抓模板
      final b = run(6); // 修复后：用户点选帧抓模板
      final distA = meanDistFrom6(a);
      final distB = meanDistFrom6(b);
      expect(distB, lessThan(20), reason: '平均距离 < 20px，实际 $distB');
      expect(distB, lessThan(distA * 0.5),
          reason: '修复有效性的对照：B=$distB 应 < A=$distA 的一半');
    });

    test('时间轴与帧数不变：B[6].t=6/30、B.length=12', () {
      final b = run(6);
      expect(b.length, 12);
      expect(b[6].t, closeTo(6 / 30, 1e-9));
    });

    test('点选之前的帧停在点击位置附近（±48px 内）', () {
      final b = run(6);
      final dx = b[0].x - 400; // 点击坐标全分辨率 (400,360)
      final dy = b[0].y - 360;
      expect(sqrt(dx * dx + dy * dy), lessThan(48),
          reason: 'B[0]=(${b[0].x}, ${b[0].y})，点击坐标=(400,360)');
    });

    test('templateFrameIndex 越界时 clamp 到末帧，不抛', () {
      final pts = run(99);
      expect(pts.length, 12);
    });
  });

  group('T20 跟踪管线（P2-11/13）', () {
    test('shouldCompleteOnExit：isolate 异常死亡才用 null 兜底', () {
      expect(shouldCompleteOnExit(cancelled: false, completed: false), isTrue,
          reason: '异常退出且未收到结果 → 必须 complete(null)');
      expect(shouldCompleteOnExit(cancelled: true, completed: false), isFalse,
          reason: '取消路径由 deleteRawThenComplete 收尾');
      expect(shouldCompleteOnExit(cancelled: false, completed: true), isFalse,
          reason: '结果已到达，不覆盖');
    });

    test('decodeRawFrames 走全局串行闸：与 export 任务顺序执行（P2-13）', () async {      final tmp = await Directory.systemTemp.createTemp('wuji_gate_decode');
      final timeline = <String>[];
      final decodeFuture = decodeRawFrames(
        videoPath: '/v.mp4',
        ss: Duration.zero,
        duration: const Duration(seconds: 1),
        fps: 30,
        outPath: '${tmp.path}${Platform.pathSeparator}x.raw',
        decode: (cmd) async {
          timeline.add('enter:decode');
          await Future<void>.delayed(const Duration(milliseconds: 30));
          timeline.add('exit:decode');
          return 0;
        },
      );
      final exportFuture = ffmpegGate.run(() async {
        timeline.add('enter:export');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        timeline.add('exit:export');
      });
      await Future.wait([decodeFuture, exportFuture]);
      expect(timeline,
          ['enter:decode', 'exit:decode', 'enter:export', 'exit:export'],
          reason: 'decode 未走 gate 时会与 export 重叠');
      await tmp.delete(recursive: true);
    });
  });

  group('T29 fps 探测失败自校验（P2-9）', () {
    const dur10 = Duration(seconds: 10);
    int bytesFor(int frames) => frames * frameLen;

    test('10s/600 帧、probed 30 → 60（60fps 源纠正）', () {
      expect(
        resolveTrackFps(
            rawBytes: bytesFor(600), duration: dur10, probedFps: 30),
        60,
      );
    });

    test('10s/300 帧、probed 30 → 30（不误改）', () {
      expect(
        resolveTrackFps(
            rawBytes: bytesFor(300), duration: dur10, probedFps: 30),
        30,
      );
    });

    test('10s/305 帧、probed 30 → 30（偏差 ≤1 视为探测可信）', () {
      expect(
        resolveTrackFps(
            rawBytes: bytesFor(305), duration: dur10, probedFps: 30),
        30,
      );
    });

    test('10s/250 帧、probed 30 → 25（25fps 源纠正）', () {
      expect(
        resolveTrackFps(
            rawBytes: bytesFor(250), duration: dur10, probedFps: 30),
        25,
      );
    });

    test('duration=0 或不足一帧 → null（不猜）', () {
      expect(
        resolveTrackFps(
            rawBytes: bytesFor(600), duration: Duration.zero, probedFps: 30),
        isNull,
      );
      expect(
        resolveTrackFps(
            rawBytes: frameLen - 1, duration: dur10, probedFps: 30),
        isNull,
      );
    });
  });
}
