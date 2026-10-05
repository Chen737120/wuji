import 'dart:ui';
import 'package:flutter/material.dart';

/// 单侧画面变换（规格 §4.1 ②画面微调；v1.5.8 遮罩裁剪语义，2026-10-05
/// 用户反馈重做：比例改变的是**裁剪框大小**，视频以正常大小完整打底、
/// 不变形，手势移动/放大的是框下面的视频，框内即导出画面、框外遮住）。
///
/// 容器归一化坐标系：容器高 = 1 单位、宽 = containerAspect 单位（两侧容器
/// 同高同宽比，预览与导出共用此唯一真源）。
class SideTransform {
  SideTransform({this.scale = 1.0, this.pan = Offset.zero, this.ratio = '3:4'});

  /// 视频显示倍数：1.0 = 完整画面 contain 打底（不变形）；可放大到 4。
  double scale;

  /// 视频中心相对容器中心的偏移（容器归一化单位）。
  /// 计算时 clamp 到"视频不滑离框"的可移动范围。
  Offset pan;

  /// 裁剪框比例 '1:1' | '3:4' | '9:16'（改变的是框，不是视频）。
  String ratio;

  SideTransform copy() => SideTransform(scale: scale, pan: pan, ratio: ratio);

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

  /// 裁剪框在容器中的矩形（归一化坐标）。
  /// 框 = 容器内留边距的最大内接 ratio 窗；改变比例 → 框变大变小。
  Rect frameInContainer(double containerAspect) {
    const containerH = 210.0; // 与 compare_page 预览容器高一致
    final pad = 5.0 / containerH;
    final availW = containerAspect - 2 * pad;
    final availH = 1 - 2 * pad;
    final ra = aspect;
    double fw = availH * ra, fh = availH;
    if (fw > availW) {
      fw = availW;
      fh = availW / ra;
    }
    return Rect.fromCenter(
        center: Offset(containerAspect / 2, 0.5), width: fw, height: fh);
  }

  /// 视频画面在容器中的显示矩形（归一化坐标）。
  /// contain（不变形）× scale，中心 = 容器中心 + pan（clamp 到可移动范围）。
  Rect videoRectInContainer(Size src, double containerAspect) {
    final sa = src.width / src.height;
    double w, h;
    if (sa > containerAspect) {
      w = containerAspect;
      h = containerAspect / sa;
    } else {
      h = 1.0;
      w = sa;
    }
    w *= scale;
    h *= scale;
    final frame = frameInContainer(containerAspect);
    final rangeX = ((w - frame.width) / 2).clamp(0.0, double.infinity);
    final rangeY = ((h - frame.height) / 2).clamp(0.0, double.infinity);
    final cx = containerAspect / 2 + pan.dx.clamp(-rangeX, rangeX);
    final cy = 0.5 + pan.dy.clamp(-rangeY, rangeY);
    return Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
  }

  /// 反解为源画面取样矩形（导出 crop 与预览遮罩严格一致）。
  /// [src] 源视频尺寸（显示方向）；[containerAspect] 预览容器宽高比。
  Rect toSourceRect(Size src, double containerAspect) {
    final frame = frameInContainer(containerAspect);
    final video = videoRectInContainer(src, containerAspect);
    final unitPerSrcPxX = video.width / src.width;
    final unitPerSrcPxY = video.height / src.height;
    var w = frame.width / unitPerSrcPxX;
    var h = frame.height / unitPerSrcPxY;
    // 框可能大于画面（scale=1 且框比 contain 画面大）：clamp 进源
    w = w.clamp(1.0, src.width);
    h = h.clamp(1.0, src.height);
    var left = (frame.left - video.left) / unitPerSrcPxX;
    var top = (frame.top - video.top) / unitPerSrcPxY;
    left = left.clamp(0.0, src.width - w);
    top = top.clamp(0.0, src.height - h);
    return Rect.fromLTWH(left, top, w, h);
  }
}
