import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../editing/keyframes.dart';
import '../../editing/mosaic_editor_state.dart';
import '../../editing/mosaic_region.dart';
import '../../editing/mosaic_snapshot.dart';
import '../../editing/mosaic_view.dart';
import '../../editing/trim_timeline.dart';
import '../../theme.dart';
import '../widgets/top_tip.dart';

/// 打码编辑器（spec §3.3）：视频最大化＋区域框叠加＋底部工具条。
/// embedded=true（直拍内嵌）→ 底部主按钮「完成」pop 回区域列表；
/// embedded=false（独立入口）→ 「导出」，由宿主回调 onExport。
class MosaicEditorPage extends StatefulWidget {
  const MosaicEditorPage({
    super.key,
    required this.srcPath,
    required this.srcW,
    required this.srcH,
    required this.durationMs,
    this.trimStart = Duration.zero,
    this.initialRegions = const [],
    required this.embedded,
    this.onExport,
  });

  final String srcPath;

  /// 源视频尺寸（video_player 已应用 rotation 的像素域，与导出滤镜一致）。
  final int srcW;
  final int srcH;
  final int durationMs;

  /// 修剪起点（直拍内嵌传入；独立入口默认 0）。播放器/快照的源视频 seek
  /// 须加此偏移，编辑器内部（区域关键帧/轨道/快照滤镜）一律用 track 时间
  /// （0=trimStart），见 [trackPosition]/[sourcePosition]。
  final Duration trimStart;
  final List<MosaicRegion> initialRegions;
  final bool embedded;
  final void Function(List<MosaicRegion> regions)? onExport;

  @override
  State<MosaicEditorPage> createState() => _MosaicEditorPageState();
}

class _MosaicEditorPageState extends State<MosaicEditorPage> {
  late final MosaicEditorState _state;
  late final VideoPlayerController _player;
  double _viewScale = 1;
  Offset _viewOffset = Offset.zero;
  bool _immersive = false;
  String? _snapshotPath; // 当前 position 的帧快照（Task 5 生成）

  /// [_snapshotPath] 对应的 track 时刻（2026-10-29 预览 T1）：供时刻匹配
  /// 判定；与 path 同生命周期（path 置 null 处不必同步清，判定已为 false）。
  Duration? _snapshotAt;
  bool _playing = false;
  // 快照重生成 debounce（spec §6）：300ms 静默后抽帧；busy 期间新请求
  // 只更新时间戳与提示策略，由进行中的循环等待后拿最新状态补拍。
  DateTime _lastSnapshotRequest =
      DateTime.now().subtract(const Duration(days: 1));
  bool _snapshotBusy = false;

  /// 最近一次请求失败时是否提示（seek 高频失败降噪，裁决 5）。
  bool _snapshotAnnounce = true;

  /// 源视频总时长（快照片尾钳制上限，2026-10-28 反馈 #6）：兜底用元数据
  /// 口径，播放器初始化后取 ExoPlayer 真实时长。**必须 late**——State 字段
  /// 初始化器执行时 widget 尚未赋值，惰性求值到首次使用才安全。
  late Duration _srcDuration = widget.trimStart + _state.duration;

  /// 当前是否有一张"对应当前时刻"的快照（T1 时刻匹配，T2 遮罩共用）。
  bool get _hasFreshSnapshot => snapshotMatchesPosition(
      path: _snapshotPath,
      snapshotAt: _snapshotAt,
      position: _state.position);

  @override
  void initState() {
    super.initState();
    _state = MosaicEditorState(
      duration: Duration(milliseconds: widget.durationMs),
      srcW: widget.srcW,
      srcH: widget.srcH,
      initialRegions: widget.initialRegions,
    );
    _player = VideoPlayerController.file(File(widget.srcPath));
    _player.initialize().then((_) async {
      if (!mounted) return;
      final d = _player.value.duration; // ExoPlayer 真实时长，比元数据口径可靠
      if (d > Duration.zero) _srcDuration = d;
      // 直拍内嵌：首帧定位到修剪起点（track 0 = 源 trimStart，F1）
      if (widget.trimStart > Duration.zero) {
        await _player.seekTo(widget.trimStart);
      }
      if (mounted) setState(() {});
    });
    _player.addListener(_onPlayerTick);
  }

