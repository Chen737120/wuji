
/// 对比重叠区间计算（规格 §4.2）。
/// 偏移语义：offset 正值＝我的视频延后（老师先出画）；负值＝我的提前。
/// 重叠区间 = [max(0, offset), min(teacherDur, myDur + offset))。
class OverlapCalc {
  OverlapCalc._();

  /// 重叠区间起点（在两视频"已对齐时间轴"上）。
  static Duration start(Duration offset) =>
      offset < Duration.zero ? Duration.zero : offset;

  /// 重叠区间终点（区间为空时返回 start，即长度 0）。
  static Duration end(Duration teacherDur, Duration myDur, Duration offset) {
    final a = teacherDur;
    final b = myDur + offset;
    final s = start(offset);
    final raw = a < b ? a : b;
    return raw < s ? s : raw;
  }

  /// 导出条件：重叠 ≥ 1 秒（规格 §7）。
  static bool exportable(Duration end, Duration start) =>
      end.inMilliseconds - start.inMilliseconds >= 1000;
}

/// 重叠时长（供导出命令构建复用）。
Duration overlapLength(Duration teacherDur, Duration myDur, Duration offset) {
  final s = OverlapCalc.start(offset);
  var e = OverlapCalc.end(teacherDur, myDur, offset);
  if (e < s) e = s;
  return e - s;
}

/// 微调文案（规格：offset<0 显示"提前"，>0 显示"延后"）。
String describeOffset(Duration offset) {
  final ms = offset.inMilliseconds.abs();
  final seconds = (ms / 1000).toStringAsFixed(2);
  if (offset == Duration.zero) return '未偏移';
  return offset < Duration.zero
      ? '我的视频提前 $seconds 秒'
      : '我的视频延后 $seconds 秒';
}
