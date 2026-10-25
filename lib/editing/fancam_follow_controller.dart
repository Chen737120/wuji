// 骑行跟随控制器＋锚点余弦混合＋sendcmd 生成（Task 2，纯 Dart）。
// 算法唯一真源：docs/superpowers/prototypes/fancam-follow/gen_d5.dart
// （_load 低置信 carry 与 _axis 骑行状态机逐行照搬，常量名 kZx 等对应原型 zx 等）。
// 与原型的差异（均在 Controller ruling / spec 范围内）：
//   ① fps/时长参数化（原型硬编码 30fps 与 Conf.dur）；
//   ② 输入装载自 Task 1 的 TrackPoint 列表（原型读 CSV 行；4 列语义 t秒,x,y,score 相同）；
//   ③ 锚点余弦混合为本任务新增（原型无锚点；spec §2.4）；
//   ④ sendcmd 在原型「中心−半宽取整」基础上按 Review Focus #2 追加偶数化
//      （yuv420p 色度偶对齐，语义同 keyframes.dart _evenClamp——原型两次踩坑的防线）；
//   ⑤ 原型 stderr 统计 port 为 FollowAxisStats 返回值（bodyHalf=90 常量照搬）。
// 本文件不 import package:flutter（无头可测）；经 crop_box.dart 间接持有 dart:ui 类型
// （CropBox 为用户比例框，与 Task 4 页面状态直接衔接）。
import 'dart:math' as math;

import 'crop_box.dart';
import 'fancam_tracker.dart';

/// 控制器参数（gen_d5 L11-16 逐行照搬；spec §2.2 参数表——横轴按框宽、纵轴按框高）。
const double kFollowTau = 0.15; // 频率分离 EMA τ（秒）
const double kZx = 0.12, kV0x = 0.09, kStopX = 0.05; // 横轴：死区/基础回中/到位
const double kZy = 0.05, kV0y = 0.03, kStopY = 0.03; // 纵轴
const double kHiFrac = 0.30; // 紧急回中加速起点：|o| > 0.30·box
const double kKem = 8.0; // 每超出 1px 加 8px/s
const double kCapFrac = 0.85; // 框速总上限 0.85·box/秒
const double kCarryScore = 0.6; // score<0.6 沿用上一有效位置（spec §2.1）
const double kBodyHalf = 90.0; // 近缘统计的人体半宽（gen_d5 常量照搬，仅统计用）
const double kAnchorWindowSec = 1.0; // 锚点余弦过渡半窗（spec §2.4 前后各约 1s）

/// 用户比例框 → 裁剪像素尺寸：floor→偶数化→clamp ≥16 ≤源最大偶数。
/// 语义同 keyframes.dart `_evenClamp`（抄实现逻辑）——偶数尺寸/偏移防
/// yuv420p+mediacodec 边缘伪影（2026-10-12 预览绿边黑边踩坑）。
/// 注：floor 对「归一化×源尺寸」的浮点回乘已对 340/604/272/484 实测验证
/// （偏差方向向上或精确，floor 均回目标值）。
(int, int) followCropSize(CropBox box, int srcW, int srcH) {
  int evenClamp(double px, int src) {
    final maxEven = src - (src & 1);
    var v = px.floor() & ~1;
    if (v < 16) v = 16;
    if (v > maxEven) v = maxEven;
    return v;
  }

  return (evenClamp(box.w * srcW, srcW), evenClamp(box.h * srcH, srcH));
}

/// 轨迹时刻 [trackT]（相对修剪起点）的跟随框（归一化，Task 4 预览叠加层逐帧取框）：
/// 中心取最后一个 t≤trackT 的轨迹点（像素→归一化），尺寸恒为
/// [FollowSession.box]（跟随框尺寸恒定语义）。centers 已在 recompute 时
/// clamp 进画面（框完整可见），此处 clamp 仅兜底；空轨迹（未 recompute）
/// 回退 session.box 不抛。
CropBox followBoxAt(FollowSession session, Duration trackT) {
  final cs = session.centers;
  if (cs.isEmpty) return session.box;
  final t = trackT.inMicroseconds / 1e6;
  var lo = 0, hi = cs.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (cs[mid].t <= t) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return CropBox(
    cx: (cs[lo].x / session.srcW).clamp(0.0, 1.0),
    cy: (cs[lo].y / session.srcH).clamp(0.0, 1.0),
    w: session.box.w,
    h: session.box.h,
  );
}

