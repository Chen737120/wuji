import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/crop_box.dart';
import 'package:wuji/editing/fancam_export.dart';
import 'package:wuji/editing/keyframes.dart';
import 'package:wuji/editing/mosaic_region.dart';

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

  test('单帧：常量 crop + 不放大规则（框高<1080 时输出=框高，16 对齐）', () {
    // 源 1080x1920，框 0.5x0.5 → 像素 540x960。高 960 恰为 16 倍数；
    // 宽 540 → 16 对齐 544（宏块 padding 防护，2026-10-12）
    final t = track([[0.5, 0.5, 0.5, 0.5]]);
    final cmd = buildFancamCommand(
        srcPath: '/s.mp4', track: t, srcW: 1080, srcH: 1920);
    expect(cmd, contains('crop=540:960:270:480'));
    expect(cmd, contains('scale=544:960'));
    expect(cmd, contains('-c:a aac'));
    expect(cmd, isNot(contains('-an')));
  });

  test('480p 源：框像素高 <1080 → 不放大（输出=框像素高，16 对齐）(Review Focus #3)', () {
    // 源 480x854，框 0.5 高 → crop 像素 450x426 → 输出高 426→16 对齐 432、
    // 宽 450×432/426≈456→464（v1.5.24：非 16 倍数会被编码器 pad 出绿边黑边）
    final t = track([[0.5, 0.5, 0.9412, 0.5]]);
    final cmd = buildFancamCommand(
        srcPath: '/s.mp4', track: t, srcW: 480, srcH: 854);
    expect(cmd, contains('scale=464:432'));
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

  test('视频码率显式分档（2026-10-08 需求 #1）：1088→16M / 960→10M / 432→6M', () {
    // 框高 ≥1080 → 输出 1088（1080 的 16 对齐）→ 16M
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
    // 框高 426 → 输出 432 → 6M
    final small = track([[0.5, 0.5, 0.9412, 0.5]]);
    expect(
        buildFancamCommand(
            srcPath: '/s.mp4', track: small, srcW: 480, srcH: 854),
        contains('-b:v 6M'));
  });

  test('fancamOutputSize：16 宏块对齐 + 不放大（绿边黑边根因回归）', () {
    // 2026-10-12 真机实证：278×534 输出被编码器 pad 到 288×544（右10底10
    // conformance crop），部分设备 TextureView 不应用 crop → 绿条黑条。
    // 输出必须本身就是 16 的倍数。
    final (w, h) = fancamOutputSize(278, 534);
    expect(w % 16, 0, reason: 'w=$w');
    expect(h % 16, 0, reason: 'h=$h');
    expect(h, lessThanOrEqualTo(534)); // 不放大：不超 crop 原生高
    // 常规 9:16 框：540x960 → (544, 960)
    expect(fancamOutputSize(540, 960), (544, 960));
    // 大框：crop 高超 1080 → 输出高 1088（1080 的 16 对齐）
    final (bw, bh) = fancamOutputSize(864, 1536);
    expect(bh, 1088);
    expect(bw % 16, 0, reason: 'bw=$bw');
  });

  test('直拍＋打码：-vf 切 filter_complex，打码在前裁剪在后，打码模式显式 map 音频', () {
    final regions = [
      MosaicRegion(
        id: 'r1',
        track: KeyframeTrack(duration: const Duration(seconds: 30))
          ..reset(const CropBox(cx: 0.5, cy: 0.5, w: 0.2, h: 0.2)),
      ),
    ];
    final cmd = buildFancamCommand(
      srcPath: '/tmp/a.mp4',
      track: track([
        [0.5, 0.5, 0.5, 0.5],
        [0.3, 0.3, 0.4, 0.4],
        [0.7, 0.7, 0.6, 0.6],
      ]),
      srcW: 1280,
      srcH: 720,
      regions: regions,
    );
    expect(cmd, contains('-filter_complex "'));
    expect(cmd, isNot(contains('-vf "')));
    // 顺序：overlay 在 crop 之前（打码先于裁剪，spec §5.2）
    final overlayIdx = cmd.indexOf('[mo0]');
    final cropIdx = cmd.indexOf('crop=', overlayIdx);
    expect(cropIdx, greaterThan(overlayIdx));
    expect(cmd, contains('-map "[vout]"'));
    expect(cmd, contains('-map 0:a?')); // filter_complex 下显式 map 音频
  });

  test('直拍无打码：命令与旧版一致（空 regions 零回归）', () {
    final cmd = buildFancamCommand(
      srcPath: '/tmp/a.mp4',
      track: track([
        [0.5, 0.5, 0.5, 0.5],
        [0.3, 0.3, 0.4, 0.4],
        [0.7, 0.7, 0.6, 0.6],
      ]),
      srcW: 1280,
      srcH: 720,
    );
    expect(cmd, contains('-vf "'));
    expect(cmd.contains('-filter_complex'), isFalse);
  });
}
