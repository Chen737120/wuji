import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/fab_logic.dart';

void main() {
  group('FabLogic（规格 §3：悬浮球纯逻辑）', () {
    const screen = Size(400, 800);
    const ball = Size(48, 48);

    test('clamp restored offset into current screen（Review Focus #4）', () {
      final big = FabLogic.clampIntoScreen(
          const Offset(9999, 9999), screen, ball);
      expect(big.dx, lessThanOrEqualTo(400 - 48));
      expect(big.dy, lessThanOrEqualTo(800 - 48 - 56)); // 减去底部导航高
      expect(big.dx, greaterThanOrEqualTo(0));
      expect(big.dy, greaterThanOrEqualTo(0));
    });

    test('clamp keeps negative restored values inside', () {
      final neg = FabLogic.clampIntoScreen(
          const Offset(-50, -50), screen, ball);
      expect(neg, Offset.zero);
    });

    test('snapEdge picks nearer horizontal edge', () {
      final right = FabLogic.snapEdge(
          const Offset(300, 500), screen, ball);
      expect(right.dx, 400 - 48);
      final left =
          FabLogic.snapEdge(const Offset(80, 500), screen, ball);
      expect(left.dx, 0);
    });

    test('isTap threshold 6dp', () {
      expect(FabLogic.isTap(const Offset(5, 3)), isTrue);
      expect(FabLogic.isTap(const Offset(7, 0)), isFalse);
      expect(FabLogic.isTap(Offset.zero), isTrue);
    });

    test('initial offset = 右下（默认）', () {
      final initial = FabLogic.initialOffset(screen, ball);
      expect(initial.dx, 400 - 48);
      expect(initial.dy, 800 - 48 - 56); // 底部导航高 56（2026-10-09 #6 从 64 压小）
    });
  });
}
