import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/crop_box.dart';
import 'dart:ui';
import 'package:wuji/editing/keyframes.dart';

void main() {
  group('KeyframeTrack（规格 §5.2：≤10、排序去重、分段线性插值）', () {
    test('upsert：乱序插入自动排序、同刻替换、clamp 到 [0,dur]', () {
      final track = KeyframeTrack(duration: const Duration(seconds: 10));
      track.upsert(const Duration(seconds: 5), CropBox.centered('9:16'));
      track.upsert(const Duration(seconds: 1), CropBox.centered('9:16'));
      track.upsert(const Duration(seconds: 3), CropBox.centered('9:16'));
      expect(track.frames.map((f) => f.t.inSeconds).toList(), [1, 3, 5]);

      // 同刻替换
      final box2 = CropBox(cx: 0.3, cy: 0.3, w: 0.3, h: 0.3);
      track.upsert(const Duration(seconds: 3), box2);
      expect(track.frames, hasLength(3));
      expect(track.frames[1].box.cx, 0.3);

      // 越界 clamp
      track.upsert(const Duration(seconds: 99), CropBox.centered('9:16'));
      expect(track.frames.last.t, const Duration(seconds: 10));
      track.upsert(const Duration(milliseconds: -5), CropBox.centered('9:16'));
      expect(track.frames.first.t, Duration.zero);
      expect(track.frames, hasLength(5));
    });

    test('关键帧上限 10 个：第 11 个被拒绝', () {
      final track = KeyframeTrack(duration: const Duration(seconds: 100));
      for (var i = 0; i < 10; i++) {
        track.upsert(Duration(seconds: i * 10 + 1), CropBox.centered('9:16'));
      }
      expect(track.frames, hasLength(10));
      final added = track.upsert(
          const Duration(seconds: 99), CropBox(cx: 0.4, cy: 0.4, w: 0.2, h: 0.2));
      expect(added, isFalse);
      expect(track.frames, hasLength(10));
    });

    test('boxAt：端点精确、两点中点＝均值', () {
      final track = KeyframeTrack(duration: const Duration(seconds: 10));
      track.upsert(Duration.zero,
          const CropBox(cx: 0.2, cy: 0.2, w: 0.4, h: 0.4));
      track.upsert(const Duration(seconds: 10),
          const CropBox(cx: 0.6, cy: 0.6, w: 0.8, h: 0.8));

      expect(track.boxAt(Duration.zero).cx, 0.2);
      expect(track.boxAt(const Duration(seconds: 10)).cx, 0.6);
      final mid = track.boxAt(const Duration(seconds: 5));
      expect(mid.cx, closeTo(0.4, 0.001));
      expect(mid.w, closeTo(0.6, 0.001));
    });

    test('boxAt：单帧（单框模式）全程恒定', () {
      final track = KeyframeTrack(duration: const Duration(seconds: 10));
      track.upsert(const Duration(seconds: 2),
          const CropBox(cx: 0.5, cy: 0.5, w: 0.5, h: 0.5));
      expect(track.boxAt(Duration.zero).cx, 0.5);
      expect(track.boxAt(const Duration(seconds: 9)).cx, 0.5);
    });

    test('boxAt：区间外取最近端点', () {
      final track = KeyframeTrack(duration: const Duration(seconds: 100));
      track.upsert(const Duration(seconds: 10),
          const CropBox(cx: 0.2, cy: 0.2, w: 0.4, h: 0.4));
      track.upsert(const Duration(seconds: 20),
          const CropBox(cx: 0.8, cy: 0.8, w: 0.4, h: 0.4));
      expect(track.boxAt(const Duration(seconds: 5)).cx, 0.2);
      expect(track.boxAt(const Duration(seconds: 50)).cx, 0.8);
    });

    test('cropExpr：单帧＝常量 crop；双帧＝分段线性表达式', () {
      final single = KeyframeTrack(duration: const Duration(seconds: 10));
      single.upsert(const Duration(seconds: 2),
          const CropBox(cx: 0.5, cy: 0.5, w: 0.5, h: 0.5));
      final singleExpr = single.cropExpr(1080, 1920, outH: 720);
      expect(singleExpr, startsWith('crop='));
      expect(singleExpr, isNot(contains('if(lt(t,')));
      // 像素值：w=540, h=960, x=270, y=480；不放大规则 outH=720 < 960 → 720/960=0.75
      // → 输出高 720？不——规格：框实际高<720 才不放大。框高 960 ≥720 → 缩到 720
      expect(singleExpr, contains('540'));

      final dual = KeyframeTrack(duration: const Duration(seconds: 10));
      dual.upsert(Duration.zero,
          const CropBox(cx: 0.2, cy: 0.2, w: 0.4, h: 0.4));
      dual.upsert(const Duration(seconds: 10),
          const CropBox(cx: 0.6, cy: 0.6, w: 0.8, h: 0.8));
      final dualExpr = dual.cropExpr(1080, 1920, outH: 720);
      expect(dualExpr, contains('if(lt(t,'));
      // 两个关键帧 → 一次 lerp 段（首段在 if 内、尾段在 else）
      expect(dualExpr.contains('if(lt(t,'), isTrue);
      expect(dualExpr.contains(')*('), isTrue); // lerp 结构
    });

    test('reset：还原回单框', () {
      final track = KeyframeTrack(duration: const Duration(seconds: 10));
      track.upsert(Duration.zero, const CropBox(cx: 0.5, cy: 0.5, w: 0.5, h: 0.5));
      track.upsert(const Duration(seconds: 5),
          const CropBox(cx: 0.3, cy: 0.3, w: 0.3, h: 0.3));
      track.reset(const CropBox(cx: 0.5, cy: 0.5, w: 0.6, h: 0.6));
      expect(track.frames, hasLength(1));
      expect(track.frames.single.box.w, 0.6);
    });
  });
}