  /// 播放器位置 → track 时间（0=trimStart，钳进修剪区间）。播放同步、
  /// 快照、打点都读这个口径。
  Duration get _trackPosition => trackPosition(
        playerPosition: _player.value.position,
        trimStart: widget.trimStart,
        duration: _state.duration,
      );

  /// 播放中随帧同步 state.position（否则叠加框/轨道不动）并刷新。
  /// 拖动/关键帧落点同样读 state.position，两处口径一致。
  void _onPlayerTick() {
    if (!mounted) return; // dispose 期间控制器仍可能推最后一轮事件
    final v = _player.value;
    final playing = v.isPlaying;
    if (playing != _playing) {
      setState(() {
        _playing = playing;
        // 播放中禁止落帧（P1-10）：状态层不变量，UI 同步切换
        _state.editable = !playing;
      });
      // 暂停后恢复 WYSIWYG 快照（播放期间快照隐藏，视频帧即画面）
      if (!playing) _refreshSnapshot();
    }
    if (!playing) return;
    // 播到修剪区间末端停住（F5；track 时间口径见 F1）
    final end = widget.trimStart + _state.duration;
    if (v.position >= end) {
      _player.pause();
      _player.seekTo(end);
      setState(() => _state.seekTo(_state.duration));
      return;
    }
    setState(() => _state.seekTo(_trackPosition));
  }

  /// 播放/暂停（F5）：暂停中从当前位置继续；在修剪起点前或末端则先回起点。
  Future<void> _togglePlay() async {
    if (!_player.value.isInitialized) return;
    if (_player.value.isPlaying) {
      await _player.pause();
      return;
    }
    final end = widget.trimStart + _state.duration;
    if (_player.value.position < widget.trimStart ||
        _player.value.position >= end) {
      await _player.seekTo(widget.trimStart);
      if (!mounted) return;
      setState(() {
        _state.seekTo(Duration.zero);
        _snapshotPath = null;
      });
    }
    await _player.play();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    dismissTopTip(); // 顶部轻提示随页面移除（防跨页残留）
    deleteMosaicSnapshotDir(); // 快照临时目录整删（fire-and-forget，内部吞异常）
    _player.dispose();
    super.dispose();
  }