/// 单轴控制统计（gen_d5 stderr 行的 port；无行为影响，测试断言/日志用）。
class FollowAxisStats {
  int moves = 0; // 触发骑行次数
  int emFrames = 0; // 回中受限帧（骑行分量被挤压）
  int nearEdge = 0; // 碰缘帧（|off|＋bodyHalf > box/2）
  int outFrames = 0; // 中心出框帧（|off| > box/2）
  double maxE = 0.0; // 最大偏移 px
  int frames = 0;

  @override
  String toString() =>
      '触发$moves 最大偏移${maxE.round()}px 碰缘$nearEdge 出框$outFrames 回中受限$emFrames 帧$frames';
}

/// 骑行跟随会话：持有跟踪点列与用户比例框，生成运镜轨迹（含锚点混合）与 sendcmd 文本。
///
/// 用法：构造 → [recompute] 生成基线轨迹 → 预览中拖框时 [insertAnchor]（混合同步更新
/// [centers]）→ [buildSendCmd] 导出。锚点默认取当前轨迹该时刻中心（拖框场景由调用方
/// 传归一化目标位置）。
class FollowSession {
  FollowSession({
    required List<TrackPoint> points,
    required this.box,
    required this.srcW,
    required this.srcH,
  }) : points = List.unmodifiable(points);

  /// 跟踪器原始点列（Task 1 输出；t 秒、x/y 全分辨率像素、score 置信度）。
  final List<TrackPoint> points;

  /// 用户比例框（归一化；像素尺寸经 [followCropSize]，控制器参数按其比例化）。
  final CropBox box;
  final int srcW;
  final int srcH;

  final List<({Duration t, double cx, double cy})> _anchors = [];

  /// 手动锚点（中心归一化；按时间升序）。
  List<({Duration t, double cx, double cy})> get anchors =>
      List.unmodifiable(_anchors);

  /// 当前运镜轨迹（全分辨率像素中心；recompute 后含锚点混合与 clamp）。
  List<({double t, double x, double y})> centers = const [];

  /// 两轴统计（基线轨迹口径，同 gen_d5 stderr；空点列为全零）。
  FollowAxisStats statsX = FollowAxisStats();
  FollowAxisStats statsY = FollowAxisStats();

  double? _lastFps;
  Duration? _lastDuration;

  /// 重算轨迹：低置信 carry 装载 → 两轴骑行控制（gen_d5 _axis）→ 锚点余弦混合
  /// → clamp 进画面（ruling：保锚点也不出界）。
  void recompute({required double fps, required Duration duration}) {
    _lastFps = fps;
    _lastDuration = duration;
    statsX = FollowAxisStats();
    statsY = FollowAxisStats();
    final samples = _loadCarried();
    if (samples.isEmpty) {
      centers = const [];
      return;
    }
    final (boxW, boxH) = followCropSize(box, srcW, srcH);
    final frames = (duration.inMicroseconds / 1e6 * fps).floor();
    final (tx, bx) = _axis(
      samples: samples,
      axis: 0,
      box: boxW.toDouble(),
      srcDim: srcW,
      fps: fps,
      frames: frames,
    );
    final (ty, by) = _axis(
      samples: samples,
      axis: 1,
      box: boxH.toDouble(),
      srcDim: srcH,
      fps: fps,
      frames: frames,
    );
    final n = tx.length;
    final cx = [for (final e in tx) e.$2];
    final cy = [for (final e in ty) e.$2];
    // 锚点混合（spec §2.4）：基线 b(t)，每锚点 delta=anchor−b(ta)，
    // |t−ta|≤1s 区间加 delta·0.5·(1+cos(π(t−ta)/1s))（锚点时刻权值=1）；
    // 多锚点按时间顺序依次叠加。
    for (final a in _anchors) {
      final ta = a.t.inMicroseconds / 1e6;
      final axPx = a.cx * srcW, ayPx = a.cy * srcH;
      final i0 = _indexAtTime(tx, ta);
      final dx = axPx - tx[i0].$2;
      final dy = ayPx - ty[i0].$2;
      for (var i = 0; i < n; i++) {
        final dt = tx[i].$1 - ta;
        if (dt.abs() > kAnchorWindowSec) continue;
        final w = 0.5 * (1 + math.cos(math.pi * dt / kAnchorWindowSec));
        cx[i] += w * dx;
        cy[i] += w * dy;
      }
    }
    // 混合后 clamp：锚点也不出界（gen_d5 循环内只对 bSlow 做过，混合后再兜一次）
    centers = [
      for (var i = 0; i < n; i++)
        (
          t: tx[i].$1,
          x: cx[i].clamp(boxW / 2, srcW - boxW / 2).toDouble(),
          y: cy[i].clamp(boxH / 2, srcH - boxH / 2).toDouble(),
        ),
    ];
    statsX = bx;
    statsY = by;
  }

