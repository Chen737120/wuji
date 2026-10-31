import 'package:flutter/material.dart';

/// 悬浮球纯逻辑（规格 §3）：clamp 进屏、松手贴边、拖/点判定。
/// 与 widget 解耦，宿主 flutter test 全覆盖。
class FabLogic {
  FabLogic._();

  /// 底部导航高度（home_shell 底栏高度 56，2026-10-09 需求 #6 从 64 压小，
  /// 降低底栏存在感）——球不能压在导航上。
  static const double bottomBarHeight = 56;

  /// 默认位置：右下角（规格：SharedPreferences 无值时的缺省）。
  static Offset initialOffset(Size screen, Size ball) {
    final bottomLimit = screen.height - ball.height - bottomBarHeight;
    return Offset(
        _clampAxis(screen.width - ball.width, 0, screen.width - ball.width),
        _clampAxis(bottomLimit, 0, bottomLimit));
  }

  /// 把恢复的 offset clamp 进当前屏幕（折叠屏展开/换机场景）。
  static Offset clampIntoScreen(Offset o, Size screen, Size ball) {
    final maxX = (screen.width - ball.width).clamp(0.0, double.infinity);
    final maxY =
        (screen.height - ball.height - bottomBarHeight).clamp(0.0, double.infinity);
    return Offset(_clampAxis(o.dx, 0, maxX), _clampAxis(o.dy, 0, maxY));
  }

  /// 松手吸附到较近的左/右边缘（y 不动）。
  static Offset snapEdge(Offset o, Size screen, Size ball) {
    final maxX = (screen.width - ball.width).clamp(0.0, double.infinity);
    final x = o.dx.clamp(0.0, maxX);
    final snapped = x < maxX / 2 ? 0.0 : maxX;
    return Offset(snapped, o.dy);
  }

  /// 位移阈值 <6dp 判定为点击（规格 §3）。
  static bool isTap(Offset delta) => delta.distance < 6;

  /// 动量投影（T11，原型 project(v, decelRate .998) 闭式）：
  /// 释放速度 px/s → 惯性滑行总位移 px。
  static double projectMomentum(double vPerSec, [double rate = .998]) =>
      (vPerSec / 1000) * rate / (1 - rate);

  /// rubber-band 阻尼（T11，原型 rubberband(o, dim 60, c .55)）：
  /// 出界量 → 弹性视觉偏移，越远阻力越大。
  static double rubberband(double over, [double dim = 60, double c = .55]) =>
      (over * dim * c) / (dim + c * over.abs());

  /// 拖拽中的软 clamp（T11）：边界内原样，出界部分按 rubber-band 弹性偏移
  /// （与 [clampIntoScreen] 的硬 clamp 相对）。
  static Offset clampRubberBand(Offset o, Size screen, Size ball) {
    final maxX = (screen.width - ball.width).clamp(0.0, double.infinity);
    final maxY =
        (screen.height - ball.height - bottomBarHeight).clamp(0.0, double.infinity);
    double band(double v, double min, double max) {
      if (v < min) return min - rubberband(min - v);
      if (v > max) return max + rubberband(v - max);
      return v;
    }

    return Offset(band(o.dx, 0, maxX), band(o.dy, 0, maxY));
  }

  /// 释放目标（T11，原型 fabRelease）：x＝当前位置＋动量投影后按投影位置
  /// 贴较近的左/右边缘；y＝投影×0.35 阻尼后 clamp 入屏（不贴边）。
  static Offset releaseTarget(
      Offset o, Offset velocityPerSec, Size screen, Size ball) {
    final maxX = (screen.width - ball.width).clamp(0.0, double.infinity);
    final maxY =
        (screen.height - ball.height - bottomBarHeight).clamp(0.0, double.infinity);
    final px = o.dx + projectMomentum(velocityPerSec.dx);
    final tx = px < maxX / 2 ? 0.0 : maxX;
    final ty = (o.dy + projectMomentum(velocityPerSec.dy) * .35)
        .clamp(0.0, maxY)
        .toDouble();
    return Offset(tx, ty);
  }

  static double _clampAxis(double v, double min, double max) =>
      v.clamp(min, max);
}
