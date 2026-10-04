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

  test('单帧：常量 crop + 不放大规则（框高<720 时输出=框高）', () {
    // 源 1080x1920，框 0.5x0.5 → 像素 540x960。9:16 比例下框高 960 ≥720 → 输出 720
    final t = track([[0.5, 0.5, 0.5, 0.5]]);
    final cmd = buildFancamCommand(
        srcPath: '/s.mp4', track: t, srcW: 1080, srcH: 1920);
    expect(cmd, contains('crop=540:960:270:480'));
    expect(cmd, contains('scale=-2:720'));
    expect(cmd, contains('-c:a aac'));
    expect(cmd, isNot(contains('-an')));
  });

  test('480p 源：框像素高 <720 → 不放大（输出=框像素高）(Review Focus #3)', () {
    // 源 480x854（9:16 附近），框全高 → 像素高 854？不——9:16 框在 854 高上=854*9/16=480 宽
    // 框 0.5 高 → 像素高 427 < 720 → 输出 427（原分辨率，不放大）
    final t = track([[0.5, 0.5, 0.9412, 0.5]]);
    final cmd = buildFancamCommand(
        srcPath: '/s.mp4', track: t, srcW: 480, srcH: 854);
    // scale 高度=框像素高 427（round）
    expect(cmd, contains('scale=-2:427'));
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

  test('双帧：命令含分段线性 crop 表达式', () {
    final t = track([
      [0.2, 0.2, 0.4, 0.4],
      [0.6, 0.6, 0.8, 0.8],
    ]);
    final cmd = buildFancamCommand(
        srcPath: '/s.mp4', track: t, srcW: 1080, srcH: 1920);
    expect(cmd, contains('if(lt(t,'));
    expect(cmd, contains('crop='));
  });
}