  /// 快照重生成（spec §6）：调整结束/seek 停止后 300ms 静默抽帧跑真实打码链。
  /// 播放中不刷新（视频帧即真实画面）；失败降级为 null＋可选轻提示。
  Future<void> _refreshSnapshot({bool announceFailure = true}) async {
    if (!snapshotStillValid(regionCount: _state.regions.length)) {
      // 删到 0 个区域：旧快照带马赛克，必须立刻失效（P2-2）
      if (_snapshotPath != null && mounted) {
        setState(() => _snapshotPath = null);
      }
      return;
    }
    if (_playing) return;
    _lastSnapshotRequest = DateTime.now();
    _snapshotAnnounce = announceFailure;
    if (_snapshotBusy) return;
    _snapshotBusy = true;
    var stale = false;
    try {
      while (true) {
        final idle = DateTime.now().difference(_lastSnapshotRequest);
        if (idle >= const Duration(milliseconds: 300)) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }
      // dispose 恰逢等待中：不起 capture（否则会重建 dispose 刚删掉的快照目录）
      if (!mounted) return;
      final capturedAt = DateTime.now();
      final atPosition = _state.position; // 本次快照对应的 track 时刻
      final path = await captureMosaicSnapshot(
        srcPath: widget.srcPath,
        regions: _state.regions,
        at: atPosition,
        srcW: widget.srcW,
        srcH: widget.srcH,
        sourceOffset: widget.trimStart,
        sourceDuration: _srcDuration, // 片尾钳制＋失败重试（反馈 #6）
      );
      // stale 判断前移到写入前（评审 Important #1）：capture 期间又来了
      // 新请求（典型：seek 已清空 _snapshotPath），旧时刻帧不得回填——
      // 跳过本次写入与提示，交给 tail 补拍最新状态。
      stale = _lastSnapshotRequest.isAfter(capturedAt);
      if (mounted && !stale && !_playing) {
        final old = _snapshotPath;
        setState(() {
          _snapshotPath = path;
          _snapshotAt = atPosition; // 与 path 同步写入，供时刻匹配判定
        });
        // 写新删旧（P2-3）：快照每次唯一命名，只增不删会持续吃磁盘
        if (old != null && old != path) {
          try {
            File(old).deleteSync();
          } catch (_) {}
        }
        if (path == null && _snapshotAnnounce) {
          showTopTip(context, '快照生成失败，可重试');
        }
      }
    } finally {
      _snapshotBusy = false;
    }
    // tail 补拍须过 mounted 门闩（评审 Minor #2）：dispose 后递归会重建
    // 快照目录留下孤儿 jpg
    if (mounted && stale) {
      await _refreshSnapshot(announceFailure: _snapshotAnnounce);
    }
  }

  /// 「区域」：到 5 个上限时提示且不新增（spec §7；addRegion 底层
  /// 超限会静默返回末位区域，UI 侧前置拦截）。
  void _addRegion() {
    if (_state.regions.length >= MosaicRegion.maxRegions) {
      showTopTip(context, '最多 5 个区域');
      return;
    }
    setState(_state.addRegion);
    _refreshSnapshot(); // 新区域进滤镜图，快照须重拍
  }

  /// 「关键帧」：当前时刻 upsert（同刻替换不算新增，不受上限拦）。
  /// addKeyframeAtPosition 无返回值，先按 KeyframeTrack.maxFrames 前置判断。
  void _addKeyframe() {
    final sel = _state.selected;
    if (sel == null) return;
    final track = sel.track;
    final replaceSame = track.frames.any((f) => f.t == _state.position);
    if (track.frames.length >= KeyframeTrack.maxFrames && !replaceSame) {
      showTopTip(context, '关键帧已达 10 个上限');
      return;
    }
    setState(_state.addKeyframeAtPosition);
    _refreshSnapshot(); // 关键帧增删（裁决 3）
  }

