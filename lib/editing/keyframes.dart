import 'dart:math' as math;

import 'crop_box.dart';

/// 单个关键帧：时间点＋当时的框。
class Keyframe {
  const Keyframe({required this.t, required this.box});
  final Duration t;
  final CropBox box;
}

/// 关键帧轨道（规格 §5.2）：
/// - ≤10 个；插入自动排序去重（同刻替换）；t clamp 到 [0, duration]；
/// - [boxAt] 分段 smoothstep 缓动插值（cx/cy/w/h 各自 lerp）；
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

  /// t 处的框：分段缓动插值（与导出表达式一致，WYSIWYG）；
  /// 区间外取最近端点。
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
        final e = _dwellEase(f);
        double lerp(double x, double y) => x + (y - x) * e;
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
  /// FFmpeg 硬限制：crop 的 **w/h 只在初始化时求值一次（不能用 t）**，
  /// 仅 x/y 支持逐帧表达式。因此多帧方案（v1.5.7）：
  /// - w/h 取**所有帧框的最大值**作为常量；
  /// - x/y 用嵌套 if(lt(t,..)) 链分段线性跟随各帧框中心；
  /// - 「框大小动画」降级为固定最大框，位置跟随完整保留
  ///   （2026-10-05 真机报错 "Unknown function in 'w(...)'" 的修复）。
  String cropExpr(int srcW, int srcH) {
    final (fw, fh) = fixedCropSize(srcW, srcH);
    if (_frames.isEmpty) {
      final b = CropBox.centered('9:16', srcW: srcW, srcH: srcH);
      return 'crop=$fw:$fh:'
          '${_clampedCenter(b.cx, fw, srcW)}:${_clampedCenter(b.cy, fh, srcH)}';
    }
    if (_frames.length == 1) {
      final b = _frames.single.box;
      return 'crop=$fw:$fh:'
          '${_clampedCenter(b.cx, fw, srcW)}:${_clampedCenter(b.cy, fh, srcH)}';
    }
    // 多帧：x/y 表达式内含逗号，参数必须单引号包裹（filtergraph 语法）
    final xE = _posExpr(fw.toDouble(), srcW, (b) => b.cx);
    final yE = _posExpr(fh.toDouble(), srcH, (b) => b.cy);
    return "crop=$fw:$fh:x='$xE':y='$yE'";
  }

  /// 固定框像素尺寸（各帧框取最大，clamp 进源、≥16px）。
  /// cropExpr / 导出输出高 / 预览参数单共用此单一真源。
  ///
  /// **宽高必须偶数化**：奇数尺寸/偏移送 yuv420p+mediacodec 会在画面
  /// 边缘出绿色/黑色垃圾列（2026-10-12 用户报告预览绿边黑边）。
  (int, int) fixedCropSize(int srcW, int srcH) {
    var w = 0.0;
    var h = 0.0;
    for (final f in _frames) {
      w = math.max(w, f.box.w);
      h = math.max(h, f.box.h);
    }
    if (_frames.isEmpty) {
      final b = CropBox.centered('9:16', srcW: srcW, srcH: srcH);
      w = b.w;
      h = b.h;
    }
    return (_evenClamp(w * srcW, srcW), _evenClamp(h * srcH, srcH));
  }

  /// 像素值取整→偶数→clamp 进源（上限取源的最大偶数）。
  static int _evenClamp(double px, int src) {
    final maxEven = src - (src & 1);
    var v = px.floor() & ~1;
    if (v < 16) v = 16;
    if (v > maxEven) v = maxEven;
    return v;
  }

  /// 中心→crop 左上角像素偏移：clamp 进源并**偶数化**（yuv420p 色度
  /// 偶对齐；搭配 fixedCropSize 的偶数宽高，杜绝编码器边缘伪影）。
  int _clampedCenter(double centerNorm, int sizePx, int src) {
    final maxEven = src - sizePx - ((src - sizePx) & 1);
    var v = (centerNorm * src - sizePx / 2).floor() & ~1;
    if (v < 0) v = 0;
    if (v > maxEven) v = maxEven;
    return v;
  }

  /// x/y 逐帧表达式：嵌套 if 时间分段，跟随框中心（节点值 clamp 进源内）。
  ///
  /// 时间轴语义（v1.5.8 修"第一关键帧前画面慢慢移动"）：
  /// t<首帧 → **固定在第一帧位置**（旧实现误用 lerp 外推）；
  /// [t_i, t_{i+1}) → 缓动 lerp(v_i, v_{i+1})；t≥末帧 → 固定末帧位置。
  ///
  /// 缓动（2026-10-12 用户反馈"画面移动感明显"二轮优化）：整段 smoothstep
  /// 虽然两端减速，但全程仍在持续移动，段一长就是明显漂移。改为**停顿式
  /// （dwell）**：每段两端各停住 [_holdFrac] 时间，只在中间窗口内 smoothstep
  /// 摇过去——观感是"停稳→干脆地摇到位→再停稳"，预览 [boxAt] 同用此曲线。
  String _posExpr(double sizePx, int src, double Function(CropBox) pick) {
    String nodeOf(CropBox b) =>
        _clampedCenter(pick(b), sizePx.round(), src).toString();
    final s = _holdFrac.toStringAsFixed(2); // '0.25'
    final w = (1 - 2 * _holdFrac).toStringAsFixed(2); // '0.50'
    var inner = nodeOf(_frames.last.box); // 最内层：t≥末帧 → 固定末帧
    for (var i = _frames.length - 1; i >= 0; i--) {
      final tSec =
          (_frames[i].t.inMilliseconds / 1000).toStringAsFixed(3);
      final String branch;
      if (i == 0) {
        branch = nodeOf(_frames[0].box);
      } else {
        final a = nodeOf(_frames[i - 1].box);
        final b = nodeOf(_frames[i].box);
        final t0 =
            (_frames[i - 1].t.inMilliseconds / 1000).toStringAsFixed(3);
        final span = ((_frames[i].t - _frames[i - 1].t).inMilliseconds / 1000)
            .toStringAsFixed(3);
        final p = '((t-$t0)/$span)';
        final u = '(($p-$s)/$w)';
        branch =
            '($a+($b-($a))*if(lt($p,$s),0,if(lt($p,${1 - _holdFrac}),($u*$u*(3-2*$u)),1)))';
      }
      inner = 'if(lt(t,$tSec),$branch,$inner)';
    }
    return inner;
  }
}

/// 每段两端停住的时间占比：前后各 25% 保持静止，中段 50% 完成 smoothstep 摇镜。
const _holdFrac = 0.25;

/// 停顿式缓动：u∈[0,1] → 两端 [_holdFrac] 内 0/1（停住），中段 smoothstep。
double _dwellEase(double u) {
  final x = u.clamp(0.0, 1.0);
  if (x <= _holdFrac) return 0;
  if (x >= 1 - _holdFrac) return 1;
  return _smoothstep((x - _holdFrac) / (1 - 2 * _holdFrac));
}

/// smoothstep 缓动：f∈[0,1] → 3f²-2f³（两端导数为 0）。
double _smoothstep(double f) {
  final x = f.clamp(0.0, 1.0);
  return x * x * (3 - 2 * x);
}
