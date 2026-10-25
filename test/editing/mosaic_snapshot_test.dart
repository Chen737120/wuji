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
}