  /// 在 [t] 插入锚点（同刻替换，升序插入）。位置默认取当前轨迹该时刻中心
  /// （ruling 1）；预览拖框场景由调用方传拖动后的归一化位置 [cx]/[cy]。
  /// 有基线时混合同步更新 [centers]。
  void insertAnchor(Duration t, {double? cx, double? cy}) {
    final clamped = _clampToDuration(t);
    double cxNorm;
    double cyNorm;
    if (cx != null && cy != null) {
      cxNorm = cx;
      cyNorm = cy;
    } else {
      if (centers.isEmpty) {
        throw ArgumentError('centers 为空：先 recompute 或显式传 cx/cy');
      }
      final i = _indexAtTime(
        [for (final c in centers) (c.t, c.x)],
        clamped.inMicroseconds / 1e6,
      );
      cxNorm = centers[i].x / srcW;
      cyNorm = centers[i].y / srcH;
    }
    final a = (t: clamped, cx: cxNorm.clamp(0.0, 1.0), cy: cyNorm.clamp(0.0, 1.0));
    final idx = _anchors.indexWhere((e) => e.t == clamped);
    if (idx >= 0) {
      _anchors[idx] = a;
    } else {
      _anchors.add(a);
      _anchors.sort((x, y) => x.t.compareTo(y.t));
    }
    _reblendIfPossible();
  }

  /// 复制会话并替换比例框（Task 4 自动模式改框尺寸：比例 chips / 角柄缩放 /
  /// 还原——[box] 为 final，须重建会话）。锚点原样保留（同刻同位置）并重混合，
  /// 轨迹帧数不变；原会话完全不受影响（页面侧以新会话替换旧引用）。
  FollowSession withBox(CropBox newBox,
      {required double fps, required Duration duration}) {
    final s = FollowSession(
        points: points, box: newBox, srcW: srcW, srcH: srcH);
    s.recompute(fps: fps, duration: duration);
    for (final a in _anchors) {
      s.insertAnchor(a.t, cx: a.cx, cy: a.cy);
    }
    return s;
  }

