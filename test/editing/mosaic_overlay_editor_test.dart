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
    await tester.tap(find.text('马赛克')); // 默认已高亮「模糊」，点另一段才是真实切换
    expect(state.selected!.effect, MosaicEffect.mosaic);
    await tester.tap(find.byKey(const ValueKey('strength-2')));
    expect(state.selected!.strength, 2);
  });

  testWidgets('无区域点「模糊」→ 轻提示（冒烟缺陷 5：原样静默无响应）', (tester) async {
    final state = MosaicEditorState(
        duration: const Duration(seconds: 10), srcW: 1280, srcH: 720);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Expanded(
            child: OverlayEditor(
              state: state,
                  immersive: false,
              onChanged: () {},
              onToggleImmersive: () {},
            ),
          ),
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
    await tester.pump();
    expect(find.text('请先添加打码区域'), findsOneWidget);
    expect(state.regions, isEmpty); // 无区域：不产生任何状态变化
    // T3：提示已改顶部 Overlay 轻提示，pump 掉 2s 自动消失 Timer（防 pending timer）
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('关键帧圆点点击 seek（评审 Important 修复回归）', (tester) async {
    final state = MosaicEditorState(
        duration: const Duration(seconds: 10), srcW: 1280, srcH: 720)
      ..addRegion()
      ..seekTo(const Duration(seconds: 5))
      ..addKeyframeAtPosition(); // 帧 = [0s, 5s]
    final seeks = <Duration>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MosaicTrackBar(
          duration: state.duration,
          position: state.position,
          frames: state.selected?.track.frames ?? const [],
          onSeek: seeks.add,
          onDeleteKeyframe: (_) {},
        ),
      ),
    ));
    // 圆点渲染（0s 定位在左边缘截断处，5s 在轨道中部）
    final dots = find.byIcon(Icons.circle);
    expect(dots, findsNWidgets(2));
    // 点击 5s 圆点 → onSeek 收到该帧时刻
    // （T2 后 MosaicTrackBar 独立挂载、无外层双击竞技场，tap 立即生效）
    await tester.tap(dots.last);
    expect(seeks, [const Duration(seconds: 5)]);
  });

  testWidgets('播放/暂停按钮（F5）：图标随 isPlaying 切换，点击回调', (tester) async {
    final state = MosaicEditorState(
        duration: const Duration(seconds: 10), srcW: 1280, srcH: 720);
    var toggles = 0;
    Widget build(bool playing) => MaterialApp(
          home: Scaffold(
            body: MosaicToolbar(
              state: state,
              hasSelection: false,
              onAddRegion: () {},
              onAddKeyframe: () {},
              onDeleteRegion: () {},
              isPlaying: playing,
              onTogglePlay: () => toggles++,
            ),
          ),
        );
    await tester.pumpWidget(build(false));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow));
    expect(toggles, 1);
    await tester.pumpWidget(build(true));
    expect(find.byIcon(Icons.pause), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause));
    expect(toggles, 2);
  });

  testWidgets('onAdjustEnd 接线（Task 5）：强度切换与关键帧长按删除后触发', (tester) async {
    final state = MosaicEditorState(
        duration: const Duration(seconds: 10), srcW: 1280, srcH: 720)
      ..addRegion()
      ..seekTo(const Duration(seconds: 5))
      ..addKeyframeAtPosition(); // 帧 = [0s, 5s]，长按删除才有 ≥2 帧前提
    var adjustEnds = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Expanded(
            child: OverlayEditor(
              state: state,
                  immersive: false,
              onChanged: () {},
              onToggleImmersive: () {},
              onAdjustEnd: () => adjustEnds++,
            ),
          ),
          MosaicToolbar(
            state: state,
            hasSelection: state.selected != null,
            onAddRegion: state.addRegion,
            onAddKeyframe: state.addKeyframeAtPosition,
            onDeleteRegion: () => state.removeRegion(state.selectedId!),
            onAdjustEnd: () => adjustEnds++,
          ),
        ]),
      ),
    ));
    // 强度切换 → onAdjustEnd（MosaicToolbar 无双击竞技场，tap 直接生效）
    await tester.tap(find.byKey(const ValueKey('strength-2')));
    expect(state.selected!.strength, 2);
    expect(adjustEnds, 1);
    // 效果切换 → onAdjustEnd（默认已高亮「模糊」，点另一段才是真实切换）
    await tester.tap(find.text('马赛克'));
    expect(state.selected!.effect, MosaicEffect.mosaic);
    expect(adjustEnds, 2);
    // （T2：关键帧圆点长按删除随轨道条移出画面，验证迁至独立用例）
  });

  testWidgets('关键帧圆点长按删除（T2：轨道条移出画面后回调语义不变）',
      (tester) async {
    final state = MosaicEditorState(
        duration: const Duration(seconds: 10), srcW: 1280, srcH: 720)
      ..addRegion()
      ..seekTo(const Duration(seconds: 5))
      ..addKeyframeAtPosition(); // 帧 = [0s, 5s]，长按删除才有 ≥2 帧前提
    final deletions = <Duration>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MosaicTrackBar(
          duration: state.duration,
          position: state.position,
          frames: state.selected?.track.frames ?? const [],
          onSeek: (_) {},
          onDeleteKeyframe: deletions.add,
        ),
      ),
    ));
    final dots = find.byIcon(Icons.circle);
    await tester.longPress(dots.last);
    expect(deletions, [const Duration(seconds: 5)]);
  });

  testWidgets('T2：进度条移出画面——OverlayEditor 不再渲染轨道条', (tester) async {
    final state = MosaicEditorState(
        duration: const Duration(seconds: 10), srcW: 1280, srcH: 720)
      ..addRegion();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OverlayEditor(
          state: state,
          immersive: false,
          onChanged: () {},
          onToggleImmersive: () {},
        ),
      ),
    ));
    expect(find.byType(MosaicTrackBar), findsNothing);
    expect(find.byIcon(Icons.circle), findsNothing); // 圆点也不在画面层
  });

  testWidgets('T4：边柄渲染——右缘/下缘单轴柄＋右下角柄保留', (tester) async {
    final state = MosaicEditorState(
        duration: const Duration(seconds: 10), srcW: 1280, srcH: 720)
      ..addRegion(); // addRegion 自动选中
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OverlayEditor(
          state: state,
          immersive: false,
          onChanged: () {},
          onToggleImmersive: () {},
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('mosaic-handle-right')), findsOneWidget);
    expect(find.byKey(const ValueKey('mosaic-handle-bottom')), findsOneWidget);
    expect(find.byIcon(Icons.control_camera), findsOneWidget); // 角柄保留
  });

  testWidgets('T2：showRegionMask=true 时两个区域框都有遮罩（含未选中）',
      (tester) async {
    final state = MosaicEditorState(
        duration: const Duration(seconds: 10), srcW: 1280, srcH: 720)
      ..addRegion()
      ..addRegion();
    // 两个默认框完全重叠（同中心同尺寸），先挪开选中的第二个
    state.moveSelectedBy(const Offset(0.35, 0));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OverlayEditor(
          state: state,
          immersive: false,
          onChanged: () {},
          onToggleImmersive: () {},
          showRegionMask: true,
        ),
      ),
    ));
    // 框体 Container 是 Positioned(key) → GestureDetector → Container 的
    // 唯一 Container（角柄/边柄是 Padding+Icon，不产生 Container）
    for (final key in const ['mosaic-box-0', 'mosaic-box-1']) {
      final box = tester.widget<Container>(find
          .descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(Container))
          .first);
      final deco = box.decoration as BoxDecoration;
      expect(deco.color, isNotNull, reason: key);
      expect(deco.color!.a, closeTo(OverlayEditor.maskAlpha, 0.001),
          reason: key);
    }
  });

  testWidgets('T2：默认不传 showRegionMask → 框体无遮罩（默认行为零影响）',
      (tester) async {
    final state = MosaicEditorState(
        duration: const Duration(seconds: 10), srcW: 1280, srcH: 720)
      ..addRegion();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OverlayEditor(
          state: state,
          immersive: false,
          onChanged: () {},
          onToggleImmersive: () {},
        ),
      ),
    ));
    final box = tester.widget<Container>(find
        .descendant(
            of: find.byKey(const ValueKey('mosaic-box-0')),
            matching: find.byType(Container))
        .first);
    final deco = box.decoration as BoxDecoration;
    expect(deco.color, isNull);
  });

  testWidgets('角柄 onPanStart 触发 onPause（P1-10：播放中拖角柄先暂停）',
      (tester) async {
    final state = MosaicEditorState(
        duration: const Duration(seconds: 10), srcW: 1280, srcH: 720)
      ..addRegion();
    var pauses = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OverlayEditor(
          state: state,
          immersive: false,
          onChanged: () {},
          onToggleImmersive: () {},
          onPause: () => pauses++,
        ),
      ),
    ));
    expect(find.byIcon(Icons.control_camera), findsOneWidget);
    // 分步移动：位移必须超过 kTouchSlop（18px），否则 pan 不进 arena
    final g = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.control_camera)));
    await g.moveBy(const Offset(20, 20));
    await tester.pump();
    await g.moveBy(const Offset(20, 20));
    await tester.pump();
    await g.up();
    // 外层双击窗口的计时器走完，避免 pending timer
    await tester.pump(const Duration(milliseconds: 400));
    expect(pauses, 1, reason: '角柄内层 pan 必须自己回调 onPause');
  });
}
