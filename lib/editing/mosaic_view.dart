import 'dart:math' as math;
import 'dart:ui';

import 'crop_box.dart';

/// 打码编辑器查看缩放几何（v1.5.26 走查 F2）。
///
/// 编辑器的 VideoPlayer、快照 Image 与区域框必须共用同一变换：缩放/平移
/// 都绕画布中心（与 `player_page.dart` 的 `Transform.scale` 一致），区域框
/// 用本函数换算到同一屏域。修复前框按左上锚点缩放、画面不动，框与画面
/// 脱节，用户可能在错误位置打码。

/// 归一化框 → 当前查看变换下的画布像素矩形（中心锚点）。
Rect mosaicBoxRect(CropBox b, Size canvas, double scale, Offset offset) {
  final center = Offset(
    canvas.width / 2 + (b.cx - 0.5) * canvas.width * scale + offset.dx,
    canvas.height / 2 + (b.cy - 0.5) * canvas.height * scale + offset.dy,
  );
  return Rect.fromCenter(
    center: center,
    width: b.w * canvas.width * scale,
    height: b.h * canvas.height * scale,
  );
}

/// 查看平移钳位（中心锚点）：单侧可拖余量 = (scale−1)×canvas/2；
/// scale=1 时各轴归零，画面拖不动。与播放页 `clampViewOffset` 同口径，
/// 此处画面内容恰为画布（AspectRatio 包裹），无需再传 content 尺寸。
Offset clampMosaicViewOffset(Offset offset, double scale, Size canvas) {
  final lx = math.max(0.0, (scale * canvas.width - canvas.width) / 2);
  final ly = math.max(0.0, (scale * canvas.height - canvas.height) / 2);
  return Offset(offset.dx.clamp(-lx, lx), offset.dy.clamp(-ly, ly));
}
