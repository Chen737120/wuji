import 'dart:math';

import 'mosaic_region.dart';

/// 打码滤镜图生成（spec §5.1）：
/// 每区域一节 split 流 → crop（区域 w/h 取全轨最大框常量，位置随帧）→
/// 效果处理（马赛克=neighbor 缩放往返；模糊=gblur）→ overlay 贴回底流。
///
/// [at] 非空时输出常量坐标链（快照）；空时输出逐帧 if 链（导出）。
/// 返回 (滤镜图段, 打码完成流标签)；空列表返回原输入标签直通。
(String, String) buildMosaicGraph(
  List<MosaicRegion> regions, {
  required int srcW,
  required int srcH,
  required String inputLabel,
  Duration? at,
}) {
  if (regions.isEmpty) return ('', inputLabel);

  final splitOuts =
      List.generate(regions.length, (i) => '[mr$i]').join();
  final parts = <String>[
    '[$inputLabel]split=${regions.length + 1}[mbg]$splitOuts',
  ];
  var base = 'mbg';
  for (var i = 0; i < regions.length; i++) {
    final r = regions[i];
    final (cw, ch) = r.track.fixedCropSize(srcW, srcH);
    final (String x, String y) = at == null
        ? r.track.topLeftExprs(cw, ch, srcW, srcH)
        : _constPair(r.track.topLeftAt(at, cw, ch, srcW, srcH));
    // 含逗号的表达式必须单引号包裹（filtergraph 语法，与 cropExpr 同法）
    String q(String e) => e.contains(',') ? "'$e'" : e;

    final String effectSeg;
    switch (r.effect) {
      case MosaicEffect.mosaic:
        final sw = r.mosaicTargetWidth(r.strength);
        final sh = (sw * ch / cw).round().clamp(2, ch);
        effectSeg =
            'scale=$sw:$sh:flags=neighbor,scale=$cw:$ch:flags=neighbor';
      case MosaicEffect.blur:
        final sigma =
            r.blurSigma(min(cw, ch), r.strength).toStringAsFixed(2);
        effectSeg = 'gblur=sigma=$sigma:steps=2';
    }
    parts
      ..add('[mr$i]crop=$cw:$ch:${q(x)}:${q(y)}[mrq$i]')
      ..add('[mrq$i]$effectSeg[meff$i]')
      ..add('[$base][meff$i]overlay=${q(x)}:${q(y)}[mo$i]');
    base = 'mo$i';
  }
  return (parts.join(';'), base);
}

/// 快照常量坐标 (int,int) → 字符串对（与逐帧表达式在 crop/overlay 参数位同构）。
(String, String) _constPair((int, int) p) =>
    (p.$1.toString(), p.$2.toString());
