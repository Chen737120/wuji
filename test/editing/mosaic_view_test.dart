// 打码编辑器查看缩放几何（v1.5.26 走查 F2）：视频、快照、区域框共用
// 中心锚点变换（与播放页 Transform.scale 一致），偏移按画面尺寸钳位。
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/crop_box.dart';
import 'package:wuji/editing/mosaic_view.dart';

void main() {
  const canvas = Size(400, 800);
  const centerBox = CropBox(cx: 0.5, cy: 0.5, w: 0.2, h: 0.2);

  group('mosaicBoxRect', () {
    test('scale=1、offset=0：与修复前左上锚点公式逐值一致', () {
      const b = CropBox(cx: 0.3, cy: 0.7, w: 0.25, h: 0.1);
      final r = mosaicBoxRect(b, canvas, 1, Offset.zero);
      expect(r.left, closeTo((b.cx - b.w / 2) * canvas.width, 1e-9));
      expect(r.top, closeTo((b.cy - b.h / 2) * canvas.height, 1e-9));
      expect(r.width, closeTo(b.w * canvas.width, 1e-9));
      expect(r.height, closeTo(b.h * canvas.height, 1e-9));
    });

    test('scale=2、offset=0：中心框中心仍在画布中心，宽高翻倍', () {
      final r = mosaicBoxRect(centerBox, canvas, 2, Offset.zero);
      expect(r.center.dx, closeTo(canvas.width / 2, 1e-9));
      expect(r.center.dy, closeTo(canvas.height / 2, 1e-9));
      expect(r.width, closeTo(0.2 * canvas.width * 2, 1e-9));
      expect(r.height, closeTo(0.2 * canvas.height * 2, 1e-9));
    });

    test('scale=2：非中心框中心 = canvas.center + (p−0.5)×canvas×2', () {
      const b = CropBox(cx: 0.25, cy: 0.5, w: 0.1, h: 0.1);
      final r = mosaicBoxRect(b, canvas, 2, Offset.zero);
      expect(r.center.dx, closeTo(canvas.width / 2 + (0.25 - 0.5) * canvas.width * 2, 1e-9));
      expect(r.center.dy, closeTo(canvas.height / 2, 1e-9));
    });

    test('offset 平移叠加在缩放后的中心上', () {
      final r = mosaicBoxRect(centerBox, canvas, 2, const Offset(30, -40));
      expect(r.center, const Offset(200, 400) + const Offset(30, -40));
    });
  });

  group('clampMosaicViewOffset', () {
    test('scale=1：任意偏移归零（画面未溢出，拖不走）', () {
      expect(clampMosaicViewOffset(const Offset(120, -80), 1, canvas),
          Offset.zero);
    });

    test('scale=2：逐轴钳在 ±(scale−1)×canvas/2', () {
      const within = Offset(150, -300);
      expect(clampMosaicViewOffset(within, 2, canvas), within);
      final out = clampMosaicViewOffset(const Offset(999, -999), 2, canvas);
      expect(out, const Offset(200, -400));
      final outNeg = clampMosaicViewOffset(const Offset(-999, 999), 2, canvas);
      expect(outNeg, const Offset(-200, 400));
    });
  });
}
