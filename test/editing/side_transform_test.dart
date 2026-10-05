import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/side_transform.dart';

void main() {
  // 容器归一化坐标：高=1、宽=containerAspect。测试用 1×1 方形容器最直观。
  const ca = 1.0;

  group('SideTransform（v1.5.8 遮罩裁剪语义：框=比例窗、视频 contain 打底）', () {
    test('frameInContainer：3:4 框留边距居中，比例改变框大小', () {
      final f34 = SideTransform(ratio: '3:4').frameInContainer(ca);
      // availH = 1-2*5/210 ≈ 0.9524；3:4 框 fw=availH*0.75≈0.7143 < availW
      expect(f34.height, closeTo(0.9524, 0.001));
      expect(f34.width, closeTo(0.7143, 0.001));
      expect(f34.center.dx, closeTo(0.5, 0.001));
      // 方容器内 1:1/3:4/9:16 框都撑满可用高，宽度递减（框随比例变宽变窄）
      final f11 = SideTransform(ratio: '1:1').frameInContainer(ca);
      final f916 = SideTransform(ratio: '9:16').frameInContainer(ca);
      expect(f11.height, closeTo(0.9524, 0.001));
      expect(f11.width, closeTo(0.9524, 0.001));
      expect(f916.width, closeTo(0.5357, 0.001));
      expect(f11.width, greaterThan(f34.width));
      expect(f34.width, greaterThan(f916.width));
    });

    test('videoRectInContainer：scale=1 完整画面 contain 居中', () {
      // 横屏源在 1×1 容器：宽撑满=1、高=1080/1920=0.5625
      final r = SideTransform(ratio: '3:4')
          .videoRectInContainer(const Size(1920, 1080), ca);
      expect(r.width, closeTo(1.0, 0.001));
      expect(r.height, closeTo(0.5625, 0.001));
      expect(r.center, closeToOffset(const Offset(0.5, 0.5)));
      // 竖屏源：高撑满=1、宽=1080/1920=0.5625
      final p = SideTransform(ratio: '3:4')
          .videoRectInContainer(const Size(1080, 1920), ca);
      expect(p.width, closeTo(0.5625, 0.001));
      expect(p.height, closeTo(1.0, 0.001));
    });

    test('videoRectInContainer：pan clamp 到视频不滑离框的范围', () {
      final t = SideTransform(ratio: '3:4', scale: 1.0);
      t.pan = const Offset(5, 5); // 远超可移动范围
      final r = t.videoRectInContainer(const Size(1080, 1920), ca);
      // 竖屏源 scale=1：视频宽 0.5625 < 框宽 0.7143 → 横向无移动空间
      expect(r.center.dx, closeTo(0.5, 0.001));
      // 纵向视频高 1 > 框高 0.9524 → 可移动 ±0.0238
      expect(r.center.dy, closeTo(0.5 + 0.0238, 0.001));
    });

    test('toSourceRect：scale=1、竖屏源、3:4 框 → 全高、居中宽', () {
      final r =
          SideTransform(ratio: '3:4').toSourceRect(const Size(1080, 1920), ca);
      // 视频 contain 高=1 → 框高 0.9524 → 源高 0.9524×1920=1828.6
      expect(r.height, closeTo(1828.6, 1.0));
      expect(r.top, closeTo((1920 - 1828.6) / 2, 1.0));
      // 框宽 0.7143 > 视频宽 0.5625 → clamp 到源全宽
      expect(r.width, 1080);
      expect(r.left, 0);
    });

    test('toSourceRect：scale=2 居中 → 取样面积减半、中心对齐', () {
      final t = SideTransform(ratio: '1:1', scale: 2.0);
      final r = t.toSourceRect(const Size(1080, 1080), ca);
      // 框 0.9524 → 源 0.9524×1080/2 = 514.3
      expect(r.width, closeTo(514.3, 1.0));
      expect(r.height, closeTo(514.3, 1.0));
      expect(r.left, closeTo((1080 - 514.3) / 2, 1.0));
      expect(r.top, closeTo((1080 - 514.3) / 2, 1.0));
    });

    test('toSourceRect：pan 与预览一致（视频右移→框内看到更靠左的源区域）', () {
      final t = SideTransform(ratio: '1:1', scale: 2.0);
      final center = t.toSourceRect(const Size(1080, 1080), ca);
      // 视频中心右移 0.2 单位（clamp 范围 ±0.5238 内）
      t.pan = const Offset(0.2, 0);
      final moved = t.toSourceRect(const Size(1080, 1080), ca);
      // 取样窗相对源左移：0.2 容器单位 = 0.2×(1080/2)=108 源像素
      expect(center.left - moved.left, closeTo(108, 1.0));
    });
  });
}

Matcher closeToOffset(Offset o) => _IsCloseToOffset(o);

class _IsCloseToOffset extends Matcher {
  _IsCloseToOffset(this.target);
  final Offset target;
  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) =>
      item is Offset &&
      (item.dx - target.dx).abs() < 0.001 &&
      (item.dy - target.dy).abs() < 0.001;
  @override
  Description describe(Description d) => d.add('close to $target');
}
