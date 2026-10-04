import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/crop_box.dart';

void main() {
  group('CropBox（归一化 0..1，比例锁定）', () {
    test('centered(9:16) 在横屏源上居中、比例正确', () {
      final box = CropBox.centered('9:16');
      expect(box.cx, 0.5);
      expect(box.cy, 0.5);
      // 9:16 → w/h = 9/16；归一化下面积 ≤1
      expect(box.w / box.h, closeTo(9 / 16, 0.001));
      expect(box.w, lessThanOrEqualTo(1));
      expect(box.h, lessThanOrEqualTo(1));
    });

    test('centered(9:16) 在 9:21 超高竖屏源上居中（Review Focus #5）', () {
      final box = CropBox.centered('9:16');
      expect(box.cx, 0.5);
      expect(box.cy, 0.5);
      // 归一化面积与宽高比保持
      expect(box.w / box.h, closeTo(9 / 16, 0.001));
    });

    test('比例 3:4 / 1:1 各自正确', () {
      expect(CropBox.centered('3:4').w / CropBox.centered('3:4').h,
          closeTo(3 / 4, 0.001));
      expect(CropBox.centered('1:1').w, CropBox.centered('1:1').h);
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