  /// 「删除」：移除选中区域并重拍快照（滤镜图变了）。
  void _deleteSelectedRegion() {
    setState(() {
      if (_state.selectedId != null) {
        _state.removeRegion(_state.selectedId!);
      }
    });
    _refreshSnapshot();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        SafeArea(
          child: Column(children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: widget.srcW / widget.srcH,
                  child: Stack(fit: StackFit.expand, children: [
                    // 视频/快照共用查看变换（中心锚点，与 OverlayEditor 的
                    // 框公式同源——F2：修复前框缩放而画面不动，框与画面脱节）
                    Transform.translate(
                      offset: _viewOffset,
                      child: Transform.scale(
                        scale: _viewScale,
                        child: Stack(fit: StackFit.expand, children: [
                          if (_player.value.isInitialized)
                            VideoPlayer(_player)
                          else
                            const ColoredBox(color: Colors.black12),
                          if (!_playing && _hasFreshSnapshot)
                            Image.file(File(_snapshotPath!),
                                fit: BoxFit.fill,
                                // 解码上限：编辑区宽度量级足够（P2-3）
                                cacheWidth: 1080),
                        ]),
                      ),
                    ),
                    OverlayEditor(
                      state: _state,
                      immersive: _immersive,
                      onChanged: () => setState(() {}),
                      // 拖框/角柄缩放结束、关键帧删除后重拍快照（裁决 3）
                      onAdjustEnd: () => _refreshSnapshot(),
                      onToggleImmersive: () =>
                          setState(() => _immersive = !_immersive),
                      // 预览遮罩（预览 T2）：播放中/快照未就绪时遮罩表达
                      // 打码范围；暂停且快照匹配（_hasFreshSnapshot）露出真实效果
                      showRegionMask: _playing || !_hasFreshSnapshot,
                      viewScale: _viewScale,
                      viewOffset: _viewOffset,
                      onViewTransformed: (scale, offset) => setState(() {
                        _viewScale = scale;
                        _viewOffset = offset;
                      }),
                      onPause: () => _player.pause(),
                    ),
                  ]),
                ),
              ),
            ),
            // T2（反馈 #4）：轨道条从画面内移到视频下方、工具条上方；
            // 原画布内 bottomCenter 挂载（OverlayEditor）已删除
            if (!_immersive && _state.regions.isNotEmpty)
              MosaicTrackBar(
                duration: _state.duration,
                position: _state.position,
                frames: _state.selected?.track.frames ?? const [],
                onSeek: (t) {
                  setState(() {
                    _state.seekTo(t);
                    // 轨道时间是 track 口径，播放器要源时间（F1）
                    _player.seekTo(sourcePosition(t, widget.trimStart));
                    _snapshotPath = null; // 位置变了，快照失效待重生成
                  });
                  // seek 触发的刷新失败不提示（高频降噪，裁决 5）
                  _refreshSnapshot(announceFailure: false);
                },
                onDeleteKeyframe: (t) {
                  setState(() => _state.removeKeyframeAt(t));
                  _refreshSnapshot(); // 关键帧删除后重拍快照
                },
              ),
            if (!_immersive)
              MosaicToolbar(
                state: _state,
                hasSelection: _state.selected != null,
                onAddRegion: _addRegion,
                onAddKeyframe: _addKeyframe,
                onDeleteRegion: _deleteSelectedRegion,
                // 效果/强度切换后重拍快照（工具条回调由页面组合，裁决 3）
                onAdjustEnd: () => _refreshSnapshot(),
                isPlaying: _playing,
                onTogglePlay: _togglePlay,
                onPrimary: () {
                  if (widget.embedded) {
                    Navigator.pop(context, _state.regions);
                  } else {
                    widget.onExport?.call(_state.regions);
                  }
                },
                primaryLabel: widget.embedded ? '完成' : '导出',
              ),
          ]),
        ),
        // 返回（fancam 同款顶部返回；brief 未画，独立入口需要出口）
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              // 注：此 pop 不带回传（null），与「完成」pop(regions) 返回类型
              // 不一致——宿主须容错 null=取消/放弃（Task 7 直拍接线时处理）。
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ]),
    );
  }
}

/// 区域框叠加层＋手势（无播放器依赖，可 widget 测试）。
/// 手势分工照抄 fancam_page：单指拖框体=移动；拖角柄（右下）=缩放；
/// 双指=查看缩放/平移（仅查看 1×~4×）；双击=复位查看；点空白=取消选中/切沉浸。
class OverlayEditor extends StatefulWidget {
  const OverlayEditor({
    super.key,
    required this.state,
    required this.immersive,
    required this.onChanged,
    required this.onToggleImmersive,
    this.onAdjustEnd,
    this.showRegionMask = false,
    this.viewScale = 1,
    this.viewOffset = Offset.zero,
    this.onViewTransformed,
    this.onPause,
  });

  final MosaicEditorState state;
  final bool immersive;
  final VoidCallback onChanged;
  final VoidCallback onToggleImmersive;

  /// 播放中/快照未就绪时用框内遮罩表达打码范围（2026-10-29 预览 T2）；
  /// 暂停且快照匹配时关掉，露出真实效果。默认 false → 现有测试构造零影响。
  final bool showRegionMask;

