import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/side_transform.dart';

void main() {
  group('SideTransform.toSourceRect（导出与预览遮罩的唯一真源）', () {
    test('默认（scale=1）居中取样、比例 3:4 填满高度', () {
      // 源 1920x1080（横屏），目标高 720、比例 3:4 → 取样高=源高、取样宽=高*3/4
      final t = SideTransform(ratio: '3:4');
      final r = t.toSourceRect(const Size(1920, 1080), 720);
      // 取样高按比例在源内最大化：h=1080、w=1080*3/4=810，居中
      expect(r.height, 1080);
      expect(r.width, 810);
      expect(r.left, (1920 - 810) / 2);
      expect(r.top, 0);
    });

    test('缩放 2× 后取样面积减半', () {
      final t = SideTransform(ratio: '1:1', scale: 2.0);
      final r = t.toSourceRect(const Size(1080, 1080), 720);
      // 1:1、scale2 → 取样边 = 1080/2 = 540，居中
      expect(r.width, 540);
      expect(r.height, 540);
      expect(r.left, 270);
      expect(r.top, 270);
    });

    test('pan 把取样窗口平移并 clamp 在源内', () {
      final t = SideTransform(ratio: '1:1', scale: 2.0, pan: const Offset(1, 0));
      final r = t.toSourceRect(const Size(1080, 1080), 720);
      // pan.x=1 → 窗口推到右缘
      expect(r.left, 540);
      expect(r.top, 270);
    });

    test('竖屏源 9:16 比例取样全屏（Review Focus #5 相关）', () {
      final t = SideTransform(ratio: '9:16');
      final r = t.toSourceRect(const Size(1080, 1920), 720);
      expect(r.width, 1080);
      expect(r.height, 1920);
    });

    test('比例切换改变取样宽高比', () {
      final tall = SideTransform(ratio: '9:16').toSourceRect(const Size(1080, 1920), 720);
      final sq = SideTransform(ratio: '1:1').toSourceRect(const Size(1080, 1920), 720);
      // 9:16 源上：1:1 裁剪宽=全宽、高更小（几何正确）
      expect(sq.width, tall.width);
      expect(sq.height, lessThan(tall.height));
    });
  });
}
