import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/crop_box.dart';
import 'package:wuji/editing/fancam_export.dart';
import 'package:wuji/editing/keyframes.dart';

void main() {
  KeyframeTrack track(List<List<double>> frames) {
    final t = KeyframeTrack(duration: const Duration(seconds: 10));
    for (var i = 0; i < frames.length; i++) {
      final f = frames[i];
      t.upsert(
        Duration(seconds: i * 5),
        CropBox(cx: f[0], cy: f[1], w: f[2], h: f[3]),
      );
    }
    return t;
  }

  test('单帧：常量 crop + 不放大规则（框高<1080 时输出=框高）', () {
    // 源 1080x1920，框 0.5x0.5 → 像素 540x960。9:16 比例下框高 960 ≥720 → 输出 720
    final t = track([[0.5, 0.5, 0.5, 0.5]]);
    final cmd = buildFancamCommand(
        srcPath: '/s.mp4', track: t, srcW: 1080, srcH: 1920);
    expect(cmd, contains('crop=540:960:270:480'));
    expect(cmd, contains('scale=-2:960'));
    expect(cmd, contains('-c:a aac'));
    expect(cmd, isNot(contains('-an')));
  });

  test('480p 源：框像素高 <720 → 不放大（输出=框像素高，偶数化）(Review Focus #3)', () {
    // 源 480x854（9:16 附近），框 0.5 高 → 像素高 427 < 720 → 输出取 427；
    // v1.5.7 起 h264_mediacodec 要求偶数尺寸 → 偶数化为 426
    final t = track([[0.5, 0.5, 0.9412, 0.5]]);
    final cmd = buildFancamCommand(
        srcPath: '/s.mp4', track: t, srcW: 480, srcH: 854);
    expect(cmd, contains('scale=-2:426'));
  });

  test('无声源 → -an（Review Focus #1）', () {
    final t = track([[0.5, 0.5, 0.5, 0.5]]);
    final cmd = buildFancamCommand(
        srcPath: '/s.mp4',
        track: t,
        srcW: 1080,
        srcH: 1920,
        hasAudio: false);
    expect(cmd, contains('-an'));
    expect(cmd, isNot(contains('-c:a aac')));
  });

  test('双帧：命令含分段缓动 crop 表达式', () {
    final t = track([
      [0.2, 0.2, 0.4, 0.4],
      [0.6, 0.6, 0.8, 0.8],
    ]);
    final cmd = buildFancamCommand(
        srcPath: '/s.mp4', track: t, srcW: 1080, srcH: 1920);
    expect(cmd, contains('if(lt(t,'));
    expect(cmd, contains('crop='));
  });

  test('视频码率显式分档（2026-10-08 需求 #1）：1080→16M / 960→10M / 426→6M', () {
    // 框高 ≥1080 → 输出 1080 → 16M
    final tall = track([[0.5, 0.5, 0.5625, 1.0]]); // h=1.0×1920=1920≥1080
    expect(
        buildFancamCommand(
            srcPath: '/s.mp4', track: tall, srcW: 1080, srcH: 1920),
        contains('-b:v 16M'));
    // 框高 960 → 输出 960 → 10M
    final mid = track([[0.5, 0.5, 0.5, 0.5]]);
    expect(
        buildFancamCommand(
            srcPath: '/s.mp4', track: mid, srcW: 1080, srcH: 1920),
        contains('-b:v 10M'));
    // 框高 426 → 输出 426 → 6M
    final small = track([[0.5, 0.5, 0.9412, 0.5]]);
    expect(
        buildFancamCommand(
            srcPath: '/s.mp4', track: small, srcW: 480, srcH: 854),
        contains('-b:v 6M'));
  });
}