  /// 框内遮罩透明度（实现与测试断言共用同一真源）。
  /// 真机观感校准（2026-10-31）：0.22 在浅色场景偏淡，按任务书授权
  /// 范围（0.18~0.30）调至 0.28。
  static const double maskAlpha = 0.28;

  /// 区域调整结束（拖框/角柄缩放 onPanEnd、关键帧删除）——宿主用于重拍快照。
  final VoidCallback? onAdjustEnd;
  final double viewScale;
  final Offset viewOffset;
  final void Function(double scale, Offset offset)? onViewTransformed;
  final void Function()? onPause;

  @override
  State<OverlayEditor> createState() => _OverlayEditorState();
}

class _OverlayEditorState extends State<OverlayEditor> {
  /// 捏合起始时的查看缩放。onScaleUpdate 的 d.scale 自手势起累计（1.0 起），
  /// 若直接 viewScale * d.scale，中途 onViewTransformed 更新 viewScale 会
  /// 复利放大（fancam_page _panStart 同款问题域），须记手势起点基准。
  double? _scaleBase;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;

      Widget boxLayer(int i) {
        final r = state.regions[i];
        final b = r.track.boxAt(state.position);
        final selected = r.id == state.selectedId;
        // 归一化框 → 布局像素（中心锚点缩放＋平移，与视频层的 Transform 同源）
        final rect = mosaicBoxRect(
            b, Size(w, h), widget.viewScale, widget.viewOffset);
        return Positioned.fromRect(
          key: ValueKey('mosaic-box-$i'),
          rect: rect,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              state.selectedId = r.id;
              widget.onChanged();
            },
            onPanStart: (_) => widget.onPause?.call(),
            onPanUpdate: (d) {
              // 拖框体：布局像素位移 → 归一化位移（除以 viewScale）
              state.moveSelectedBy(Offset(
                d.delta.dx / (w * widget.viewScale),
                d.delta.dy / (h * widget.viewScale),
              ));
              widget.onChanged();
            },
            onPanEnd: (_) => widget.onAdjustEnd?.call(),
            child: Container(
              decoration: BoxDecoration(
                // 预览遮罩（2026-10-29 预览 T2）：仅在"看不到真实效果"时
                // 表达打码范围（选中/未选中框一致，不影响任何手势）
                color: widget.showRegionMask
                    ? Colors.white.withValues(alpha: OverlayEditor.maskAlpha)
                    : null,
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white,
                  width: selected ? 2 : 1,
                ),
              ),
              // 手柄（选中时）：右下角柄=等比缩放（fancam 角柄模式，保留）；
              // T4（2026-10-28 反馈 #3）：右缘/下缘边柄=单轴调宽/高（自由比例）
              child: selected
                  ? Stack(children: [
                      Align(
                        alignment: Alignment.bottomRight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          // 角柄内层 pan 会赢下手势竞技场，父框 onPanStart 不会触发，
                          // 必须自己暂停（P1-10：否则播放中拖角柄按帧写关键帧）
                          onPanStart: (_) => widget.onPause?.call(),
                          onPanUpdate: (d) {
                            final f = 1 +
                                (d.delta.dx + d.delta.dy) /
                                    ((w + h) * widget.viewScale) *
                                    2;
                            state.scaleSelectedBy(f);
                            widget.onChanged();
                          },
                          onPanEnd: (_) => widget.onAdjustEnd?.call(),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.control_camera,
                                size: 20, color: Colors.white),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          key: const ValueKey('mosaic-handle-right'),
                          onPanStart: (_) => widget.onPause?.call(),
                          onPanUpdate: (d) {
                            state.resizeSelectedByAxis(
                                Offset(d.delta.dx / (w * widget.viewScale), 0));
                            widget.onChanged();
                          },
                          onPanEnd: (_) => widget.onAdjustEnd?.call(),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.swap_horiz,
                                size: 20, color: Colors.white),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          key: const ValueKey('mosaic-handle-bottom'),
                          onPanStart: (_) => widget.onPause?.call(),
                          onPanUpdate: (d) {
                            state.resizeSelectedByAxis(
                                Offset(0, d.delta.dy / (h * widget.viewScale)));
                            widget.onChanged();
                          },
                          onPanEnd: (_) => widget.onAdjustEnd?.call(),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.swap_vert,
                                size: 20, color: Colors.white),
                          ),
                        ),
                      ),
                    ])
                  : null,
            ),
          ),
        );
      }

      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        // 双指查看缩放/平移（fancam 模式：仅 pointerCount>=2 参与缩放判定）
        onScaleStart: (_) => _scaleBase = widget.viewScale,
        onScaleUpdate: (d) {
          if (d.pointerCount < 2 || widget.onViewTransformed == null) return;
          final scale =
              ((_scaleBase ?? widget.viewScale) * d.scale).clamp(1.0, 4.0);
          widget.onViewTransformed!(
            scale,
            // 中心锚点余量：画面未溢出的轴拖不走（与视频 Transform 同口径）
            clampMosaicViewOffset(
                widget.viewOffset + d.focalPointDelta, scale, Size(w, h)),
          );
        },
        onScaleEnd: (_) => _scaleBase = null,
        // 双击复位查看（fancam 同款；须注册 onDoubleTap 回调本身才生效）
        onDoubleTap: () => widget.onViewTransformed?.call(1, Offset.zero),
        onTap: () {
          if (state.selectedId != null) {
            state.selectedId = null;
            widget.onChanged();
          } else {
            widget.onToggleImmersive();
          }
        },
        // T2（2026-10-28 反馈 #4）：轨道条移出画面——挂载点迁到页面
        // Column（视频区与工具条之间），本层只保留区域框叠加
        child: Stack(
          children: [
            for (var i = 0; i < state.regions.length; i++) boxLayer(i),
          ],
        ),
      );
    });
  }
}

