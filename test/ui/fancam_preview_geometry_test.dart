// 直拍预览几何单测（v1.5.26 走查 F10）：videoRect 400×800、scale=2、pan=0。
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/ui/fancam/preview_geometry.dart';

void main() {
  const video = Rect.fromLTWH(0, 0, 400, 800);

  test('scale=1、pan=0：映射恒等（手动模式 1× 零变化）', () {
    expect(previewToScreen(const Offset(100, 200), video, 1, Offset.zero),
        const Offset(100, 200));
    expect(previewToContent(const Offset(100, 200), video, 1, Offset.zero),
        const Offset(100, 200));
    expect(
      previewMappedRect(const Rect.fromLTWH(50, 100, 100, 200), video, 1,
          Offset.zero),
      const Rect.fromLTWH(50, 100, 100, 200),
    );
  });

  test('scale=2、pan=0：内容中心 → 屏幕中心；(.25,.5) → x=0', () {
    expect(previewToScreen(const Offset(200, 400), video, 2, Offset.zero),
        const Offset(200, 400));
    expect(previewToScreen(const Offset(100, 400), video, 2, Offset.zero),
        const Offset(0, 400));
  });

  test('点选逆变换：屏幕 (0,400) → 归一化 (.25,.5)，中心 → (.5,.5)', () {
    expect(previewNormalizedPoint(const Offset(0, 400), video, 2, Offset.zero),
        const Offset(0.25, 0.5));
    expect(previewNormalizedPoint(const Offset(200, 400), video, 2, Offset.zero),
        const Offset(0.5, 0.5));
  });

  test('越界点 clamp 到 0..1', () {
    expect(previewNormalizedPoint(const Offset(-999, 9999), video, 2, Offset.zero),
        const Offset(0, 1));
  });

  test('pan 叠加：内容中心映射到屏幕中心 + pan', () {
    const pan = Offset(30, -40);
    expect(previewToScreen(const Offset(200, 400), video, 2, pan),
        const Offset(230, 360));
    expect(previewToContent(const Offset(230, 360), video, 2, pan),
        const Offset(200, 400));
  });

  test('框矩形：中心随变换、宽高乘 scale', () {
    // 内容框 200×400 居中 → 2× 后 400×800 居中
    final r = previewMappedRect(
        const Rect.fromLTWH(100, 200, 200, 400), video, 2, Offset.zero);
    expect(r.center, const Offset(200, 400));
    expect(r.width, 400);
    expect(r.height, 800);
    // 非中心框：中心 = 屏幕中心 + (内容中心−视频中心)×2
    final r2 = previewMappedRect(
        Rect.fromCenter(
            center: const Offset(300, 400), width: 100, height: 100),
        video,
        2,
        Offset.zero);
    expect(r2.center, const Offset(400, 400)); // 右侧 1/4 处 → 屏幕右缘
    expect(r2.width, 200);
  });
}
