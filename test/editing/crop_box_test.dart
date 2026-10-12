import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/crop_box.dart';

void main() {
  group('CropBox（归一化 0..1，比例锁定=像素域语义）', () {
    test('centered(9:16) 在横屏源上居中、像素比例正确', () {
      final box = CropBox.centered('9:16', srcW: 1920, srcH: 1080);
      expect(box.cx, 0.5);
      expect(box.cy, 0.5);
      // 归一化宽高物理基准不同（w×源宽、h×源高），像素域 w·srcW / h·srcH
      // 才是真比例——旧实现归一化 w/h=比例值，9:16 源上全偏窄（1.5.23 修）
      expect(box.w * 1920 / (box.h * 1080), closeTo(9 / 16, 0.001));
      expect(box.w, lessThanOrEqualTo(1));
      expect(box.h, lessThanOrEqualTo(1));
    });

    test('centered(9:16) 在 9:21 超高竖屏源上居中（Review Focus #5）', () {
      final box = CropBox.centered('9:16', srcW: 1080, srcH: 2520);
      expect(box.cx, 0.5);
      expect(box.cy, 0.5);
      expect(box.w * 1080 / (box.h * 2520), closeTo(9 / 16, 0.001));
    });

    test('9:16 竖屏源上三种比例像素域各自正确', () {
      final wants = {'9:16': 9 / 16, '3:4': 3 / 4, '1:1': 1.0};
      for (final e in wants.entries) {
        final b = CropBox.centered(e.key, srcW: 1080, srcH: 1920);
        expect(b.w * 1080 / (b.h * 1920), closeTo(e.value, 0.001),
            reason: e.key);
      }
    });

    test('clamped 把出界框拉回画面内', () {
      final box = CropBox(cx: 0.9, cy: 0.9, w: 0.5, h: 0.5 / (9 / 16) > 1 ? 1.0 : 0.88);
      // w=0.5 → h=0.889；cx+0.25=1.15 出界 → clamp 后右缘=1
      final c = box.clamped();
      expect(c.right, lessThanOrEqualTo(1.0001));
      expect(c.bottom, lessThanOrEqualTo(1.0001));
      expect(c.left, greaterThanOrEqualTo(-0.0001));
      expect(c.top, greaterThanOrEqualTo(-0.0001));
    });

    test('最小面积 = 画面 10%：过小框被放大回 10%', () {
      final tiny = CropBox(cx: 0.5, cy: 0.5, w: 0.1, h: 0.1 * 16 / 9 > 1 ? 1 : 0.1 * 16 / 9);
      // w=0.1, h=0.1778 → 面积 0.0178 < 0.1 → clamp 后面积 ≥ 0.1
      final c = tiny.clamped();
      expect(c.w * c.h, greaterThanOrEqualTo(0.0999));
    });
  });
}
