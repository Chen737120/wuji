import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全 App 唯一的彩色：点缀色预设（规格 §9/§3.6）。
enum AccentPreset {
  jade(0xFF3FA26F, '翠芽'),
  matcha(0xFF52B788, '抹茶'),
  mint(0xFF6FCF9F, '薄荷'),
  pine(0xFF2F5D50, '松绿');

  const AccentPreset(this.value, this.label);
  final int value;
  final String label;

  Color get color => Color(value);
}

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
