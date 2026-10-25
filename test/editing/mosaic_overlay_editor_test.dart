// 打码编辑器 UI widget 测试（Task 4 brief Step 1）：
// OverlayEditor / MosaicToolbar 无视频依赖，直接构造测渲染与状态写入。
// 注：MosaicEffect 需显式 import mosaic_region.dart（state 未 re-export）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/mosaic_editor_state.dart';
import 'package:wuji/editing/mosaic_region.dart';
import 'package:wuji/ui/mosaic/mosaic_editor_page.dart';

void main() {
  testWidgets('OverlayEditor：区域框渲染＋点选切换选中', (tester) async {
    final state = MosaicEditorState(
        duration: const Duration(seconds: 10), srcW: 1280, srcH: 720)
      ..addRegion()
      ..addRegion();
    // 两个默认框完全重叠（同中心同尺寸），Stack 命中只取最上层——
    // 先把选中的第二个框挪开，才能点到 box-0（测试几何修正，意图不变）
    state.moveSelectedBy(const Offset(0.35, 0));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OverlayEditor(
          state: state,
          canvasSize: const Size(320, 180),
          immersive: false,
          onChanged: () {},
          onToggleImmersive: () {},
        ),
      ),
    ));
    // 两个区域框渲染（以 key 命中）
    expect(find.byKey(const ValueKey('mosaic-box-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('mosaic-box-1')), findsOneWidget);
    // 点击第一个框 → 选中切换
    await tester.tap(find.byKey(const ValueKey('mosaic-box-0')));
    // 外层 onDoubleTap（双击复位查看）会扣住手势竞技场，单击在 ~300ms
    // 双击窗口过后才生效（fancam 同款手势组合的固有延迟），推进假时钟
    await tester.pump(const Duration(milliseconds: 400));
    expect(state.selectedId, state.regions[0].id);
  });

  testWidgets('效果/强度控件写入 state', (tester) async {
    final state = MosaicEditorState(
        duration: const Duration(seconds: 10), srcW: 1280, srcH: 720)
      ..addRegion();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Expanded(
            child: OverlayEditor(
              state: state,
              canvasSize: const Size(320, 180),
              immersive: false,
              onChanged: () {},
              onToggleImmersive: () {},
            ),
          ),
          // 底部条独立成组件以便单测：MosaicToolbar
          MosaicToolbar(
            state: state,
            hasSelection: state.selected != null,
            onAddRegion: state.addRegion,
            onAddKeyframe: state.addKeyframeAtPosition,
            onDeleteRegion: () => state.removeRegion(state.selectedId!),
          ),
        ]),
      ),
    ));
    await tester.tap(find.text('模糊'));
    expect(state.selected!.effect, MosaicEffect.blur);
    await tester.tap(find.byKey(const ValueKey('strength-2')));
    expect(state.selected!.strength, 2);
  });
}
