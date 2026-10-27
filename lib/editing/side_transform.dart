import 'dart:ui';
import 'package:flutter/material.dart';

/// 单侧画面变换（规格 §4.1 ②画面微调；v1.5.9 方案一：**画面框＝裁剪框**，
/// 2026-10-05 用户确认：比例改变的是整个画面框的比例，视频 cover 填满
/// 画面框（溢出即被裁掉，所见即所得），手势平移/缩放的是框下的视频，
/// 时间微调/画面微调两个 tab 的预览共用此呈现。
///
/// 容器（画面框）归一化坐标系：容器高 = 1、宽 = containerAspect（即
/// 所选比例的 w/h 值，两侧画面框同比例同大小）。
class SideTransform {
  SideTransform({this.scale = 1.0, this.pan = Offset.zero, this.ratio = '3:4'});

  /// 视频显示倍数：1.0 = cover 恰好填满画面框；>1 放大（可拖动查看）。
  double scale;

  /// 视频中心相对容器中心的偏移（容器归一化单位）；
  /// 计算时 clamp 到"视频不滑离画面框"的范围。
  Offset pan;

  /// 画面框比例（v1.5.9 起全局共享，两侧一致）。
  String ratio;

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

  /// 视频在画面框中的显示矩形（归一化坐标）。
  /// cover 基准（scale=1 恰好填满框）× scale，中心 = 容器中心 + pan
  /// （clamp 到视频不滑离框的可移动范围）。
  Rect videoRectInContainer(Size src, double containerAspect) {
    final sa = src.width / src.height;
    double w, h; // cover：把视频撑到恰好盖住 containerAspect×1 的框
    if (sa > containerAspect) {
      h = 1.0;
      w = 1.0 * sa;
    } else {
      w = containerAspect;
      h = containerAspect / sa;
    }
    w *= scale;
    h *= scale;
    final rangeX = ((w - containerAspect) / 2).clamp(0.0, double.infinity);
    final rangeY = ((h - 1.0) / 2).clamp(0.0, double.infinity);
    final cx = containerAspect / 2 + pan.dx.clamp(-rangeX, rangeX);
    final cy = 0.5 + pan.dy.clamp(-rangeY, rangeY);
    return Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
  }

  /// 反解为源画面取样矩形（导出 crop 与预览严格一致）。
  /// 取样区 = 画面框（容器全域）映射回源；框外（溢出）不可见即被裁掉。
  /// [src] 源视频尺寸（显示方向）；[containerAspect] 画面框宽高比。
  Rect toSourceRect(Size src, double containerAspect) {
    final video = videoRectInContainer(src, containerAspect);
    final unitPerSrcPxX = video.width / src.width;
    final unitPerSrcPxY = video.height / src.height;
    // 框 = 容器全域 (0,0,containerAspect,1)
    var w = containerAspect / unitPerSrcPxX;
    var h = 1.0 / unitPerSrcPxY;
    // scale=1（cover 基准）时 w/h 恰为框比例下源内最大窗；clamp 进源兜底
    w = w.clamp(1.0, src.width);
    h = h.clamp(1.0, src.height);
    var left = (0.0 - video.left) / unitPerSrcPxX;
    var top = (0.0 - video.top) / unitPerSrcPxY;
    left = left.clamp(0.0, src.width - w);
    top = top.clamp(0.0, src.height - h);
    return Rect.fromLTWH(left, top, w, h);
  }
}
