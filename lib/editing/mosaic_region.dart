import 'keyframes.dart';

/// 打码效果类型。
enum MosaicEffect { mosaic, blur }

/// 打码区域（spec §4）：区域框轨迹复用 [KeyframeTrack]（单框=全程生效）。
class MosaicRegion {
  MosaicRegion({
    required this.id,
    required this.track,
    this.effect = MosaicEffect.blur,
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

  /// gblur 高斯 sigma：按区域**短边**比例化（spec §3.3）。
  /// 旧 boxblur 半径按宽计算且上限 20，但 min 包未编译 boxblur（真机 APK
  /// 实证），改用 gblur；gblur 的 sigma 无 chroma 半径硬限制。
  double blurSigma(int fixedShortPx, int strength) {
    final s = fixedShortPx * (0.012 + 0.018 * strength);
    return s.clamp(0.5, 30.0).toDouble(); // num.clamp 返回 num，需转 double
  }
}