/// 底部工具条（效果/强度/区域管理/主按钮）。
class MosaicToolbar extends StatelessWidget {
  const MosaicToolbar({
    super.key,
    required this.state,
    required this.hasSelection,
    required this.onAddRegion,
    required this.onAddKeyframe,
    required this.onDeleteRegion,
    this.onAdjustEnd,
    this.onPrimary,
    this.primaryLabel,
    this.isPlaying = false,
    this.onTogglePlay,
  });

  final MosaicEditorState state;
  final bool hasSelection;
  final VoidCallback onAddRegion;
  final VoidCallback onAddKeyframe;
  final VoidCallback onDeleteRegion;

  /// 播放/暂停（F5）：移动目标靠关键帧跟随时，可边播边找落点。
  final bool isPlaying;
  final VoidCallback? onTogglePlay;

  /// 效果/强度切换后回调——宿主用于重拍快照（本组件不依赖快照实现）。
  final VoidCallback? onAdjustEnd;
  final VoidCallback? onPrimary;
  final String? primaryLabel;

  @override
  Widget build(BuildContext context) {
    final sel = state.selected;
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            // 无区域时点击任一段（含已选中的）都提示引导——默认 blur 后
            // 点已选中的「模糊」SegmentedButton 不回调，零反馈像坏了
            // （冒烟缺陷 5 的 blur 侧镜像，T1 配套修复）；有区域正常切换
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: hasSelection
                  ? null
                  : () => showTopTip(context, '请先添加打码区域'),
              child: IgnorePointer(
                ignoring: !hasSelection,
                child: SegmentedButton<MosaicEffect>(
                  segments: const [
                    ButtonSegment(value: MosaicEffect.mosaic, label: Text('马赛克')),
                    ButtonSegment(value: MosaicEffect.blur, label: Text('模糊')),
                  ],
                  selected: {sel?.effect ?? MosaicEffect.blur},
                  onSelectionChanged: (s) {
                    state.setEffect(s.first);
                    onAdjustEnd?.call();
                  },
                ),
              ),
            ),
          ),
          // 强度三档：细/中/粗
          for (var i = 0; i < 3; i++)
            IconButton(
              key: ValueKey('strength-$i'),
              onPressed: hasSelection
                  ? () {
                      state.setStrength(i);
                      onAdjustEnd?.call();
                    }
                  : null,
              isSelected: sel?.strength == i,
              icon: Icon(const [Icons.grain, Icons.circle, Icons.blur_on][i],
                  size: 18),
              tooltip: const ['细', '中', '粗'][i],
            ),
        ]),
        Row(children: [
          IconButton(
            key: const ValueKey('mosaic-play-toggle'),
            onPressed: onTogglePlay,
            icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, size: 20),
            tooltip: isPlaying ? '暂停' : '播放',
          ),
          TextButton.icon(
              onPressed: onAddRegion,
              icon: const Icon(Icons.add),
              label: const Text('区域')),
          TextButton.icon(
              onPressed: hasSelection ? onAddKeyframe : null,
              icon: const Icon(Icons.push_pin),
              label: const Text('关键帧')),
          TextButton.icon(
              onPressed: hasSelection ? onDeleteRegion : null,
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除')),
          const Spacer(),
          // F3：竖屏 400 逻辑宽本行内容 384.9 超 376 溢出 8.9px——收窄主按钮
          // 水平 padding 24→16（任务书方案②；方案① compact 在 M3 下对按钮
          // 宽度零效果已实测排除）。测试约束 400×890 先复现 8.9 再转绿。
          FilledButton(
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
            onPressed: onPrimary,
            child: Text(primaryLabel ?? '完成'),
          ),
        ]),
      ]),
    );
  }
}

