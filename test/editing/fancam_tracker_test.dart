// NCC 模板跟踪器移植测试（原型 docs/superpowers/prototypes/fancam-follow/track.dart）。
// 合成帧：320×180×3 RGB24，全灰底 (60,60,60)，中央亮红 40×56 方块逐帧右移 2px。
// 约定（DS=4 标准映射）：srcW=1280/srcH=720，方块画在 ds 帧的 (80,90)，
// 其"全分辨率"位置 = ds×4 = (320,360)，归一化 init=(0.25,0.5)。
// 方块必须带纹理（R 通道垂直渐变 170..225）：均匀方块会使模板 tStd 退化到 1e-9 下限、
// NCC 相关值全为舍入噪声，跟踪器永不移动（PC 仿真验证）；真实人像模板天然有纹理。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/fancam_tracker.dart';

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
}
