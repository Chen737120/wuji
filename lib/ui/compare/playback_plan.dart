/// 判定「已播到结尾」的阈值，与 compare_page 的 _atEnd 同口径。
const _endThreshold = Duration(milliseconds: 80);

/// 同屏对比播放起点计算（纯函数，单测覆盖）。
///
/// 返回 null = 原地续播，不需要 seek；返回起点 = 两路各自 seek 一次即达
/// 正确错位关系（同刻 我的.position = 老师.position − offset）。
///
/// 缺陷背景（缺陷会话 2026-10-26）：v1.5.22 的归零重播块每路连发 2 次
/// seek（归零 + offset 起点）且在毫秒级内完成，ExoPlayer 逐次替换 seek
/// 目标时真机出现 surface 灰块。这里把重播收敛成「每路 1 次直达 seek」。
({Duration teacher, Duration mine})? planPlayStart({
  required Duration teacherPos,
  required Duration teacherDur,
  required Duration minePos,
  required Duration offset,
}) {
  final bool isRestart = teacherDur > Duration.zero &&
      teacherPos >= teacherDur - _endThreshold;
  if (isRestart) {
    // 重播：每路 1 次 seek 直达预览起点（与首次播放/导出起点同语义）。
    // 老师的 seek 目标钳进 [0, teacherDur]：offset 由时间微调面板自由步进，
    // 可能超过视频时长，超出时交给 play() 从 0 起（video_player 对 ENDED
    // 态 play() 会自动回零）——目标值本身不留非法值，保证纯函数可判定。
    // 我的目标不做钳制：本函数没有「我的」时长，video_player 的 seekTo
    // 自身会钳到 [0, duration]。
    if (offset >= Duration.zero) {
      return (
        teacher: offset > teacherDur ? teacherDur : offset,
        mine: Duration.zero,
      );
    }
    return (teacher: Duration.zero, mine: -offset);
  }
  final offMs = offset.inMilliseconds;
  if (offMs > 0 && teacherPos < offset) {
    return (teacher: offset, mine: Duration.zero);
  }
  if (offMs < 0 && minePos < -offset) {
    return (teacher: Duration.zero, mine: -offset);
  }
  return null;
}
