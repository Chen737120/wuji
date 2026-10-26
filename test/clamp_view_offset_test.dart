// test/clamp_view_offset_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/ui/player_page.dart';

void main() {
  const vp = Size(400, 800);

  group('videoBaseSize', () {
    test('横屏视频竖看：宽顶满、高按比例', () {
      final s = videoBaseSize(vp, 16 / 9);
      expect(s.width, 400);
      expect(s.height, closeTo(225, 0.01));
    });
    test('竖屏视频竖看：宽顶满、高按比例', () {
      final s = videoBaseSize(vp, 9 / 16);
      expect(s.width, 400);
      expect(s.height, closeTo(711.11, 0.01));
    });
    test('横屏视频全屏（800×400）：高顶满、宽按比例', () {
      final s = videoBaseSize(const Size(800, 400), 16 / 9);
      expect(s.height, 400);
      expect(s.width, closeTo(711.11, 0.01));
    });
  });

  group('clampViewOffset', () {
    const landscape = Size(400, 225); // 横屏视频竖看（videoBaseSize 口径）
    const portrait = Size(400, 711); // 竖屏视频竖看

    test('scale=1 任意偏移归零', () {
      expect(clampViewOffset(const Offset(999, -999), 1.0, landscape, vp),
          Offset.zero);
    });
    test('横屏视频竖看 scale=2：横向钳 ±200，纵向未溢出钳 0', () {
      expect(clampViewOffset(const Offset(500, 0), 2.0, landscape, vp),
          const Offset(200, 0));
      expect(clampViewOffset(const Offset(0, -900), 2.0, landscape, vp),
          Offset.zero);
    });
    test('竖屏视频竖看 scale=2：钳在 ±(200, 311)', () {
      expect(clampViewOffset(const Offset(-50, -900), 2.0, portrait, vp),
          const Offset(-50, -311));
    });
    test('界内偏移原样保留', () {
      expect(clampViewOffset(const Offset(30, -70), 1.5, portrait, vp),
          const Offset(30, -70));
    });
  });
}
