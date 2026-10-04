import 'dart:ui';
import 'package:flutter/material.dart';

/// 单侧画面变换（规格 §4.1 ②画面微调）：
/// 用户在显示层做平移/缩放；[toSourceRect] 把显示变换反解为
/// 源画面上的取样矩形（clamp 在源内）——导出 crop 与预览遮罩共用此唯一真源。
class SideTransform {
  SideTransform({
    this.scale = 1.0,
    this.pan = Offset.zero,
    this.ratio = '3:4',
  });

  /// 缩放倍数（1.0 = 按比例最大化填满取样窗；范围 0.5~3.0）。
  double scale;

  /// 平移（归一化：-1..1，相对取样窗可移动范围的百分比，+x 向右）。
  Offset pan;

  /// 目标比例 '1:1' | '3:4' | '9:16'（宽:高）。
  String ratio;

  SideTransform copy() =>
      SideTransform(scale: scale, pan: pan, ratio: ratio);

  /// 比例的宽高比（w/h）。
  double get aspect {
    switch (ratio) {
      case '1:1':
        return 1;
      case '9:16':
        return 9 / 16;
      default:
        return 3 / 4;
    }
  }

  /// 反解为源画面取样矩形。
  ///
  /// [src] 源视频尺寸；[dstHeight] 导出目标高（对比固定 720）。
  /// 算法：按比例在源内取"最大可能取样窗"（scale=1 时窗的一条边贴满源），
  /// 再除以 scale 得实际取样大小，最后按 pan 平移并 clamp 在源内。
  Rect toSourceRect(Size src, double dstHeight) {
    final targetAspect = aspect;
    // scale=1 时的基准取样窗：以高度或宽度为约束在源内最大化
    var baseW = src.height * targetAspect;
    var baseH = src.height.toDouble();
    if (baseW > src.width) {
      baseW = src.width;
      baseH = src.width / targetAspect;
    }

    final w = (baseW / scale).clamp(0.0, src.width);
    final h = (baseH / scale).clamp(0.0, src.height);

    // 可移动范围（取样窗中心的活动边界）
    final rangeX = (src.width - w) / 2;
    final rangeY = (src.height - h) / 2;
    final cx = src.width / 2 + pan.dx * rangeX;
    final cy = src.height / 2 + pan.dy * rangeY;

    var left = cx - w / 2;
    var top = cy - h / 2;
    left = left.clamp(0.0, src.width - w);
    top = top.clamp(0.0, src.height - h);
    return Rect.fromLTWH(left, top, w, h);
  }
}
