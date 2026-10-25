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

  /// 给定比例下"中央默认框"：取画面可容纳的最大比例窗的 80%。
  ///
  /// 比例锁定指**像素域** w·srcW / h·srcH = ratio——归一化宽高的物理基准
  /// 不同（w×源宽、h×源高），归一化 w/h 必须含 srcH/srcW 修正，否则
  /// 9:16 源上选 1:1 实际出 9:16 框、选 9:16 出约 1:3.2 窄条
  /// （2026-10-12 用户报告"实际比例错误"的根因）。
  static CropBox centered(String ratio,
      {required int srcW, required int srcH, double fill = 0.8}) {
    final aspect = _aspect(ratio);
    // 尺寸未知（调用方初始化时序上 video_player size 尚未就绪）时退回
    // 满幅 fill 框：0/0=NaN 一旦流进 KeyframeTrack，导出参数单
    // _evenClamp(NaN).floor() 会抛 Infinity or NaN toInt（冒烟实证）
    if (srcW <= 0 || srcH <= 0) {
      return CropBox(cx: 0.5, cy: 0.5, w: fill, h: fill);
    }
    var w = aspect * srcH / srcW; // h=1 时的归一化宽
    var h = 1.0;
    if (w > 1) {
      h = 1 / w;
      w = 1;
    }
    return CropBox(cx: 0.5, cy: 0.5, w: w * fill, h: h * fill);
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

  /// clamp：框出界拉回画面内；面积 < [minArea] 时等比放大到最小面积。
  /// 直拍规格最小面积 = 画面 10%；打码区域允许更小（spec §7，Task 3 传 0.0016）。
  CropBox clamped({double minArea = 0.10}) {
    var nw = w;
    var nh = h;
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
  /// [minArea] 透传 [clamped]：打码小框拖动时不得被最小面积放大（spec §7），
  /// 直拍默认 0.10 行为不变。
  CropBox movedBy(Offset delta, {double minArea = 0.10}) =>
      CropBox(cx: cx + delta.dx, cy: cy + delta.dy, w: w, h: h)
          .clamped(minArea: minArea);

  /// 以 factor 缩放（>1 放大框）后 clamp；比例锁定按 w 等比。
  /// 直拍默认 minFactor 0.5 / maxFactor 2.0 / minArea 0.10 行为不变；
  /// 打码编辑器（Task 3）传 minFactor 0.1 / maxFactor 4.0、minArea 0.0016
  /// 以支持小框深缩放（spec §7）。
  CropBox scaledBy(
    double factor, {
    double minArea = 0.10,
    double minFactor = 0.5,
    double maxFactor = 2.0,
  }) {
    final factorClamped = factor.clamp(minFactor, maxFactor);
    return CropBox(cx: cx, cy: cy, w: w * factorClamped, h: h * factorClamped)
        .clamped(minArea: minArea);
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

