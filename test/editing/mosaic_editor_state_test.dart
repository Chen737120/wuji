import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/keyframes.dart';
import 'package:wuji/editing/mosaic_editor_state.dart';
import 'package:wuji/editing/mosaic_region.dart';

MosaicEditorState state() =>
    MosaicEditorState(duration: const Duration(seconds: 10), srcW: 1280, srcH: 720);

void main() {
  test('addRegion：中央默认框（像素短边 30% 方形）、自动选中', () {
    final s = state()..addRegion();
    expect(s.regions, hasLength(1));
    expect(s.selectedId, s.regions.first.id);
    // 短边 720×0.3=216px → 归一化 w=216/1280≈0.169, h=216/720=0.3
    final b = s.selected!.track.boxAt(Duration.zero);
    expect(b.w, closeTo(0.169, 0.01));
    expect(b.h, closeTo(0.30, 0.01));
  });

  test('区域上限 5 个：第 6 个被拒绝', () {
    final s = state();
    for (var i = 0; i < MosaicRegion.maxRegions; i++) {
      s.addRegion();
    }
    final before = s.regions.length;
    s.addRegion();
    expect(s.regions.length, before); // 仍 5
  });

  test('拖动：单框模式直接改框并 clamp（Review Focus #5 小框不被放大）', () {
    final s = state()..addRegion();
    // 拖到右下并缩小框到 0.05（> minSide 面积下限 0.0016）
    s.scaleSelectedBy(0.3); // 0.169*0.3≈0.051
    s.moveSelectedBy(const Offset(0.3, 0.2));
    final b = s.selected!.track.boxAt(Duration.zero);
    expect(b.w * 1280, closeTo(65, 6)); // 0.051*1280
    expect(b.cx + b.w / 2, lessThanOrEqualTo(1.0)); // clamp 在画面内
  });

  test('多帧模式：拖动=当前时刻 upsert（KeyframeTrack 同刻替换语义）', () {
    final s = state()..addRegion();
    s.seekTo(const Duration(seconds: 4));
    s.addKeyframeAtPosition(); // 4s 处打点
    s.seekTo(const Duration(seconds: 6));
    s.moveSelectedBy(const Offset(0.1, 0));
    final frames = s.selected!.track.frames;
    expect(frames.where((f) => f.t == const Duration(seconds: 6)), hasLength(1));
  });

  test('删除区域清空选中；效果/强度写入选中区域', () {
    final s = state()..addRegion();
    final id = s.selectedId!;
    s.setEffect(MosaicEffect.blur);
    s.setStrength(2);
    expect(s.selected!.effect, MosaicEffect.blur);
    expect(s.selected!.strength, 2);
    expect(s.removeRegion(id), isTrue);
    expect(s.selectedId, isNull);
    expect(s.removeRegion('nonexistent'), isFalse);
  });

  test('删首个关键帧：只移除该帧，后续帧不被移到 0s（F6）', () {
    final s = state()..addRegion();
    s.seekTo(const Duration(seconds: 5));
    s.moveSelectedBy(const Offset(0.1, 0)); // 5s 处落一帧（与 0s 帧框不同）
    final track = s.selected!.track;
    expect(track.frames.map((f) => f.t).toList(),
        [Duration.zero, const Duration(seconds: 5)]);
    final second = track.frames[1];
    s.removeKeyframeAt(Duration.zero);
    expect(track.frames, hasLength(1));
    expect(track.frames.single.t, const Duration(seconds: 5));
    expect(track.frames.single.box.cx, second.box.cx);
  });

  test('关键帧轨道：打点→长按删除→剩 1 帧即单框；上限 10', () {
    final s = state()..addRegion();
    for (var i = 0; i < KeyframeTrack.maxFrames; i++) {
      s.seekTo(Duration(seconds: i));
      s.addKeyframeAtPosition();
    }
    expect(s.selected!.track.frames, hasLength(10));
    s.seekTo(const Duration(seconds: 9));
    s.addKeyframeAtPosition(); // 超限静默不增（upsert 返回 false）
    expect(s.selected!.track.frames, hasLength(10));
    s.removeKeyframeAt(const Duration(seconds: 5));
    expect(s.selected!.track.frames, hasLength(9));
  });

  group('editable 不变量（P1-10：播放中禁止落帧）', () {
    test('默认可编辑', () {
      expect(state().editable, isTrue);
    });

    test('editable=false 时拖动/缩放/打点全部 no-op', () {
      final s = state()..addRegion();
      final beforeFrames = s.selected!.track.frames.length;
      final beforeBox = s.selected!.track.boxAt(Duration.zero);
      s.editable = false;
      s.seekTo(const Duration(seconds: 3));

      s.scaleSelectedBy(1.2);
      s.moveSelectedBy(const Offset(0.2, 0.2));
      s.addKeyframeAtPosition();

      expect(s.selected!.track.frames, hasLength(beforeFrames));
      final afterBox = s.selected!.track.boxAt(Duration.zero);
      expect(afterBox.cx, beforeBox.cx);
      expect(afterBox.cy, beforeBox.cy);
      expect(afterBox.w, beforeBox.w);
      expect(afterBox.h, beforeBox.h);
    });

    test('editable=true 时同样调用按原逻辑生效（回归）', () {
      final s = state()..addRegion();
      s.seekTo(const Duration(seconds: 3));
      s.moveSelectedBy(const Offset(0.1, 0));
      s.addKeyframeAtPosition();
      expect(s.selected!.track.frames, hasLength(2));
      expect(s.selected!.track.frames.last.t, const Duration(seconds: 3));
    });
  });
}
