// ffprobe JSON 解析（v1.5.26 走查 F3）：rotation 元数据 → display 尺寸。
// 手机竖拍常见「编码 1920×1080 + rotation=90」：video_player 与 ffmpeg
// autorotate 后显示 1080×1920，打码编辑器/导出必须按 display 尺寸建域。
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/ffmpeg_probe.dart';

String _json({
  int width = 1920,
  int height = 1080,
  String? sideDataRotation,
  String? tagRotate,
}) {
  final side = sideDataRotation == null
      ? ''
      : ',"side_data_list":[{"side_data_type":"Display Matrix","rotation":$sideDataRotation}]';
  final tags = tagRotate == null ? '' : ',"tags":{"rotate":"$tagRotate"}';
  return '{"streams":[{"codec_type":"video","width":$width,"height":$height,'
      '"avg_frame_rate":"30/1"$side$tags}],'
      '"format":{"duration":"10.0"}}';
}

void main() {
  test('side_data rotation=-90：显示尺寸交换为竖屏', () {
    final info = parseMediaInformationJson(_json(sideDataRotation: '-90'))!;
    expect(info.rotationDegrees, -90);
    expect(info.width, 1920); // 编码尺寸语义不变（compare 等仍按它用）
    expect(info.height, 1080);
    expect(info.displayWidth, 1080);
    expect(info.displayHeight, 1920);
  });

  test('side_data rotation=90/270 均交换；0/180 不交换', () {
    for (final r in ['90', '270', '-270']) {
      final info = parseMediaInformationJson(_json(sideDataRotation: r))!;
      expect(info.displayWidth, 1080, reason: r);
      expect(info.displayHeight, 1920, reason: r);
    }
    for (final r in ['0', '180', '-180']) {
      final info = parseMediaInformationJson(_json(sideDataRotation: r))!;
      expect(info.displayWidth, 1920, reason: r);
      expect(info.displayHeight, 1080, reason: r);
    }
  });

  test('兼容旧字段 tags.rotate（字符串）', () {
    final info = parseMediaInformationJson(_json(tagRotate: '90'))!;
    expect(info.rotationDegrees, 90);
    expect(info.displayWidth, 1080);
    expect(info.displayHeight, 1920);
  });

  test('side_data 优先于 tags.rotate', () {
    final info = parseMediaInformationJson(
        _json(sideDataRotation: '-90', tagRotate: '0'))!;
    expect(info.rotationDegrees, -90);
    expect(info.displayWidth, 1080);
  });

  test('无 rotation 字段：display 与编码尺寸相同（行为不变）', () {
    final info = parseMediaInformationJson(_json())!;
    expect(info.rotationDegrees, 0);
    expect(info.displayWidth, info.width);
    expect(info.displayHeight, info.height);
  });
}
