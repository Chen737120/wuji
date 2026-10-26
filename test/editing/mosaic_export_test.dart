import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/crop_box.dart';
import 'package:wuji/editing/ffmpeg_probe.dart';
import 'package:wuji/editing/fancam_export.dart';
import 'package:wuji/editing/keyframes.dart';
import 'package:wuji/editing/mosaic_export.dart';
import 'package:wuji/editing/mosaic_region.dart';

MediaInfo info({bool hasAudio = true, int width = 1920, int height = 1080}) =>
    MediaInfo(durationMs: 30000, width: width, height: height, fps: 30, hasAudio: hasAudio);

MosaicRegion oneRegion() => MosaicRegion(
  id: 'r1',
  track: KeyframeTrack(duration: const Duration(seconds: 30))
    ..reset(const CropBox(cx: 0.5, cy: 0.5, w: 0.2, h: 0.2)),
);

void main() {
  test('命令结构：filter_complex＋map 输出＋分辨率保持源（无 scale 全帧滤镜）', () {
    final cmd = buildMosaicExportCommand(
        srcPath: '/tmp/a.mp4', regions: [oneRegion()], info: info());
    expect(cmd, contains('-filter_complex "'));
    expect(cmd, contains('-map "[mo0]"'));
    expect(cmd, isNot(contains('scale=1920'))); // 不做全帧缩放
    expect(cmd, contains('-c:v h264_mediacodec'));
    expect(cmd, contains('-b:v 16M')); // 1080p 分档
  });

  test('有音轨：AAC 标准化（spec L1 修订口径，与直拍同参数）', () {
    final cmd = buildMosaicExportCommand(
        srcPath: '/tmp/a.mp4', regions: [oneRegion()], info: info());
    expect(cmd, contains('-c:a aac -ar 48000 -ac 2 -b:a 128k'));
  });

  test('无音轨：-an（Review Focus #1）', () {
    final cmd = buildMosaicExportCommand(
        srcPath: '/tmp/a.mp4',
        regions: [oneRegion()],
        info: info(hasAudio: false));
    expect(cmd, contains('-an'));
    expect(cmd, isNot(contains('-c:a')));
  });

  test('rotation=90：滤镜/码率按 display 尺寸（1080×1920），不按编码 1920×1080', () {
    final rotated = MediaInfo(
        durationMs: 30000,
        width: 1920,
        height: 1080,
        fps: 30,
        hasAudio: true,
        rotationDegrees: 90);
    final cmd = buildMosaicExportCommand(
        srcPath: '/tmp/a.mp4', regions: [oneRegion()], info: rotated);
    // 0.2×0.2 区域按 display 1080×1920 → 216×384（偶对齐后不变）
    expect(cmd, contains('crop=216:384:'));
    expect(cmd.contains('crop=384:216:'), isFalse);
    // 编码高 1080 会被判 16M；修正后按 display 高 1920 仍是 16M，
    // 故用 720 高的旋转源区分：1280×720 rotation=90 → display 720×1280
    final small = MediaInfo(
        durationMs: 30000,
        width: 1280,
        height: 720,
        fps: 30,
        hasAudio: true,
        rotationDegrees: 90);
    final smallCmd = buildMosaicExportCommand(
        srcPath: '/tmp/a.mp4', regions: [oneRegion()], info: small);
    expect(smallCmd, contains('-b:v 16M')); // displayHeight=1280
    expect(smallCmd, isNot(contains('-b:v 10M')));
  });

  test('videoBitrateFor 分档与原 _videoBitrate 一致（公开化回归）', () {
    expect(videoBitrateFor(1080), '16M');
    expect(videoBitrateFor(720), '10M');
    expect(videoBitrateFor(480), '6M');
  });
}
