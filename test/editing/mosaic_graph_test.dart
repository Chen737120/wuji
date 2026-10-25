import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/crop_box.dart';
import 'package:wuji/editing/keyframes.dart';
import 'package:wuji/editing/mosaic_graph.dart';
import 'package:wuji/editing/mosaic_region.dart';

MosaicRegion region(String id, MosaicEffect effect,
    {int strength = 1, int frames = 1}) {
  final track = KeyframeTrack(duration: const Duration(seconds: 10));
  if (frames == 1) {
    track.reset(const CropBox(cx: 0.5, cy: 0.5, w: 0.2, h: 0.2));
  } else {
    for (var i = 0; i < frames; i++) {
      track.upsert(Duration(seconds: i), CropBox(cx: 0.3 + 0.05 * i, cy: 0.5, w: 0.2, h: 0.2));
    }
  }
  return MosaicRegion(id: id, track: track, effect: effect, strength: strength);
}

void main() {
  test('空列表：原样返回输入标签', () {
    final (g, out) = buildMosaicGraph(const [], srcW: 1280, srcH: 720, inputLabel: '0:v');
    expect(g, isEmpty);
    expect(out, '0:v');
  });

  test('单区域常量模式（快照）：split→crop 常量→neighbor scale→overlay', () {
    final (g, out) = buildMosaicGraph([region('r1', MosaicEffect.mosaic)],
        srcW: 1280, srcH: 720, inputLabel: '0:v', at: Duration.zero);
    // 0.2*1280=256 宽 → 固定尺寸 (256,144)，坐标 640-128=512, 360-72=288
    expect(g, contains('[0:v]split=2[mbg][mr0]'));
    expect(g, contains('crop=256:144:512:288'));
    expect(g, contains('scale=16:9:flags=neighbor,scale=256:144:flags=neighbor'));
    expect(g, contains('overlay=512:288'));
    expect(out, 'mo0');
  });

  test('单区域逐帧模式（导出）：if 链单引号包裹', () {
    final (g, out) = buildMosaicGraph([region('r1', MosaicEffect.mosaic, frames: 5)],
        srcW: 1280, srcH: 720, inputLabel: '0:v');
    expect(g, contains("if(lt(t,"));
    expect(g, contains("'")); // 含逗号表达式被引号包裹
    expect(out, 'mo0');
  });

  test('10 关键帧哨兵：任一单滤镜参数 <2000 字符（Review Focus #4，4KB 硬限制防御）', () {
    final (g, _) = buildMosaicGraph([region('r1', MosaicEffect.mosaic, frames: 10)],
        srcW: 1280, srcH: 720, inputLabel: '0:v');
    for (final seg in g.split(';')) {
      expect(seg.length, lessThan(2000), reason: '滤镜节超长: $seg');
    }
  });

  test('两区域串联：底流标签链 mo0→mo1，split=3', () {
    final (g, out) = buildMosaicGraph(
        [region('r1', MosaicEffect.mosaic), region('r2', MosaicEffect.blur)],
        srcW: 1280, srcH: 720, inputLabel: '0:v');
    expect(g, contains('split=3[mbg][mr0][mr1]'));
    expect(g, contains('[mbg][meff0]overlay='));
    expect(g, contains('[mo0][meff1]overlay='));
    expect(out, 'mo1');
  });

  test('模糊模式：boxblur luma_radius 按比例', () {
    final (g, _) = buildMosaicGraph([region('r1', MosaicEffect.blur, strength: 1)],
        srcW: 1280, srcH: 720, inputLabel: '0:v');
    expect(g, contains('boxblur=luma_radius=13')); // blurRadius(256,1)=round(256*0.05)=13
  });

  test('PC ffmpeg 冒烟（真滤镜解析，非断言测试）：常量链抽一帧成功', () {
    // 手动执行（不进 CI）：
    // 把上面常量模式用例的 g 写入 build/mosaic-smoke-graph.txt，然后：
    // C:/Users/chen/tools/ffmpeg/ffmpeg-9.0.2-essentials_build/bin/ffmpeg.exe -y -ss 1 -i testdata/fancam-motion-demo/src.mp4 \
    //   -filter_complex "<graph>" -map "[mo0]" -frames:v 1 build/mosaic-smoke.jpg
    // 预期：rc=0，jpg 生成，打开目检马赛克块位置居中。
  });
}
