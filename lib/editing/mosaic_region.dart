import 'keyframes.dart';

/// 打码效果类型。
enum MosaicEffect { mosaic, blur }

/// 打码区域（spec §4）：区域框轨迹复用 [KeyframeTrack]（单框=全程生效）。
class MosaicRegion {
  MosaicRegion({
    required this.id,
    required this.track,
    this.effect = MosaicEffect.mosaic,
    this.strength = 1,
  }) : assert(strength >= 0 && strength <= 2, 'strength 须为 0..2');

  final String id;
  final KeyframeTrack track;
  MosaicEffect effect;

  /// 强度档位：0=细 1=中 2=粗。
  int strength;

  static const maxRegions = 5;

  /// 马赛克缩小目标宽（px）：按强度档 32/16/8（块数定义本身，非比例化）。
  int mosaicTargetWidth(int strength) => switch (strength) {
        0 => 32,
        1 => 16,
        _ => 8,
      };

  /// boxblur 半径：按区域固定宽比例化（2%+3%·档位），clamp 1..20。
  int blurRadius(int fixedWpx, int strength) {
    final r = (fixedWpx * (0.02 + 0.03 * strength)).round();
    return r.clamp(1, 20);
  }
}
