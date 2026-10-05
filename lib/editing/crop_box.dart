import 'dart:math' as math;
import 'dart:ui';

/// 直拍框（规格 §5.1）：归一化 0..1 坐标（相对源画面），比例锁定。
class CropBox {
  const CropBox({
    required this.cx,
    required this.cy,
    required this.w,
    required this.h,
  });

  /// 中心点（归一化）。
  final double cx;
  final double cy;

  /// 宽/高（归一化，比例锁定 w/h = ratio）。
  final double w;
  final double h;

  double get left => cx - w / 2;
  double get right => cx + w / 2;
  double get top => cy - h / 2;
  double get bottom => cy + h / 2;

  /// 给定比例下"中央默认框"：取画面可容纳的最大 9:16/3:4/1:1 窗的 80%。
  static CropBox centered(String ratio, {double fill = 0.8}) {
    final aspect = _aspect(ratio);
    // 归一化空间里取 w×h = fill²、w/h = aspect 的最大内接框
    var w = fill;
    var h = fill / aspect;
    if (h > 1) {
      h = fill;
      w = fill * aspect;
    }
    // 归一化坐标里宽高单位不同：真实比例在像素域换算由调用方（固定以
    // 归一化 w/h 比例描述）处理——此处以"归一化正方形×fill"的启发式：
    // 为保证任意源下框都是比例锁定的可视框，直接取 h=fill*aspect clamp。
    h = (w / aspect).clamp(0.0, 1.0);
    if (h < fill * 0.5) {
      // 极端比例回退
      h = fill * 0.5;
    }
    return CropBox(cx: 0.5, cy: 0.5, w: w, h: h);
  }

  static double _aspect(String ratio) {
    switch (ratio) {
      case '1:1':
        return 1;
      case '9:16':
        return 9 / 16;
      default:
        return 3 / 4;
    }
  }

  /// clamp：框出界拉回画面内；面积 < 10% 时等比放大到最小面积。
  CropBox clamped() {
    var nw = w;
    var nh = h;
    // 面积下限（规格 §5.1：最小面积 = 画面 10%）
    const minArea = 0.10;
    if (nw * nh < minArea) {
      final factor = math.sqrt(minArea / (nw * nh));
      nw = (nw * factor).clamp(0.01, 1.0);
      nh = (nh * factor).clamp(0.01, 1.0);
    }
    // 边界：不超画面
    if (nw > 1) {
      nh *= 1 / nw;
      nw = 1;
    }
    if (nh > 1) {
      nw *= 1 / nh;
      nh = 1;
    }
    // 中心平移使框完全在画面内
    var ncx = cx.clamp(nw / 2, 1 - nw / 2);
    var ncy = cy.clamp(nh / 2, 1 - nh / 2);
    if (nw == 1) ncx = 0.5;
    if (nh == 1) ncy = 0.5;
    return CropBox(cx: ncx, cy: ncy, w: nw, h: nh);
  }

  /// 以 delta 移动中心后 clamp。
  CropBox movedBy(Offset delta) =>
      CropBox(cx: cx + delta.dx, cy: cy + delta.dy, w: w, h: h).clamped();

  /// 以 factor 缩放（>1 放大框）后 clamp；比例锁定按 w 等比。
  CropBox scaledBy(double factor) {
    final factorClamped = factor.clamp(0.5, 2.0);
    return CropBox(cx: cx, cy: cy, w: w * factorClamped, h: h * factorClamped)
        .clamped();
  }

  /// 像素域矩形（源尺寸），供 FFmpeg crop。
  /// w/h 必须 clamp 进源——FFmpeg crop 对 w/h 超界直接报错
  /// （x/y 超界才会自动夹取）。
  Rect toPixelRect(int srcW, int srcH) {
    final pw = (w * srcW).roundToDouble().clamp(16.0, srcW.toDouble());
    final ph = (h * srcH).roundToDouble().clamp(16.0, srcH.toDouble());
    final px = ((cx * srcW) - pw / 2).clamp(0.0, srcW - pw);
    final py = ((cy * srcH) - ph / 2).clamp(0.0, srcH - ph);
    return Rect.fromLTWH(px, py, pw, ph);
  }
}

