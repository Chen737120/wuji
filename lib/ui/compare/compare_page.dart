import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../editing/media_source_picker.dart';
import '../../editing/compare_export.dart';
import '../../editing/export_service.dart';
import '../../editing/ffmpeg_probe.dart';
import '../../editing/overlap.dart';
import '../../editing/side_transform.dart';
import 'frame_adjust_view.dart';
import '../../theme.dart';
import 'align_view.dart';

/// 同屏对比页（规格 §4.1）：左右同屏双播放器，时间微调 → 画面微调 → 导出。
/// 以老师播放器为时钟主：我的播放器位置 = 老师位置 - offset。
class ComparePage extends StatefulWidget {
  const ComparePage({
    super.key,
    required this.teacher,
    required this.mine,
  });

  final PickedSource teacher;
  final PickedSource mine;

  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage> {
  VideoPlayerController? _teacherCtl;
  VideoPlayerController? _mineCtl;

  Duration _offset = Duration.zero;
  double _speed = 1.0;
  bool _adjustingFrame = false;
  bool _alignedConfirmed = false;
  bool _exporting = false;
  String _exportProgress = '';
  String? _audioChoice = 'teacher';
  ExportService? _exportSvc;
  int _selectedSide = 0;
  final SideTransform _left = SideTransform(ratio: '3:4');
  final SideTransform _right = SideTransform(ratio: '3:4');

  VideoPlayerController? get ctl => _teacherCtl;
  Duration get teacherDur =>
      _teacherCtl?.value.duration ?? widget.teacher.duration ?? Duration.zero;
  Duration get myDur =>
      _mineCtl?.value.duration ?? widget.mine.duration ?? Duration.zero;

  bool get exportable {
    final end = OverlapCalc.end(teacherDur, myDur, _offset);
    final start = OverlapCalc.start(_offset);
    return OverlapCalc.exportable(end, start);
  }

  @override
  void initState() {
    super.initState();
    _initPlayers();
  }

  Future<void> _initPlayers() async {
    try {
      final t = VideoPlayerController.file(File(widget.teacher.path));
      final m = VideoPlayerController.file(File(widget.mine.path));
      await t.initialize();
      await m.initialize();
      if (!mounted) {
        await t.dispose();
        await m.dispose();
        return;
      }
      setState(() {
        _teacherCtl = t;
        _mineCtl = m;
      });
      t.addListener(_onTeacherTick);
    } catch (_) {
      // 初始化失败（文件缺失/测试环境）：页面保持可交互，画面用占位
    }
  }

  /// 老师播放器作为时钟主。播放期间**完全不做 seek**——
  /// 高频 seek 会把我的视频卡成一帧一帧跳（真机复现）。
  /// 两控制器同倍率播放，时钟天然同步；对齐只在播放/拖动/微调时一次性施加。
  void _onTeacherTick() {
    final t = _teacherCtl;
    final m = _mineCtl;
    if (t == null || m == null || !mounted) return;
    if (t.value.isPlaying != m.value.isPlaying) {
      t.value.isPlaying ? m.play() : m.pause();
    }
    if (m.value.playbackSpeed != _speed) m.setPlaybackSpeed(_speed);
  }

  /// 把我的播放器对齐到老师当前进度（点播放/拖进度/微调时调用）。
  Future<void> _syncMineToTeacher() async {
    final t = _teacherCtl;
    final m = _mineCtl;
    if (t == null || m == null) return;
    final want = t.value.position - _offset;
    if (want >= Duration.zero && want <= m.value.duration) {
      await m.seekTo(want);
    }
  }

  Future<void> _applySpeed(double s) async {
    setState(() => _speed = s);
    await _teacherCtl?.setPlaybackSpeed(s);
    await _mineCtl?.setPlaybackSpeed(s);
  }

  Future<void> _togglePlay() async {
    final t = _teacherCtl;
    if (t == null) return;
    if (t.value.isPlaying) {
      await t.pause();
      await _mineCtl?.pause();
      if (mounted) setState(() {});
      return;
    }
    // 播放前一次性对齐起点，随后两路同倍率自然同步
    await _syncMineToTeacher();
    await t.play();
    await _mineCtl?.play();
    if (mounted) setState(() {});
  }

  Future<void> _export() async {
    if (_exporting || _teacherCtl == null || _mineCtl == null) return;
    setState(() => _exporting = true);
    try {
      _exportSvc ??= ExportService(
        runner: FFmpegKitRunner(),
        mover: GalleryMover(),
      );
      final teacherInfo = await probeMedia(widget.teacher.path);
      final overlapMs = overlapLength(teacherDur, myDur, _offset).inMilliseconds;
      final cmd = buildCompareCommand(
        teacherPath: widget.teacher.path,
        minePath: widget.mine.path,
        offset: _offset,
        teacherDur: teacherDur,
        myDur: myDur,
        left: _left,
        right: _right,
        leftSrc: Size((teacherInfo?.width ?? 1080).toDouble(),
            (teacherInfo?.height ?? 1920).toDouble()),
        rightSrc: Size(
            _mineCtl!.value.size.width, _mineCtl!.value.size.height),
        audio: _audioChoice!,
        fpsCap: teacherInfo?.fps == 0 ? 30 : (teacherInfo?.fps ?? 30),
      );
      await _exportSvc!.run(
        ExportJob(
            command: cmd,
            base: '对比',
            expectedDurationMs: overlapMs),
        onProgress: (p) {
          if (mounted) {
            setState(() => _exportProgress = '${(p * 100).round()}%');
          }
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存到相册 Movies/wuji/')));
    } on ExportCancelled {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已取消导出')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  void dispose() {
    _teacherCtl?.removeListener(_onTeacherTick);
    _teacherCtl?.dispose();
    _mineCtl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final t = _teacherCtl;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
            onPressed: () => Navigator.pop(context)),
        centerTitle: true,
        title: const Text('同屏对比',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
      body: Column(
              children: [
                // 双画面（左右同屏）；画面微调时放大并叠加固定裁剪框
                _adjustingFrame
                    ? Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                  child: _side(context, t, '老师视频',
                                      adjusting: true,
                                      transform: _left,
                                      selected: _selectedSide == 0,
                                      onSelect: () =>
                                          setState(() => _selectedSide = 0),
                                      onTransformed: () => setState(() {}))),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: _side(context, _mineCtl, '我的视频',
                                      adjusting: true,
                                      transform: _right,
                                      selected: _selectedSide == 1,
                                      onSelect: () =>
                                          setState(() => _selectedSide = 1),
                                      onTransformed: () => setState(() {}))),
                            ],
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                                child: _side(context, t, '老师视频',
                                    adjusting: false)),
                            const SizedBox(width: 6),
                            Expanded(
                                child: _side(context, _mineCtl, '我的视频',
                                    adjusting: false)),
                          ],
                        ),
                      ),
                const SizedBox(height: 8),
                // 播放/速度/进度条（拖动同时校正两路）
                Row(
                  children: [
                    IconButton(
                        onPressed: _togglePlay,
                        icon: Icon(
                            (t?.value.isPlaying ?? false)
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: AppColors.ink)),
                    Expanded(
                      child: (t != null && t.value.isInitialized)
                          ? Slider(
                              value: t.value.position.inMilliseconds
                                  .clamp(0, t.value.duration.inMilliseconds)
                                  .toDouble(),
                              max: t.value.duration.inMilliseconds
                                      .toDouble()
                                      .clamp(1, double.infinity)
                                      .toDouble(),
                              onChanged: (ms) async {
                                final pos = Duration(milliseconds: ms.round());
                                await t.seekTo(pos);
                                final want = pos - _offset;
                                if (!want.isNegative &&
                                    want <= _mineCtl!.value.duration) {
                                  await _mineCtl?.seekTo(want);
                                }
                                if (mounted) setState(() {});
                              },
                            )
                          : Container(height: 2, color: AppColors.hairline),
                    ),
                    PopupMenuButton<double>(
                      onSelected: _applySpeed,
                      itemBuilder: (_) => [
                        for (final s in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                          PopupMenuItem(
                              value: s,
                              child: Text('$s×',
                                  style: const TextStyle(fontSize: 13))),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text('$_speed×',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.secondary)),
                      ),
                    ),
                  ],
                ),
                // Tab：时间微调 | 画面微调
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _tab(context, '时间微调', !_adjustingFrame,
                        () => setState(() => _adjustingFrame = false)),
                    const SizedBox(width: 16),
                    _tab(context, '画面微调', _adjustingFrame,
                        () => setState(() => _adjustingFrame = true)),
                  ],
                ),
                if (_adjustingFrame)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FrameAdjustView(
                      left: _left,
                      right: _right,
                      selectedSide: _selectedSide,
                      onSelect: (s) => setState(() => _selectedSide = s),
                      onLeftChanged: () => setState(() {}),
                      onRightChanged: () => setState(() {})),
                  )
                else
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Expanded(
                            child: AlignView(
                              offset: _offset,
                              teacherDur: teacherDur,
                              myDur: myDur,
                              onStep: (v) => setState(() => _offset = v),
                              onReset: () =>
                                  setState(() => _offset = Duration.zero),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 确认已对齐：确认后导出按钮才可用
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: _alignedConfirmed
                                  ? accent
                                  : Colors.white,
                              foregroundColor: _alignedConfirmed
                                  ? Colors.white
                                  : AppColors.ink,
                              side: _alignedConfirmed
                                  ? null
                                  : const BorderSide(
                                      color: AppColors.hairline),
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 8),
                            ),
                            onPressed: () =>
                                setState(() => _alignedConfirmed = true),
                            icon: Icon(_alignedConfirmed
                                ? Icons.check_circle
                                : Icons.check_circle_outline),
                            label: Text(
                                _alignedConfirmed ? '已确认对齐' : '确认已对齐',
                                style: const TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  ),
                // 音源选择（导出前可切）
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('对比音频：',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.secondary)),
                        for (final (v, label) in [
                          ('teacher', '老师原声'),
                          ('mine', '我的原声'),
                          ('none', '静音'),
                        ])
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text(label,
                                  style: const TextStyle(fontSize: 11)),
                              selected: _audioChoice == v,
                              selectedColor: accent,
                              backgroundColor: Colors.white,
                              labelStyle: TextStyle(
                                  color: _audioChoice == v
                                      ? Colors.white
                                      : AppColors.ink),
                              onSelected: (_) =>
                                  setState(() => _audioChoice = v),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              exportable ? accent : AppColors.hairline,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        onPressed: (_exporting || !exportable || !_alignedConfirmed)
                            ? null
                            : _export,
                        child: Text(
                            _exporting
                                ? '导出中 ${_exportProgress.isEmpty ? '' : _exportProgress}'
                                : (!exportable
                                    ? '重叠区间不足 1 秒，无法导出'
                                    : (!_alignedConfirmed
                                        ? '请先「确认已对齐」'
                                        : '导出视频')),
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: (exportable && _alignedConfirmed)
                                    ? Colors.white
                                    : AppColors.faint)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// 单侧画面。非微调：小窗播放。画面微调：撑满＋固定裁剪框，
  /// 手势改变该侧 SideTransform（框不动、框内内容平移/缩放）。
  Widget _side(
    BuildContext context,
    VideoPlayerController? ctl,
    String label, {
    bool adjusting = false,
    SideTransform? transform,
    bool selected = false,
    VoidCallback? onSelect,
    VoidCallback? onTransformed,
  }) {
    final ready = ctl != null && ctl.value.isInitialized;
    if (!adjusting || transform == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: AppColors.faint)),
          const SizedBox(height: 4),
          Container(
            height: 110,
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: ready
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AspectRatio(
                      aspectRatio: ctl.value.aspectRatio,
                      child: VideoPlayer(ctl),
                    ),
                  )
                : const Icon(Icons.play_arrow, color: AppColors.bg, size: 30),
          ),
        ],
      );
    }
    // 画面微调态
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.faint)),
        const SizedBox(height: 4),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSelect?.call,
            onScaleStart: (_) => onSelect?.call(),
            onScaleUpdate: (d) {
              if (d.pointerCount >= 2) {
                transform.scale =
                    (transform.scale * d.scale).clamp(1.0, 4.0);
              } else {
                transform.pan = Offset(
                  (transform.pan.dx - d.focalPointDelta.dx / 200)
                      .clamp(-1.0, 1.0),
                  (transform.pan.dy + d.focalPointDelta.dy / 200)
                      .clamp(-1.0, 1.0),
                );
              }
              onTransformed?.call();
            },
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: selected ? accent : AppColors.hairline,
                    width: selected ? 2 : 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: ready
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          // 内容层：按变换平移/缩放（固定裁剪框不动）
                          LayoutBuilder(builder: (context, box) {
                            final va = ctl.value.aspectRatio;
                            double w = box.maxHeight * va;
                            double h = box.maxHeight;
                            if (w < box.maxWidth) {
                              w = box.maxWidth;
                              h = box.maxWidth / va;
                            }
                            return Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..translateByDouble(
                                    transform.pan.dx * w * 0.3,
                                    transform.pan.dy * h * 0.3,
                                    0,
                                    1)
                                ..scaleByDouble(transform.scale,
                                    transform.scale, 1, 1),
                              child: SizedBox(
                                  width: w,
                                  height: h,
                                  child: VideoPlayer(ctl)),
                            );
                          }),
                        ],
                      )
                    : const Center(
                        child: Text('视频加载中…',
                            style: TextStyle(
                                fontSize: 10, color: AppColors.faint)),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tab(BuildContext context, String label, bool selected, VoidCallback onTap) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? AppColors.ink : AppColors.faint)),
          const SizedBox(height: 3),
          Container(
            height: 2,
            width: 56,
            decoration: BoxDecoration(
              color: selected ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }
}

