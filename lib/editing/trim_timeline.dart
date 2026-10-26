/// 修剪时间轴换算（v1.5.26 走查 F1/F11）。
///
/// 编辑器/轨道内部统一用 **track 时间**（0 = trimStart）；播放器 seek 与
/// 快照的源视频 seek 用 **源时间**（trimStart + track 时间）。所有入口
/// （播放同步、点进度条 seek、打点、轨道圆点、快照）都必须经这里换算，
/// 禁止在页面里零散加减偏移——否则漏改一处就会整体错位。
library;

/// 播放器当前位置 → track 时间（钳进 [0, duration]）。
Duration trackPosition({
  required Duration playerPosition,
  required Duration trimStart,
  required Duration duration,
}) {
  final p = playerPosition - trimStart;
  if (p < Duration.zero) return Duration.zero;
  return p > duration ? duration : p;
}

/// track 时间 → 播放器/源视频位置。
Duration sourcePosition(Duration track, Duration trimStart) => trimStart + track;

/// 关键帧/锚点的轨道时间 → FilmStrip 显示时间（源时间轴）。
List<Duration> displayKeyframeTimes(
        Iterable<Duration> trackTimes, Duration trimStart) =>
    [for (final t in trackTimes) t + trimStart];

/// FilmStrip 回调的显示时间 → 轨道时间（只在这里减一次偏移）。
Duration trackTimeOfDisplay(Duration displayTime, Duration trimStart) =>
    displayTime - trimStart;
