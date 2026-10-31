import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全 App 唯一的彩色：点缀色预设（规格 §9/§3.6）。
/// 2026-10-07 用户反馈：去掉草绿（保留翠芽+彩虹六色，共 7 档）。
enum AccentPreset {
  jade(0xFF3FA26F, '翠芽'),
  red(0xFFE5484D, '绯红'),
  orange(0xFFF08C1E, '暖橙'),
  yellow(0xFFD9A514, '明黄'),
  cyan(0xFF14A8B8, '湖青'),
  blue(0xFF3B6FE0, '宝蓝'),
  purple(0xFF8B5CF6, '紫罗兰');

  const AccentPreset(this.value, this.label);
  final int value;
  final String label;

  Color get color => Color(value);
}

/// 统计图表调色板（2026-10-07 用户需求：取借鉴软件老师统计前十色，
/// 类别 ≤10 各一色、**第 11 个类别起循环前十个**；「其他」类用中性灰）。
const List<Color> kRainbowPalette = [
  Color(0xFFEC6FA5), // 1 粉
  Color(0xFF5B8DEF), // 2 蓝
  Color(0xFF4CC98A), // 3 绿
  Color(0xFF8E6BE8), // 4 紫
  Color(0xFFE8B33C), // 5 黄
  Color(0xFFE96A78), // 6 红粉
  Color(0xFF2FC4D9), // 7 青
  Color(0xFF5A78E8), // 8 蓝紫
  Color(0xFFE8506B), // 9 玫红
  Color(0xFFA8D04A), // 10 黄绿
];

const Color kOtherSliceColor = Color(0xFFB8B8B4); // 「其他」/兜底中性灰

/// 图表色调亮（2026-10-07 用户反馈：老师/舞室条形整体调亮一档，
/// 显得轻松活泼——同色相提高亮度，舞种环形图保持原色）。
Color brightenChartColor(Color c) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withLightness((hsl.lightness + 0.10).clamp(0.0, 0.78))
      .withSaturation((hsl.saturation - 0.05).clamp(0.0, 1.0))
      .toColor();
}

class AppColors {
  static const bg = Color(0xFFFAFAF8);
  static const ink = Color(0xFF1A1A1A);
  static const secondary = Color(0xFF8A8A86);
  static const hairline = Color(0xFFECECE8);
  static const faint = Color(0xFFB8B8B4);
}

/// 字阶常量（spec §5 / 任务书 T1）。仅供首页 v1 重写与后续新代码引用，
/// 不批量替换现有页面文字（App 视觉零变化）。颜色由调用处指定，此处不耦合。
class AppText {
  AppText._();

  /// 首页 Large Title「记录」：28 / w800 / 字距 −2%（原型 .t-large）
  static const TextStyle homeTitle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.56,
    height: 1.12,
  );

  /// 页头标题（其余 tab）：16 / w700 / 字距 3px（原型 .t-page）
  static const TextStyle pageTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 3.0,
  );

  /// AppBar 居中标题：15 / w600 / 字距 2px（原型 .push-title）
  static const TextStyle appBarTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 2.0,
  );

  /// 记录卡正文（感受）：13.5 / 行高 1.62
  static const TextStyle cardBody = TextStyle(fontSize: 13.5, height: 1.62);

  /// 入口卡标题：18 / w800
  static const TextStyle entryTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
  );

  /// 正文：13 / 行高 1.65
  static const TextStyle body = TextStyle(fontSize: 13, height: 1.65);

  /// 元数据行：11
  static const TextStyle meta = TextStyle(fontSize: 11);

  /// 辅助 / 页脚：10
  static const TextStyle caption = TextStyle(fontSize: 10);

  /// 字段盒标签：9
  static const TextStyle fieldLabel = TextStyle(fontSize: 9);

  /// 统计数字：18 / w700 / 等宽数字（原型 .sq-num）
  static const TextStyle statNumber = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// 弹簧参数（任务书 §0 / spec §2.1）：response→stiffness=(2π/response)²、
/// damping=2·ratio·√stiffness（SpringDescription.withDampingRatio 内部即此式）。
double _springStiffness(double responseSec) {
  final w = 2 * math.pi / responseSec;
  return w * w;
}

/// 默认弹簧：damping ratio 1.0 / response 0.35s
final SpringDescription kSpringDefault = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: _springStiffness(0.35),
  ratio: 1.0,
);

/// 手势动量弹簧：damping ratio 0.8 / response 0.3s（带释放初速度）
final SpringDescription kSpringGesture = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: _springStiffness(0.3),
  ratio: 0.8,
);

/// push/pop 转场弹簧：damping ratio 1.0 / response 0.4s
final SpringDescription kSpringTransition = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: _springStiffness(0.4),
  ratio: 1.0,
);

class ThemeController extends ChangeNotifier {
  static const _key = 'accentPreset';
  AccentPreset _preset = AccentPreset.jade;
  AccentPreset get accentPreset => _preset;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final name = sp.getString(_key);
    if (name != null) {
      _preset = AccentPreset.values
          .firstWhere((e) => e.name == name, orElse: () => AccentPreset.jade);
    }
    notifyListeners();
  }

  Future<void> setPreset(AccentPreset p) async {
    _preset = p;
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, p.name);
  }
}

class AppTheme {
  static ThemeData light(AccentPreset preset) {
    final accent = preset.color;
    final scheme = ColorScheme.light(
      primary: accent,
      secondary: accent,
      surface: AppColors.bg,
      error: const Color(0xFFC0392B),
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
    );
    return base.copyWith(
      dividerColor: AppColors.hairline,
      textTheme: base.textTheme
          .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
