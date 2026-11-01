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

    test('initial offset = 右下（默认）', () {
      final initial = FabLogic.initialOffset(screen, ball);
      expect(initial.dx, 400 - 48);
      expect(initial.dy, 800 - 48 - 56); // 底部导航高 56（2026-10-09 #6 从 64 压小）
    });

    // —— T11 动量释放 ——
    test('projectMomentum：decelRate 0.998 闭式投影', () {
      // project(v) = (v/1000)·0.998/(1−0.998) ≈ v·0.499
      expect(FabLogic.projectMomentum(2000), closeTo(2000 * 0.499, 0.1));
      expect(FabLogic.projectMomentum(-1000), closeTo(-1000 * 0.499, 0.1));
      expect(FabLogic.projectMomentum(0), 0);
    });

    test('rubberband：出界越多阻力越大（dim 60 / c 0.55）', () {
      // 小出界近似线性（over·c）
      expect(FabLogic.rubberband(10), closeTo(10 * 60 * .55 / (60 + 5.5), 0.01));
      // 单调递增、渐近 dim = 60
      expect(FabLogic.rubberband(100), lessThan(FabLogic.rubberband(10000)));
      expect(FabLogic.rubberband(10000), closeTo(60, 1.0));
      expect(FabLogic.rubberband(0), 0);
    });

    test('clampRubberBand：边界内原样、出界弹性偏移', () {
      final inside =
          FabLogic.clampRubberBand(const Offset(100, 100), screen, ball);
      expect(inside, const Offset(100, 100));
      final out =
          FabLogic.clampRubberBand(const Offset(-20, -20), screen, ball);
      // 出界部分被阻尼（x∈(-33,0)，不是硬 clamp 的 0）
      expect(out.dx, lessThan(0));
      expect(out.dx, greaterThan(-33));
      expect(out.dy, lessThan(0));
      // 回到界内则恢复硬 clamp 语义
      final back = FabLogic.clampIntoScreen(out, screen, ball);
      expect(back, Offset.zero);
    });

    test('releaseTarget：动量决定贴边、y 投影 0.35 阻尼后入屏', () {
      // 右半区起点 + 向左动量把投影位置带到左半区（300−249.5=50.5 < 中线）→ 贴左
      final t = FabLogic.releaseTarget(const Offset(300, 400),
          const Offset(-500, 800), screen, ball);
      expect(t.dx, 0);
      final projectedY = 400 + FabLogic.projectMomentum(800) * .35;
      expect(t.dy, closeTo(projectedY.clamp(0.0, 800 - 48 - 56), 0.01));
      // 左半区小左拉动量（投影仍在左半区）→ 贴左
      final t2 = FabLogic.releaseTarget(const Offset(100, 100),
          const Offset(-200, 0), screen, ball);
      expect(t2.dx, 0);
      // 右半区向右动量 → 贴右
      final t4 = FabLogic.releaseTarget(const Offset(300, 100),
          const Offset(2000, 0), screen, ball);
      expect(t4.dx, 400 - 48);
      // y clamp 不出屏
      final t3 = FabLogic.releaseTarget(const Offset(300, 700),
          const Offset(0, 5000), screen, ball);
      expect(t3.dy, 800 - 48 - 56);
    });
  });
}
