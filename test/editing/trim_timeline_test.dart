// 修剪时间轴换算（v1.5.26 走查 F1/F11）：内部统一 track 时间（0=trimStart），
// 播放器/源视频 seek 用源时间。所有入口共用这两个纯函数，防止页面里零散加减。
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/trim_timeline.dart';

void main() {
  group('trackPosition（播放器位置 → track 时间）', () {
    test('trimStart=0 时恒等', () {
      expect(
        trackPosition(
            playerPosition: const Duration(seconds: 5),
            trimStart: Duration.zero,
            duration: const Duration(seconds: 10)),
        const Duration(seconds: 5),
      );
    });

    test('trimStart=20s：源 25s → track 5s', () {
      expect(
        trackPosition(
            playerPosition: const Duration(seconds: 25),
            trimStart: const Duration(seconds: 20),
            duration: const Duration(seconds: 10)),
        const Duration(seconds: 5),
      );
    });

    test('播放器位置早于修剪起点 → 钳到 0', () {
      expect(
        trackPosition(
            playerPosition: const Duration(seconds: 10),
            trimStart: const Duration(seconds: 20),
            duration: const Duration(seconds: 10)),
        Duration.zero,
      );
    });

    test('超出修剪时长 → 钳到 duration', () {
      expect(
        trackPosition(
            playerPosition: const Duration(seconds: 40),
            trimStart: const Duration(seconds: 20),
            duration: const Duration(seconds: 10)),
        const Duration(seconds: 10),
      );
    });
  });

  group('sourcePosition（track 时间 → 播放器/源视频位置）', () {
    test('trimStart=0 时恒等', () {
      expect(sourcePosition(const Duration(seconds: 5), Duration.zero),
          const Duration(seconds: 5));
    });

    test('trimStart=20s：track 5s → 源 25s', () {
      expect(sourcePosition(const Duration(seconds: 5), const Duration(seconds: 20)),
          const Duration(seconds: 25));
    });
  });

  group('关键帧圆点显示时间（F11）', () {
    test('trimStart=0 时圆点时间与轨道时间一致', () {
      expect(
        displayKeyframeTimes(
            [Duration.zero, const Duration(seconds: 5)], Duration.zero),
        [Duration.zero, const Duration(seconds: 5)],
      );
    });

    test('trimStart=20s 时圆点显示源时间、回调换回轨道时间（只加一次偏移）', () {
      final shown = displayKeyframeTimes(
          [const Duration(seconds: 5)], const Duration(seconds: 20));
      expect(shown, [const Duration(seconds: 25)]);
      expect(trackTimeOfDisplay(shown.single, const Duration(seconds: 20)),
          const Duration(seconds: 5));
    });
  });
}
