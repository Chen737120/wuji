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

  /// 播放中不允许落帧（UI 在播放时置 false，P1-10）：关键帧写入必须在
  /// 暂停态发生，否则时间轴每 tick 前移会写出大量垃圾帧且无撤销。
  bool editable = true;

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
  /// 播放中直接 no-op（[editable] 由 UI 维护），避免每帧写出垃圾关键帧。
  void _applyToSelected(CropBox Function(CropBox) transform) {
    if (!editable) return;
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
    if (!editable) return;
    final r = selected;
    if (r == null) return;
    r.track.upsert(position, r.track.boxAt(position));
  }

  /// 轨道长按删除（≤1 帧时不允许，保单框语义）。
  /// 只移除最近帧；其余帧时间/框不变（F6：不再 reset 重建，避免删 0s 帧
  /// 时把下一帧提前到 0s）。
  void removeKeyframeAt(Duration t) {
    selected?.track.remove(t);
  }
}
