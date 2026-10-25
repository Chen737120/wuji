import 'dart:ui';

import 'crop_box.dart';
import 'keyframes.dart';
import 'mosaic_region.dart';

/// 打码编辑器纯状态（spec §3.3）：UI 薄壳只做渲染与手势转发。
/// 坐标系：区域框归一化（相对源画面），与直拍 CropBox 同系。
class MosaicEditorState {
  MosaicEditorState({
    required this.duration,
    required this.srcW,
    required this.srcH,
    List<MosaicRegion> initialRegions = const [],
  }) {
    _regions.addAll(initialRegions);
  }

  final Duration duration;
  final int srcW;
  final int srcH;
  final List<MosaicRegion> _regions = [];

  /// 区域最小归一化边（spec §7：画面短边 4% 量级）。
  static const double minSide = 0.04;

  /// 面积下限：minSide 的归一化面积近似（归一化 w/h 基准不同，
  /// 取保守常量；spec §7）。
  double get _minArea => minSide * minSide;

  List<MosaicRegion> get regions => List.unmodifiable(_regions);
  String? selectedId;
  Duration position = Duration.zero;

  /// 手写查找：pubspec 未声明 collection，避免 depend_on_referenced_packages。
  MosaicRegion? get selected {
    for (final r in _regions) {
      if (r.id == selectedId) return r;
    }
    return null;
  }

  void seekTo(Duration t) => position = t;

  MosaicRegion addRegion() {
    if (_regions.length >= MosaicRegion.maxRegions) return _regions.last;
    // 中央默认框：像素短边 30% 的方形（自由比例的起点）
    final sidePx = (srcW <= srcH ? srcW : srcH) * 0.30;
    final box = CropBox(
      cx: 0.5,
      cy: 0.5,
      w: sidePx / srcW,
      h: sidePx / srcH,
    ).clamped(minArea: _minArea);
    final track = KeyframeTrack(duration: duration)..reset(box);
    final r = MosaicRegion(
      id: 'mr_${DateTime.now().microsecondsSinceEpoch}_${_regions.length}',
      track: track,
    );
    _regions.add(r);
    selectedId = r.id;
    return r;
  }

  bool removeRegion(String id) {
    final n = _regions.length;
    _regions.removeWhere((r) => r.id == id);
    if (selectedId == id) selectedId = null;
    return _regions.length < n;
  }

  void setEffect(MosaicEffect e) => selected?.effect = e;

  void setStrength(int s) {
    if (s >= 0 && s <= 2) selected?.strength = s;
  }

  /// 拖动/缩放统一落点：当前时刻 upsert（KeyframeTrack 同刻替换）。
  /// 播放须先暂停（UI 职责），否则时间流逝会产生多余关键帧。
  void _applyToSelected(CropBox Function(CropBox) transform) {
    final r = selected;
    if (r == null) return;
    final cur = r.track.boxAt(position);
    r.track.upsert(position, transform(cur));
  }

  /// 拖动：movedBy 内部即 clamp（含 minArea 透传，小框不被放大），一次到位。
  void moveSelectedBy(Offset deltaNorm) =>
      _applyToSelected((b) => b.movedBy(deltaNorm, minArea: _minArea));

  /// 缩放：打码框允许更深缩放（factor 0.1..4.0），
  /// 直拍调用点不传参保持默认 0.5..2.0 行为不变（Task 3 裁决 1）。
  void scaleSelectedBy(double factor) => _applyToSelected(
      (b) => b.scaledBy(factor,
          minArea: _minArea, minFactor: 0.1, maxFactor: 4.0));

  /// 「＋添加关键帧」：把当前插值框固化为关键帧（与直拍语义一致）。
  void addKeyframeAtPosition() {
    final r = selected;
    if (r == null) return;
    r.track.upsert(position, r.track.boxAt(position));
  }

  /// 轨道长按删除（≤1 帧时不允许，保单框语义）。
  /// KeyframeTrack 无 remove API：走 reset 重建（≤10 帧成本可忽略）。
  /// 局限：若删的是 0s 帧，次帧框会提前到 0s 占位（帧数不变，轨迹近似）。
  void removeKeyframeAt(Duration t) {
    final r = selected;
    if (r == null || r.track.frames.length <= 1) return;
    final frames = r.track.frames.toList();
    Keyframe? nearest;
    for (final f in frames) {
      if (nearest == null || (f.t - t).abs() < (nearest.t - t).abs()) {
        nearest = f;
      }
    }
    if (nearest != null && frames.length > 1) {
      final remain = frames..remove(nearest);
      final box = remain.first.box;
      r.track.reset(box);
      for (final f in remain.skip(1)) {
        r.track.upsert(f.t, f.box);
      }
    }
  }
}