/// 简化轨道：进度条＋关键帧圆点（点击 seek、长按删除）。选中区域无轨道时隐藏圆点。
/// T2（2026-10-28 反馈 #4）起为公共组件：页面在视频下方挂载，widget 测试直接构造。
class MosaicTrackBar extends StatelessWidget {
  const MosaicTrackBar({super.key,
    required this.duration,
    required this.position,
    required this.frames,
    required this.onSeek,
    required this.onDeleteKeyframe,
  });

  final Duration duration;
  final Duration position;
  final List<Keyframe> frames;
  final void Function(Duration t) onSeek;
  final void Function(Duration t) onDeleteKeyframe;

  @override
  Widget build(BuildContext context) {
    final durMs = duration.inMilliseconds;
    double ratioOf(Duration t) => durMs == 0 ? 0.0 : t.inMilliseconds / durMs;
    final ratio = ratioOf(position).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        return SizedBox(
          height: 28,
          child: Stack(alignment: Alignment.centerLeft, children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => onSeek(duration * (d.localPosition.dx / w)),
              child: SizedBox(
                height: 28,
                width: w,
                child: Center(
                  child: LinearProgressIndicator(value: ratio, minHeight: 3),
                ),
              ),
            ),
            // 关键帧圆点：按 t/duration 比例定位；命中区放大到 24dp 便于长按
            for (final f in frames)
              Positioned(
                left: ratioOf(f.t).clamp(0.0, 1.0) * w - 12,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // 点击 seek 到该帧（opaque 会拦住下层进度条的 onTapUp，
                  // 须在圆点自身注册 onTap，否则点击无响应）
                  onTap: () => onSeek(f.t),
                  onLongPress: () => onDeleteKeyframe(f.t),
                  child: const SizedBox(
                    width: 24,
                    height: 28,
                    child: Center(
                        child: Icon(Icons.circle, size: 10, color: Colors.white70)),
                  ),
                ),
              ),
          ]),
        );
      }),
    );
  }
}
