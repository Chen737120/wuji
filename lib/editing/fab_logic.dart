import 'package:flutter/material.dart';

/// 悬浮球纯逻辑（规格 §3）：clamp 进屏、松手贴边、拖/点判定。
/// 与 widget 解耦，宿主 flutter test 全覆盖。
class FabLogic {
  FabLogic._();

  /// 底部导航高度（home_shell BottomAppBar height 64）——球不能压在导航上。
  static const double bottomBarHeight = 64;

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

  static double _clampAxis(double v, double min, double max) =>
      v.clamp(min, max);
}
