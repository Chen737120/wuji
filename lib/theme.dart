import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全 App 唯一的彩色：点缀色预设（规格 §9/§3.6）。
/// 2026-10-05 用户反馈：保留翠芽，其余换为彩虹七色（共 8 档）。
enum AccentPreset {
  jade(0xFF3FA26F, '翠芽'),
  red(0xFFE5484D, '绯红'),
  orange(0xFFF08C1E, '暖橙'),
  yellow(0xFFD9A514, '明黄'),
  green(0xFF34B04A, '草绿'),
  cyan(0xFF14A8B8, '湖青'),
  blue(0xFF3B6FE0, '宝蓝'),
  purple(0xFF8B5CF6, '紫罗兰');

  const AccentPreset(this.value, this.label);
  final int value;
  final String label;

  Color get color => Color(value);
}

/// 彩虹七色调色板（2026-10-05 用户需求：舞种分布/老师/舞室统计
/// 每一项一个颜色，不再单色系）。浅色底上取中等饱和、明度相近的七色；
/// 超过 7 项循环使用；「其他」类用中性灰。
const List<Color> kRainbowPalette = [
  Color(0xFFE5484D), // 红
  Color(0xFFF08C1E), // 橙
  Color(0xFFD9A514), // 黄
  Color(0xFF34B04A), // 绿
  Color(0xFF14A8B8), // 青
  Color(0xFF3B6FE0), // 蓝
  Color(0xFF8B5CF6), // 紫
];

const Color kOtherSliceColor = Color(0xFFB8B8B4); // 「其他」/兜底中性灰

class AppColors {
  static const bg = Color(0xFFFAFAF8);
  static const ink = Color(0xFF1A1A1A);
  static const secondary = Color(0xFF8A8A86);
  static const hairline = Color(0xFFECECE8);
  static const faint = Color(0xFFB8B8B4);
}

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