  /// 删除距 [t] 最近（时间上）的锚点；混合同步更新 [centers]。
  void removeAnchor(Duration t) {
    if (_anchors.isEmpty) return;
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < _anchors.length; i++) {
      final d = (_anchors[i].t - t).abs().inMicroseconds;
      if (d < bestD) {
        bestD = d.toDouble();
        best = i;
      }
    }
    _anchors.removeAt(best);
    _reblendIfPossible();
  }

  /// 最长连续 score<[kCarryScore] 段时长 >1s → 提示文案，否则 null（spec §2.1）。
  /// 段时长 = 段内帧数×帧周期（帧周期取前两点 t 差；Task 1 语义 t=frame/fps）。
  String? lossHint() {
    if (points.length < 2) return null;
    final frameDt = points[1].t - points[0].t;
    if (frameDt <= 0) return null;
    var best = 0, cur = 0;
    for (final p in points) {
      if (p.score < kCarryScore) {
        cur++;
        if (cur > best) best = cur;
      } else {
        cur = 0;
      }
    }
    return best * frameDt > 1.0 ? '目标丢失，点击画面重新锁定' : null;
  }

  /// 生成 sendcmd 命令文件内容：每帧两行 `t crop x X;` / `t crop y Y;`（按帧升序）。
  /// X/Y = 中心−半宽 **取整再偶数化**（Review Focus #2：原型踩过忘减半宽与
  /// yuv420p 奇偏移伪影两次坑）；t 相对修剪起点（centers 自 0 起）。
  /// 行必须是 sendcmd **三段式** target+command+arg：ffmpeg 9 实测两段式
  /// `crop.x V` 会被解析为 target:"crop.x" command:"V"——无滤镜可匹配、
  /// 不报错、静默失效（Task 3 PC 冒烟发现，证据见
  /// .superpowers/sdd/2026-10-25-fancam-follow/task-3-report.md）。
  String buildSendCmd() {
    final (boxW, boxH) = followCropSize(box, srcW, srcH);
    final buf = StringBuffer();
    for (final c in centers) {
      final t = c.t.toStringAsFixed(4);
      buf.write('$t crop x ${(c.x - boxW / 2).round() & ~1};\n');
      buf.write('$t crop y ${(c.y - boxH / 2).round() & ~1};\n');
    }
    return buf.toString();
  }

  // ---- 内部实现 ----

  /// 低置信 carry（gen_d5 _load 逐行照搬，Review Focus #1）：
  /// score<[kCarryScore] 帧沿用上一有效位置；之前无有效帧时用自身位置（原型兜底）。
  List<(double, double, double)> _loadCarried() {
    final s = <(double, double, double)>[];
    (double, double)? last;
    for (final p in points) {
      final good = p.score >= kCarryScore;
      if (good) last = (p.x, p.y);
      s.add((p.t, last?.$1 ?? p.x, last?.$2 ?? p.y));
    }
    return s;
  }

  /// 单轴骑行控制器（gen_d5 _axis 逐行照搬；仅把 stderr 统计改为返回值）。
  /// 返回（轨迹 List<(t, b)>, 统计）。
  (List<(double, double)>, FollowAxisStats) _axis({
    required List<(double, double, double)> samples,
    required int axis, // 0 横（按框宽） 1 纵（按框高）
    required double box,
    required int srcDim,
    required double fps,
    required int frames,
  }) {
    final dt = 1 / fps;
    final z = (axis == 0 ? kZx : kZy) * box;
    final v0 = (axis == 0 ? kV0x : kV0y) * box;
    final stop = (axis == 0 ? kStopX : kStopY) * box;
    final hi = kHiFrac * box, cap = kCapFrac * box;
    final s0 = _sampleAt(samples, 0);
    var lp = axis == 0 ? s0.$1 : s0.$2, bSlow = lp, riding = false, oPrev = 0.0;
    final stats = FollowAxisStats();
    final traj = <(double, double)>[(0, lp)];
    for (var i = 1; i <= frames; i++) {
      final t = i * dt;
      final svRaw = _sampleAt(samples, t);
      final sv = axis == 0 ? svRaw.$1 : svRaw.$2;
      lp += (sv - lp) * dt / kFollowTau;
      // oNoAct：框不动时人物本帧的表观偏移（含本帧漂移）
      final oNoAct = lp - bSlow;
      final drift = oNoAct - oPrev; // 人物慢速移动量（带符号）
      if (!riding && oNoAct.abs() > z) {
        riding = true;
        stats.moves++;
      }
      if (riding) {
        // 框移动 = 骑行（吸收 drift，o 不因人物移动增长）＋回中（朝 o 归零方向 vRec·dt）
        final vRec =
            v0 + (oNoAct.abs() > hi ? kKem * (oNoAct.abs() - hi) : 0.0);
        var move = drift + oNoAct.sign * vRec * dt;
        if (move.abs() > cap * dt) move = move.sign * cap * dt; // 超速截断
        if (move.abs() < drift.abs() && drift.sign == oNoAct.sign) {
          stats.emFrames++; // 回中被挤压
        }
        bSlow += move;
        final oNew = lp - bSlow;
        if (oNew.abs() <= stop || oNew.sign != oNoAct.sign) {
          riding = false; // 到位或过中心
        }
      }
      final b = (bSlow + (sv - lp)).clamp(box / 2, srcDim - box / 2);
      bSlow = b - (sv - lp);
      final off = sv - b; // 实际表观偏移（含快层校验）
      oPrev = lp - bSlow;
      if (off.abs() > stats.maxE) stats.maxE = off.abs();
      if (off.abs() + kBodyHalf > box / 2) stats.nearEdge++;
      if (off.abs() > box / 2) stats.outFrames++;
      stats.frames++;
      traj.add((t, b));
    }
    return (traj, stats);
  }

  /// 采样（语义同 gen_d5 sAt）：返回最后一个 t_i ≤ t 的采样 (x, y)；
  /// 全部 t_i > t 时回首点（原型 i 退到 0 的兜底一致）。二分定位。
  static (double, double) _sampleAt(List<(double, double, double)> s, double t) {
    var lo = 0, hi = s.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (s[mid].$1 <= t) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return (s[lo].$2, s[lo].$3);
  }

  /// 最后一个 t_i ≤ t 的下标（t 小于首点时为 0；t 超尾时为末点）。
  static int _indexAtTime(List<(double, double)> traj, double t) {
    var lo = 0, hi = traj.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (traj[mid].$1 <= t) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  Duration _clampToDuration(Duration t) {
    final d = _lastDuration;
    if (d == null) {
      return t < Duration.zero ? Duration.zero : t;
    }
    if (t < Duration.zero) return Duration.zero;
    if (t > d) return d;
    return t;
  }

  void _reblendIfPossible() {
    final fps = _lastFps;
    final dur = _lastDuration;
    if (fps != null && dur != null && points.isNotEmpty) {
      recompute(fps: fps, duration: dur);
    }
  }
}
