import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/side_transform.dart';

void main() {
  // v1.5.9 方案一：画面框＝裁剪框，视频 cover 填满框（溢出即被裁掉）。
  // 容器归一化坐标：高=1、宽=containerAspect（=所选比例 w/h）。

  group('SideTransform（方案一 cover 基准：框=画面）', () {
    test('scale=1：竖屏源在 3:4 框 → 宽撑满、纵向溢出，取样=框比例下最大窗', () {
      final t = SideTransform(ratio: '3:4');
      const ca = 3 / 4.0;
      // 竖屏 1080×1920（sa=0.5625）cover 进 0.75 宽的框：宽撑满 w=0.75、
      // h=0.75/0.5625≈1.333（纵向溢出 0.333）
      final video = t.videoRectInContainer(const Size(1080, 1920), ca);
      expect(video.width, closeTo(0.75, 0.001));
      expect(video.height, closeTo(1.3333, 0.001));
      // 取样 = 框全域映射回源：全宽 1080、高 1440（1080×1440=3:4），居中
      final r = t.toSourceRect(const Size(1080, 1920), ca);
      expect(r.width, closeTo(1080, 0.5));
      expect(r.height, closeTo(1440, 0.5));
      expect(r.left, 0);
      expect(r.top, closeTo((1920 - 1440) / 2, 1.0));
    });

    test('scale=1：横屏源在 3:4 框 → 高撑满、横向溢出，取样=居中竖条', () {
      final t = SideTransform(ratio: '3:4');
      const ca = 3 / 4.0;
      final r = t.toSourceRect(const Size(1920, 1080), ca);
      // cover 高撑满：取样全高 1080、宽=1080×3/4=810，水平居中
      expect(r.width, 810);
      expect(r.height, 1080);
      expect(r.left, closeTo((1920 - 810) / 2, 1.0));
      expect(r.top, 0);
    });

    test('pan 与预览一致：视频右移 → 框内看到更靠左的源区域', () {
      final t = SideTransform(ratio: '3:4', scale: 1.5);
      const ca = 3 / 4.0;
      final center = t.toSourceRect(const Size(1080, 1920), ca);
      t.pan = const Offset(0.2, 0);
      final moved = t.toSourceRect(const Size(1080, 1920), ca);
      expect(center.left - moved.left, greaterThan(10));
    });

    test('pan clamp：视频不滑出画面框（cover 溢出方向有移动余地）', () {
      final t = SideTransform(ratio: '3:4', scale: 1.0);
      t.pan = const Offset(9, 9);
      final video = t.videoRectInContainer(const Size(1080, 1920), 3 / 4.0);
      // 横向 cover 恰好填满无移动余地；纵向 h=1.333 → 可移 ±(1.333-1)/2
      expect(video.center.dx, closeTo(3 / 8.0, 0.001));
      expect(video.center.dy, closeTo(0.5 + (4.0 / 3 - 1) / 2, 0.001));
    });

    test('比例字段（全局共享）：aspect 正确', () {
      expect(SideTransform(ratio: '1:1').aspect, 1.0);
      expect(SideTransform(ratio: '3:4').aspect, closeTo(0.75, 0.0001));
      expect(SideTransform(ratio: '9:16').aspect, closeTo(0.5625, 0.0001));
    });
  });
}
