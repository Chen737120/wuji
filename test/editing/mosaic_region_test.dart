import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/crop_box.dart';
import 'package:wuji/editing/keyframes.dart';
import 'package:wuji/editing/mosaic_region.dart';

void main() {
  group('MosaicRegion 模型', () {
    test('默认效果模糊（2026-10-28 反馈 #5）、强度中档', () {
      final r = MosaicRegion(id: 'r1', track: KeyframeTrack(duration: const Duration(seconds: 10))..reset(const CropBox(cx: 0.5, cy: 0.5, w: 0.2, h: 0.2)));
      expect(r.effect, MosaicEffect.blur);
      expect(r.strength, 1);
    });

    test('马赛克缩小目标宽按档位 32/16/8', () {
      final r = MosaicRegion(id: 'r1', track: KeyframeTrack(duration: const Duration(seconds: 10))..reset(const CropBox(cx: 0.5, cy: 0.5, w: 0.2, h: 0.2)));
      expect(r.mosaicTargetWidth(0), 32);
      expect(r.mosaicTargetWidth(1), 16);
      expect(r.mosaicTargetWidth(2), 8);
    });

    test('gblur sigma 参数化：短边 16..2000 × 三档恒 >0 且 <=30', () {
      final r = MosaicRegion(id: 'r1', track: KeyframeTrack(duration: const Duration(seconds: 10))..reset(const CropBox(cx: 0.5, cy: 0.5, w: 0.2, h: 0.2)));
      for (var short = 16; short <= 2000; short += 16) {
        for (var strength = 0; strength <= 2; strength++) {
          final s = r.blurSigma(short, strength);
          expect(s, greaterThan(0), reason: 'short=$short strength=$strength');
          expect(s, lessThanOrEqualTo(30),
              reason: 'short=$short strength=$strength');
        }
      }
    });

    test('gblur sigma：短边 324 / 中档 ≈ 9.72', () {
      final r = MosaicRegion(id: 'r1', track: KeyframeTrack(duration: const Duration(seconds: 10))..reset(const CropBox(cx: 0.5, cy: 0.5, w: 0.2, h: 0.2)));
      expect(r.blurSigma(324, 1), closeTo(9.72, 0.01));
    });

    test('gblur sigma：同一短边下强度越大 sigma 越大', () {
      final r = MosaicRegion(id: 'r1', track: KeyframeTrack(duration: const Duration(seconds: 10))..reset(const CropBox(cx: 0.5, cy: 0.5, w: 0.2, h: 0.2)));
      for (final short in [100, 324, 600]) {
        expect(r.blurSigma(short, 0), lessThan(r.blurSigma(short, 1)),
            reason: 'short=$short');
        expect(r.blurSigma(short, 1), lessThan(r.blurSigma(short, 2)),
            reason: 'short=$short');
      }
    });

    test('maxRegions = 5', () => expect(MosaicRegion.maxRegions, 5));
  });

  group('KeyframeTrack.topLeftExprs / topLeftAt', () {
    // 1280x720 源；两帧最大框 0.3 → fixedCropSize = (384, 216)（均偶数）。
    // 尺寸入参一律用 fixedCropSize 推导（与 Task 2 导出消费方式一致），
    // 不硬编码——plan 原稿硬编码 288 系算术错误（0.3*720=216）。
    late KeyframeTrack track;
    setUp(() {
      track = KeyframeTrack(duration: const Duration(seconds: 10));
      track.upsert(const Duration(seconds: 2), const CropBox(cx: 0.3, cy: 0.3, w: 0.2, h: 0.2));
      track.upsert(const Duration(seconds: 6), const CropBox(cx: 0.7, cy: 0.6, w: 0.3, h: 0.3));
    });

    test('多帧：表达式含 if(lt(t, 并单引号包裹', () {
      final (cw, ch) = track.fixedCropSize(1280, 720);
      expect(cw, 384); // 最大框 0.3*1280
      expect(ch, 216); // 最大框 0.3*720
      final (x, y) = track.topLeftExprs(cw, ch, 1280, 720);
      expect(x.contains("if(lt(t,"), isTrue);
      expect(y.contains("if(lt(t,"), isTrue);
    });

    test('单帧：topLeftAt 返回 clamp 后左上角常量', () {
      final single = KeyframeTrack(duration: const Duration(seconds: 10))
        ..reset(const CropBox(cx: 0.1, cy: 0.9, w: 0.5, h: 0.5));
      // cx=0.1 → 中心 128px，半宽 320px → 左上 = 128-320 <0 → clamp 0
      final (x, y) = single.topLeftAt(Duration.zero, 640, 360, 1280, 720);
      expect(x, 0);
      expect(y, 360); // 0.9*720=648-180=468 → clamp 上限 720-360=360
    });

    test('越界框 clamp＋偶数化（Review Focus #3）', () {
      final (cw, ch) = track.fixedCropSize(1280, 720);
      final (x, y) = track.topLeftAt(const Duration(seconds: 3), cw, ch, 1280, 720);
      expect(x.isEven, isTrue);
      expect(y.isEven, isTrue);
      expect(x, inInclusiveRange(0, 1280 - cw));
      expect(y, inInclusiveRange(0, 720 - ch));
    });

    test('与 cropExpr 的 x/y 同源：cropExpr 内层坐标与 topLeftExprs 一致', () {
      final expr = track.cropExpr(1280, 720);
      final (cw, ch) = track.fixedCropSize(1280, 720);
      final (x, y) = track.topLeftExprs(cw, ch, 1280, 720);
      expect(expr, contains("x='$x'"));
      expect(expr, contains("y='$y'"));
    });
  });

  group('CropBox.clamped minArea 参数', () {
    test('默认 minArea=0.10 行为不变（直拍回归保障）', () {
      final b = const CropBox(cx: 0.5, cy: 0.5, w: 0.1, h: 0.1).clamped();
      expect(b.w * b.h, closeTo(0.10, 0.001)); // 被放大到 10% 面积
    });

    test('打码小框用 minArea=0.0016（边 0.04）不被放大', () {
      final b = const CropBox(cx: 0.5, cy: 0.5, w: 0.05, h: 0.05).clamped(minArea: 0.0016);
      expect(b.w, 0.05);
      expect(b.h, 0.05);
    });

    test('scaledBy 透传 minArea', () {
      final b = const CropBox(cx: 0.5, cy: 0.5, w: 0.05, h: 0.05)
          .scaledBy(0.5, minArea: 0.0016);
      expect(b.w * b.h, lessThan(0.01));
    });
  });
}
