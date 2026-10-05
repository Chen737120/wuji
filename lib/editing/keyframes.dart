import 'crop_box.dart';

/// 单个关键帧：时间点＋当时的框。
class Keyframe {
  const Keyframe({required this.t, required this.box});
  final Duration t;
  final CropBox box;
}

/// 关键帧轨道（规格 §5.2）：
/// - ≤10 个；插入自动排序去重（同刻替换）；t clamp 到 [0, duration]；
/// - [boxAt] 分段线性插值（cx/cy/w/h 各自 lerp）；
/// - [cropExpr] 生成 FFmpeg crop 逐帧表达式（单帧退化为常量）。
class KeyframeTrack {
  KeyframeTrack({required this.duration});

  final Duration duration;
  final List<Keyframe> _frames = [];
  List<Keyframe> get frames => List.unmodifiable(_frames);

  static const maxFrames = 10;

  /// 插入/替换。返回是否成功（超限返回 false）。
  bool upsert(Duration t, CropBox box) {
    var clamped = t;
    if (clamped < Duration.zero) clamped = Duration.zero;
    if (clamped > duration) clamped = duration;
    final idx = _frames.indexWhere((f) => f.t == clamped);
    if (idx >= 0) {
      _frames[idx] = Keyframe(t: clamped, box: box);
      return true;
    }
    if (_frames.length >= maxFrames) return false;
    _frames.add(Keyframe(t: clamped, box: box));
    _frames.sort((a, b) => a.t.compareTo(b.t));
    return true;
  }

  /// 还原回单框模式。
  void reset(CropBox box) {
    _frames
      ..clear()
      ..add(Keyframe(t: Duration.zero, box: box));
  }

  /// t 处的框：分段线性插值；区间外取最近端点。
  CropBox boxAt(Duration t) {
    assert(_frames.isNotEmpty, 'boxAt requires at least one keyframe');
    if (_frames.length == 1) return _frames.single.box;
    if (t <= _frames.first.t) return _frames.first.box;
    if (t >= _frames.last.t) return _frames.last.box;
    for (var i = 0; i < _frames.length - 1; i++) {
      final a = _frames[i];
      final b = _frames[i + 1];
      if (t >= a.t && t <= b.t) {
        final span = (b.t - a.t).inMilliseconds;
        final f = span == 0 ? 0.0 : (t - a.t).inMilliseconds / span;
        double lerp(double x, double y) => x + (y - x) * f;
        return CropBox(
          cx: lerp(a.box.cx, b.box.cx),
          cy: lerp(a.box.cy, b.box.cy),
          w: lerp(a.box.w, b.box.w),
          h: lerp(a.box.h, b.box.h),
        );
      }
    }
    return _frames.last.box;
  }

  /// FFmpeg crop 逐帧表达式（规格 §5.3）。
  ///
  /// 输出高 = min(outH, 框像素高) —— 不放大规则（Review Focus #3）；
  /// 输出宽按当前框比例。单帧：常量 `crop=w:h:x:y`；
  /// 多帧：`crop='w(t):h(t):x(t):y(t)'` 的分段线性 if(lt(t,..)) 链。
  String cropExpr(int srcW, int srcH, {required int outH}) {
    if (_frames.isEmpty) {
      final b = CropBox.centered('9:16');
      return _constantExpr(b, srcW, srcH, outH);
    }
    if (_frames.length == 1) {
      return _constantExpr(_frames.single.box, srcW, srcH, outH);
    }
    // 多关键帧：对 w/h/x/y 各建一条分段线性表达式（像素域）
    // w/h 必须 clamp 进源尺寸——FFmpeg crop 对 w/h 超界直接报错
    final wE = _pixelExpr(srcW, srcH, outH, (b) => b.w,
        (p, v) => (v * srcW).clamp(16.0, srcW.toDouble()));
    final hE = _pixelExpr(srcW, srcH, outH, (b) => b.h,
        (p, v) => (v * srcH).clamp(16.0, srcH.toDouble()));
    final xE = _pixelExpr(srcW, srcH, outH, (b) => b.left,
        (p, v) => (v * srcW - p / 2).clamp(0.0, srcW.toDouble()));
    final yE = _pixelExpr(srcW, srcH, outH, (b) => b.top,
        (p, v) => (v * srcH - p / 2).clamp(0.0, srcH.toDouble()));
    return "crop='w($wE):h($hE):x($xE):y($yE)'";
  }

  /// 常量 crop 表达式（含不放大缩放建议由命令层处理；这里输出像素 crop）。
  String _constantExpr(CropBox box, int srcW, int srcH, int outH) {
    final r = box.toPixelRect(srcW, srcH);
    return 'crop=${r.width.round()}:${r.height.round()}:${r.left.round()}:${r.top.round()}';
  }

  /// 把归一化属性 [pick] 映射到像素域表达式（关键帧时间 t 单位秒）。
  String _pixelExpr(int srcW, int srcH, int outH,
      double Function(CropBox) pick, double Function(double p, double v) map) {
    final parts = <String>[];
    for (var i = 0; i < _frames.length - 1; i++) {
      final a = _frames[i];
      final b = _frames[i + 1];
      final va = map(pick(a.box), pick(a.box));
      final vb = map(pick(b.box), pick(b.box));
      final tSec = (a.t.inMilliseconds / 1000).toStringAsFixed(3);
      parts.add('lt(t,$tSec)*($va+(($vb)-($va))*(t-$tSec)/${((b.t - a.t).inMilliseconds / 1000).toStringAsFixed(3)})');
    }
    // 最后一段之后固定为末帧值
    final last = _frames.last;
    final vlast = map(pick(last.box), pick(last.box));
    final expr = parts.join('+');
    if (expr.isEmpty) return vlast.toStringAsFixed(0);
    // 上式是"每段贡献"的和式近似：前段在 t 超过后其贡献为满值，需要
    // 用真正的 if 链才能精确。为精确起见改为从后往前嵌套 if：
    parts.clear();
    var nested = vlast.toStringAsFixed(2);
    for (var i = _frames.length - 2; i >= 0; i--) {
      final a = _frames[i];
      final b = _frames[i + 1];
      final va = map(pick(a.box), pick(a.box)).toStringAsFixed(2);
      final vb = map(pick(b.box), pick(b.box)).toStringAsFixed(2);
      final tSec = (a.t.inMilliseconds / 1000).toStringAsFixed(3);
      final span = ((b.t - a.t).inMilliseconds / 1000).toStringAsFixed(3);
      nested = 'if(lt(t,$tSec),($va+(($vb)-($va))*(t-$tSec)/$span),$nested)';
    }
    parts.add(nested);
    return parts.join();
  }
}
