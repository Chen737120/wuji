import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wuji/theme.dart';

void main() {
  test('preset hexes: jade kept + rainbow seven (v1.5.9, 8 total)', () {
    expect(AccentPreset.jade.value, 0xFF3FA26F);
    expect(AccentPreset.red.value, 0xFFE5484D);
    expect(AccentPreset.orange.value, 0xFFF08C1E);
    expect(AccentPreset.yellow.value, 0xFFD9A514);
    expect(AccentPreset.green.value, 0xFF34B04A);
    expect(AccentPreset.cyan.value, 0xFF14A8B8);
    expect(AccentPreset.blue.value, 0xFF3B6FE0);
    expect(AccentPreset.purple.value, 0xFF8B5CF6);
    expect(AccentPreset.values, hasLength(8));
  });
  test('legacy stored preset name falls back to jade', () async {
    SharedPreferences.setMockInitialValues({'accentPreset': 'matcha'});
    final c = ThemeController();
    await c.load();
    expect(c.accentPreset, AccentPreset.jade);
  });
  test('removed legacy preset name also falls back to jade', () async {
    SharedPreferences.setMockInitialValues({'accentPreset': 'indigo'});
    final c = ThemeController();
    await c.load();
    expect(c.accentPreset, AccentPreset.jade);
  });
  testWidgets('controller switches and notifies', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = ThemeController();
    expect(c.accentPreset, AccentPreset.jade);
    var n = 0;
    c.addListener(() => n++);
    await c.setPreset(AccentPreset.blue);
    expect(c.accentPreset, AccentPreset.blue);
    expect(n, 1);
  });
  test('theme uses bg and accent', () {
    final t = AppTheme.light(AccentPreset.jade);
    expect(t.scaffoldBackgroundColor, AppColors.bg);
    expect(t.colorScheme.primary, const Color(0xFF3FA26F));
  });
  test('chart palette: 10 colors from reference app (v1.5.10)', () {
    expect(kRainbowPalette, hasLength(10));
    expect(kRainbowPalette.toSet(), hasLength(10));
    expect(kRainbowPalette.first, const Color(0xFFEC6FA5)); // 粉（第 1 色）
    expect(kRainbowPalette[9], const Color(0xFFA8D04A)); // 黄绿（第 10 色）
  });
}
