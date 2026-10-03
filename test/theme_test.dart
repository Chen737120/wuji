import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wuji/theme.dart';

void main() {
  test('preset hexes match spec', () {
    expect(AccentPreset.jade.value, 0xFF3FA26F);
    expect(AccentPreset.indigo.value, 0xFF3E5AA8);
    expect(AccentPreset.amber.value, 0xFFE8842E);
    expect(AccentPreset.mint.value, 0xFF6FCF9F);
  });
  test('legacy stored preset name falls back to jade', () async {
    SharedPreferences.setMockInitialValues({'accentPreset': 'matcha'});
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
    await c.setPreset(AccentPreset.indigo);
    expect(c.accentPreset, AccentPreset.indigo);
    expect(n, 1);
  });
  test('theme uses bg and accent', () {
    final t = AppTheme.light(AccentPreset.jade);
    expect(t.scaffoldBackgroundColor, AppColors.bg);
    expect(t.colorScheme.primary, const Color(0xFF3FA26F));
  });
}
