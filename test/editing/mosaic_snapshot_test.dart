import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/crop_box.dart';
import 'package:wuji/editing/keyframes.dart';
import 'package:wuji/editing/mosaic_region.dart';
import 'package:wuji/editing/mosaic_snapshot.dart';

MosaicRegion _region() {
  final track = KeyframeTrack(duration: const Duration(seconds: 10))
    ..reset(const CropBox(cx: 0.5, cy: 0.5, w: 0.2, h: 0.2));
  return MosaicRegion(id: 'r1', track: track);
}

void main() {
  test('快照命令：双 -ss 精确 seek（Review Focus #2）＋常量链＋map 输出标签', () {
    final cmd = buildSnapshotCommand(
      srcPath: '/tmp/a.mp4',
      regions: [_region()],
      at: const Duration(seconds: 5, milliseconds: 300),
      srcW: 1280,
      srcH: 720,
      outPath: '/cache/snap.jpg',
    );
    // 输入侧定位 t-1s=4.3s，输出侧补 1s → 帧精确
    expect(cmd, contains('-ss 4.300 -i "/tmp/a.mp4" -ss 1.000'));
    expect(cmd, contains('-frames:v 1'));
    expect(cmd, contains('-map "[mo0]"'));
    expect(cmd, contains('overlay=')); // 常量坐标（无 if(lt(t,）
    expect(cmd.contains('if(lt(t,'), isFalse);
  });

  test('at < 1s：输入侧 0，输出侧补 at 全长', () {
    final cmd = buildSnapshotCommand(
      srcPath: '/tmp/a.mp4',
      regions: [_region()],
      at: const Duration(milliseconds: 400),
      srcW: 1280,
      srcH: 720,
      outPath: '/cache/snap.jpg',
    );
    expect(cmd, contains('-ss 0.000 -i "/tmp/a.mp4" -ss 0.400'));
  });

  test('sourceOffset（内嵌 trimStart）：源视频 seek 加偏移，滤镜图仍按 track 时间', () {
    // 两帧轨迹（0s cx=0.2 / 10s cx=0.8），at=5.3s 的插值常量 x=546；
    // 若误用源时间 25.3s 会钳到末帧 cx=0.8 → x=896。
    final track = KeyframeTrack(duration: const Duration(seconds: 10))
      ..upsert(Duration.zero,
          const CropBox(cx: 0.2, cy: 0.5, w: 0.2, h: 0.2))
      ..upsert(const Duration(seconds: 10),
          const CropBox(cx: 0.8, cy: 0.5, w: 0.2, h: 0.2));
    final cmd = buildSnapshotCommand(
      srcPath: '/tmp/a.mp4',
      regions: [MosaicRegion(id: 'r1', track: track)],
      at: const Duration(seconds: 5, milliseconds: 300),
      sourceOffset: const Duration(seconds: 20),
      srcW: 1280,
      srcH: 720,
      outPath: '/cache/snap.jpg',
    );
    expect(cmd, contains('-ss 24.300 -i "/tmp/a.mp4" -ss 1.000'));
    expect(cmd, contains('overlay=546:')); // track 时间 5.3 的插值坐标
    expect(cmd.contains('overlay=896:'), isFalse); // 不是源时间 25.3 的末帧坐标
  });

  test('sourceOffset 且 at<1s：总定位=源 20.4s（19.4 快进 + 1.0 精确补）', () {
    // 双 -ss 的总定位 = 输入侧 + 输出侧。修复文档示例写 20.400+0.400
    // 实为源 20.8s（多走一个 at）；此处按同一“sourceOffset+at”口径断言。
    final cmd = buildSnapshotCommand(
      srcPath: '/tmp/a.mp4',
      regions: [_region()],
      at: const Duration(milliseconds: 400),
      sourceOffset: const Duration(seconds: 20),
      srcW: 1280,
      srcH: 720,
      outPath: '/cache/snap.jpg',
    );
    expect(cmd, contains('-ss 19.400 -i "/tmp/a.mp4" -ss 1.000'));
  });

  test('空区域：capture 直接返回 null 不起 FFmpeg 会话（buildSnapshotCommand 仍可用）', () {
    // captureMosaicSnapshot 依赖平台通道，纯逻辑侧只验证空列表短路契约
    // 由实现保证（regions.isEmpty → null）；此处锁 buildSnapshotCommand 不空指针。
    final cmd = buildSnapshotCommand(
      srcPath: '/tmp/a.mp4',
      regions: const [],
      at: Duration.zero,
      srcW: 1280,
      srcH: 720,
      outPath: '/cache/snap.jpg',
    );
    // 空列表：graph 直通（buildMosaicGraph 返回原输入标签），map 用输入标签
    expect(cmd, contains('-map "[0:v]"'));
  });

  test('片尾钳制（反馈 #6）：sourceDuration=10s、at=10s → 源定位钳到 9.85s', () {
    final cmd = buildSnapshotCommand(
      srcPath: '/tmp/a.mp4',
      regions: [_region()],
      at: const Duration(seconds: 10),
      srcW: 1280,
      srcH: 720,
      outPath: '/cache/snap.jpg',
      sourceDuration: const Duration(seconds: 10),
    );
    // sourceAt 10s > cap 9.85s → 钳到 9.85s：输入侧 8.850 + 输出侧 1.000
    expect(cmd, contains('-ss 8.850 -i "/tmp/a.mp4" -ss 1.000'));
  });

  test('片尾钳制：极短源 cap=150ms → sourceAt=0.150', () {
    final cmd = buildSnapshotCommand(
      srcPath: '/tmp/a.mp4',
      regions: [_region()],
      at: const Duration(milliseconds: 300),
      srcW: 1280,
      srcH: 720,
      outPath: '/cache/snap.jpg',
      sourceDuration: const Duration(milliseconds: 300),
    );
    // cap = 300-150 = 150ms ≥0 → sourceAt=0.150（<1s：输入侧 0，输出侧补 0.150）
    expect(cmd, contains('-ss 0.000 -i "/tmp/a.mp4" -ss 0.150'));
  });

  test('片尾钳制防负值：cap 为负 → sourceAt=0 抽首帧', () {
    final cmd = buildSnapshotCommand(
      srcPath: '/tmp/a.mp4',
      regions: [_region()],
      at: const Duration(milliseconds: 100),
      srcW: 1280,
      srcH: 720,
      outPath: '/cache/snap.jpg',
      sourceDuration: const Duration(milliseconds: 100),
    );
    // cap = 100-150 = -50ms < 0 → sourceAt=0
    expect(cmd, contains('-ss 0.000 -i "/tmp/a.mp4" -ss 0.000'));
  });

  test('片尾钳制只动抽帧定位点：滤镜图坐标仍是 track 口径', () {
    // 轨迹同上（0s cx=0.2 / 10s cx=0.8）；at=10s 取末帧 cx=0.8。
    // 若实现误把钳制后的时间传给滤镜图（at≈9.85s），x 会偏离末帧值 896。
    final track = KeyframeTrack(duration: const Duration(seconds: 10))
      ..upsert(Duration.zero,
          const CropBox(cx: 0.2, cy: 0.5, w: 0.2, h: 0.2))
      ..upsert(const Duration(seconds: 10),
          const CropBox(cx: 0.8, cy: 0.5, w: 0.2, h: 0.2));
    final cmd = buildSnapshotCommand(
      srcPath: '/tmp/a.mp4',
      regions: [MosaicRegion(id: 'r1', track: track)],
      at: const Duration(seconds: 10),
      sourceOffset: const Duration(seconds: 20),
      srcW: 1280,
      srcH: 720,
      outPath: '/cache/snap.jpg',
      sourceDuration: const Duration(seconds: 30),
    );
    // 源定位：sourceAt=30s > cap 29.85s → 钳到 29.85s（输入侧 28.850 + 输出侧 1.000）
    expect(cmd, contains('-ss 28.850 -i "/tmp/a.mp4" -ss 1.000'));
    // 滤镜图：track 时间 10s 的末帧坐标 cx=0.8 → x=896（不受钳制影响）
    expect(cmd, contains('overlay=896:'));
  });

  test('snapshotMatchesPosition：时刻匹配的快照才可显示（2026-10-29 预览 T1）',
      () {
    // path 非空且 snapshotAt == position → true
    expect(
      snapshotMatchesPosition(
          path: '/cache/snap.jpg',
          snapshotAt: const Duration(seconds: 5),
          position: const Duration(seconds: 5)),
      isTrue,
    );
  });

  test('snapshotMatchesPosition：位置一变即失效（核心回归：暂停不露旧快照）',
      () {
    // at=0s 的旧快照，position 已到 5s → false（否则暂停瞬间露出 0s 打码）
    expect(
      snapshotMatchesPosition(
          path: '/cache/snap.jpg',
          snapshotAt: Duration.zero,
          position: const Duration(seconds: 5)),
      isFalse,
    );
  });

  test('snapshotMatchesPosition：无快照恒 false', () {
    expect(
      snapshotMatchesPosition(
          path: null,
          snapshotAt: const Duration(seconds: 5),
          position: const Duration(seconds: 5)),
      isFalse,
    );
  });

  test('snapshotStillValid：删到 0 个区域即失效（P2-2）', () {
    expect(snapshotStillValid(regionCount: 0), isFalse);
    expect(snapshotStillValid(regionCount: 1), isTrue);
    expect(snapshotStillValid(regionCount: 5), isTrue);
  });
}
