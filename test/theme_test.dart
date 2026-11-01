import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wuji/theme.dart';

void main() {
  test('preset hexes: jade kept + rainbow six (v1.5.11, 7 total)', () {
    expect(AccentPreset.jade.value, 0xFF3FA26F);
    expect(AccentPreset.red.value, 0xFFE5484D);
    expect(AccentPreset.orange.value, 0xFFF08C1E);
    expect(AccentPreset.yellow.value, 0xFFD9A514);
    expect(AccentPreset.cyan.value, 0xFF14A8B8);
    expect(AccentPreset.blue.value, 0xFF3B6FE0);
    expect(AccentPreset.purple.value, 0xFF8B5CF6);
    expect(AccentPreset.values, hasLength(7)); // 2026-10-07：草绿移除
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

  test('AppText type scale per task book T1 (spec §5)', () {
    expect(AppText.pageTitle.fontSize, 16);
    expect(AppText.pageTitle.fontWeight, FontWeight.w700);
    expect(AppText.pageTitle.letterSpacing, 3.0);
    expect(AppText.appBarTitle.fontSize, 15);
    expect(AppText.appBarTitle.letterSpacing, 2.0);
    expect(AppText.cardBody.fontSize, 13.5);
    expect(AppText.cardBody.height, 1.62);
    expect(AppText.entryTitle.fontSize, 18);
    expect(AppText.entryTitle.fontWeight, FontWeight.w800);
    expect(AppText.body.fontSize, 13);
    expect(AppText.body.height, 1.65);
    expect(AppText.meta.fontSize, 11);
    expect(AppText.caption.fontSize, 10);
    expect(AppText.fieldLabel.fontSize, 9);
    expect(AppText.statNumber.fontSize, 18);
    expect(AppText.statNumber.fontWeight, FontWeight.w700);
    expect(AppText.statNumber.fontFeatures,
        contains(const FontFeature.tabularFigures()));
  });

  test('spring constants: stiffness=(2π/response)², damping=2·ratio·√stiffness',
      () {
    // kSpringDefault: ratio 1.0 / response 0.35s
    expect(kSpringDefault.stiffness, closeTo(322.27, 0.01));
    expect(kSpringDefault.damping, closeTo(35.90, 0.01));
    // kSpringGesture: ratio 0.8 / response 0.3s
    expect(kSpringGesture.stiffness, closeTo(438.65, 0.01));
    expect(kSpringGesture.damping, closeTo(33.51, 0.01));
    // kSpringTransition: ratio 1.0 / response 0.4s
    expect(kSpringTransition.stiffness, closeTo(246.74, 0.01));
    expect(kSpringTransition.damping, closeTo(31.42, 0.01));
  });

  test('SpringHeightCurve：终场精确收敛 1、全程单调', () {
    const c = SpringHeightCurve();
    expect(c.transform(0), 0);
    expect(c.transform(1), 1); // 修前为 0.986399
    var last = 0.0;
    for (var i = 1; i <= 200; i++) {
      final v = c.transform(i / 200);
      expect(v, greaterThan(last));
      last = v;
    }
  });
}
