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

/// 同屏对比页（规格 §4.1 + 原型 03-compare-flow）：
/// 顶部小 tab → 双画面（**固定高度，两种模式同高**，画面微调只是在画面上
/// 叠加固定裁剪框、框内内容平移缩放，绝不改变视频显示尺寸）→ 播放行
/// （时间/播放/倍速）→ 大 tab 按钮 → 面板 → 音源+导出。
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
  double _appliedSpeed = 1.0; // 已实际下发到播放器的倍速（避免重复 setSpeed）
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
      // mixWithOthers（排查报告 P0）：不抢音频焦点——默认行为下第二个
      // 播放器请求焦点会把第一个卡住/暂停，表现为"只有一个视频能播"
      final t = VideoPlayerController.file(File(widget.teacher.path),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
      final m = VideoPlayerController.file(File(widget.mine.path),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
      await Future.wait([t.initialize(), m.initialize()]);
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
    if (t.value.isPlaying && !m.value.isPlaying) {
      // 我的视频已到片尾时不要反复 play()（会被重新拉起跳回）
      final ended = m.value.duration > Duration.zero &&
          m.value.position >= m.value.duration -
              const Duration(milliseconds: 80);
      if (!ended) m.play();
    } else if (!t.value.isPlaying && m.value.isPlaying) {
      m.pause();
    }
    if (_speed != _appliedSpeed) {
      _appliedSpeed = _speed;
      t.setPlaybackSpeed(_speed);
      m.setPlaybackSpeed(_speed);
    }
  }

  /// 把我的播放器对齐到老师当前进度（点播放/拖进度/微调时调用）。
  /// 漂移小于 250ms 不 seek——无谓的 seek 正是"点播放只动一帧"的来源。
  Future<void> _syncMineToTeacher({bool force = false}) async {
    final t = _teacherCtl;
    final m = _mineCtl;
    if (t == null || m == null) return;
    final want = t.value.position - _offset;
    if (want < Duration.zero || want > m.value.duration) return;
    final drift =
        (m.value.position - want).inMilliseconds.abs();
    if (force || drift > 250) {
      await m.seekTo(want);
    }
  }

  Future<void> _applySpeed(double s) async {
    setState(() => _speed = s);
    _appliedSpeed = s;
    await _teacherCtl?.setPlaybackSpeed(s);
    await _mineCtl?.setPlaybackSpeed(s);
  }

  Future<void> _togglePlay() async {
    final t = _teacherCtl;
    final m = _mineCtl;
    if (t == null) return;
    if (t.value.isPlaying) {
      await t.pause();
      await m?.pause();
      return;
    }
    // 播放前一次性对齐起点，随后两路同倍率自然同步
    await _syncMineToTeacher();
    await t.play();
    await m?.play();
  }

  /// 时间微调步进：暂停状态下同步移动我的画面，让用户直接看到对齐效果。
  void _onOffsetChanged(Duration v) {
    setState(() => _offset = v);
    final t = _teacherCtl;
    if (t != null && !t.value.isPlaying) {
      _syncMineToTeacher(force: true);
    }
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
          // 顶部小 tab（原型②③：页面顶部居中、选中点缀色下划线）
          _topTabs(),
          const SizedBox(height: 4),
          // 双画面：固定高度，两种模式同高（原型②③一致；不改变视频长宽高）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              height: 210,
              child: Row(
                children: [
                  Expanded(
                      child: _side(context, t, '老师视频',
                          dashed: false,
                          transform: _left,
                          selected: _selectedSide == 0,
                          onSelect: () => setState(() => _selectedSide = 0),
                          onTransformed: () => setState(() {}))),
                  const SizedBox(width: 6),
                  Expanded(
                      child: _side(context, _mineCtl, '我的视频',
                          dashed: true,
                          transform: _right,
                          selected: _selectedSide == 1,
                          onSelect: () => setState(() => _selectedSide = 1),
                          onTransformed: () => setState(() {}))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // 播放行＋细进度条（只重建这一段，不惊动双播放器）
          if (t != null && t.value.isInitialized)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: t,
                builder: (context, value, child) => _playbackRow(context, t),
              ),
            )
          else
            const SizedBox(height: 8),
          const SizedBox(height: 6),
          // 大 tab 按钮（原型：图标+文字、描边圆角）
          Row(
            children: [
              const SizedBox(width: 14),
              Expanded(
                  child: _bigTab(context, Icons.schedule, '时间微调',
                      !_adjustingFrame, () => setState(() => _adjustingFrame = false))),
              const SizedBox(width: 8),
              Expanded(
                  child: _bigTab(context, Icons.swap_horiz, '画面微调',
                      _adjustingFrame, () => setState(() => _adjustingFrame = true))),
              const SizedBox(width: 14),
            ],
          ),
          Expanded(
            child: _adjustingFrame
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: FrameAdjustView(
                      left: _left,
                      right: _right,
                      selectedSide: _selectedSide,
                      onSelect: (s) => setState(() => _selectedSide = s),
                      onLeftChanged: () => setState(() {}),
                      onRightChanged: () => setState(() {})),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                    child: AlignView(
                      offset: _offset,
                      teacherDur: teacherDur,
                      myDur: myDur,
                      onStep: _onOffsetChanged,
                      onReset: () => _onOffsetChanged(Duration.zero),
                    ),
                  ),
          ),
          // 确认已对齐（时间微调面板底部，原型②）
          if (!_adjustingFrame)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        _alignedConfirmed ? accent : Colors.white,
                    foregroundColor:
                        _alignedConfirmed ? Colors.white : AppColors.ink,
                    side: _alignedConfirmed
                        ? null
                        : const BorderSide(color: AppColors.hairline),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () =>
                      setState(() => _alignedConfirmed = !_alignedConfirmed),
                  child: Text(
                      _alignedConfirmed ? '已确认对齐 ✓' : '确认已对齐',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          // 音源选择（原型③：导出按钮上方一行小 chips）
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('音频：',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.secondary)),
                      for (final (v, label) in [
                        ('teacher', '老师原声'),
                        ('mine', '我的原声'),
                        ('none', '静音'),
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: ChoiceChip(
                            label: Text(label,
                                style: const TextStyle(fontSize: 10)),
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
                  const SizedBox(height: 6),
                  SizedBox(
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
                                      : '导出视频（720p）')),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: (exportable && _alignedConfirmed)
                                  ? Colors.white
                                  : AppColors.faint)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部小 tab（原型②③顶部：居中两词，选中点缀色+下划线）。
  Widget _topTabs() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _miniTab('时间微调', !_adjustingFrame,
            () => setState(() => _adjustingFrame = false)),
        const SizedBox(width: 24),
        _miniTab('画面微调', _adjustingFrame,
            () => setState(() => _adjustingFrame = true)),
      ],
    );
  }

  Widget _miniTab(String label, bool selected, VoidCallback onTap) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? accent : AppColors.faint)),
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

  /// 大 tab 按钮（原型②③：图标+文字、描边圆角10、选中点缀色描边加粗）。
  Widget _bigTab(BuildContext context, IconData icon, String label,
      bool selected, VoidCallback onTap) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? accent : AppColors.hairline,
              width: selected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: selected ? accent : AppColors.faint),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? accent : AppColors.faint)),
          ],
        ),
      ),
    );
  }

  /// 播放行：时间（左）／播放（中）／倍速（右）＋细进度条（原型②③）。
  Widget _playbackRow(BuildContext context, VideoPlayerController t) {
    String fmt(Duration d) {
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Row(
          children: [
            Text('${fmt(t.value.position)} / ${fmt(t.value.duration)}',
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.secondary,
                    fontFeatures: [])),
            Expanded(
              child: IconButton(
                  onPressed: _togglePlay,
                  icon: Icon(
                    t.value.isPlaying ? Icons.pause_circle_outline : Icons.play_circle_outline,
                    color: AppColors.ink,
                    size: 28,
                  )),
            ),
            GestureDetector(
              onTap: () => _showSpeedMenu(context),
              child: Text('$_speed×',
                  style: TextStyle(fontSize: 12, color: AppColors.secondary)),
            ),
          ],
        ),
        SizedBox(
          height: 18,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.5,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: accent,
              inactiveTrackColor: AppColors.hairline,
              thumbColor: AppColors.ink,
            ),
            child: Slider(
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
                    want <= (_mineCtl?.value.duration ?? Duration.zero)) {
                  await _mineCtl?.seekTo(want);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showSpeedMenu(BuildContext context) async {
    final s = await showMenu<double>(
      context: context,
      position: const RelativeRect.fromLTRB(200, 300, 40, 300),
      items: [
        for (final v in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
          PopupMenuItem(value: v, child: Text('$v×')),
      ],
    );
    if (s != null) await _applySpeed(s);
  }

  /// 单侧画面。**两种模式同一固定高度**：
  /// - 时间微调态：cover 播放；
  /// - 画面微调态：同样 cover，叠加固定裁剪框（实线=老师、虚线=我的），
  ///   手势只改框内内容（平移/缩放），框与视频尺寸都不变。
  Widget _side(
    BuildContext context,
    VideoPlayerController? ctl,
    String label, {
    required bool dashed,
    SideTransform? transform,
    bool selected = false,
    VoidCallback? onSelect,
    VoidCallback? onTransformed,
  }) {
    final ready = ctl != null && ctl.value.isInitialized;
    final accent = Theme.of(context).colorScheme.primary;
    final frameMode = _adjustingFrame && transform != null;
    final box = Container(
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready)
              LayoutBuilder(builder: (context, b) {
                final va = ctl.value.aspectRatio;
                double w = b.maxHeight * va;
                double h = b.maxHeight;
                if (w < b.maxWidth) {
                  w = b.maxWidth;
                  h = b.maxWidth / va;
                }
                final video = SizedBox(width: w, height: h, child: VideoPlayer(ctl));
                // 画面微调：框内内容平移/缩放（框与视频尺寸不动）
                final transformed = frameMode
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..translateByDouble(transform.pan.dx * w * 0.3,
                              transform.pan.dy * h * 0.3, 0, 1)
                          ..scaleByDouble(
                              transform.scale, transform.scale, 1, 1),
                        child: video,
                      )
                    : video;
                return Center(child: transformed);
              })
            else
              const Center(
                child: Icon(Icons.play_arrow, color: AppColors.bg, size: 30),
              ),
            // 固定裁剪框（仅画面微调态显示）：实线=老师侧、虚线=我的侧
            if (frameMode)
              Positioned.fill(
                child: IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: CustomPaint(
                      painter: _FramePainter(
                        color: selected
                            ? accent
                            : Colors.white.withValues(alpha: .85),
                        strokeWidth: selected ? 2 : 1.2,
                        dashed: dashed,
                        radius: 6,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: frameMode && selected ? FontWeight.w700 : FontWeight.w400,
                color: frameMode && selected ? accent : AppColors.faint)),
        const SizedBox(height: 4),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: frameMode ? onSelect : null,
            onScaleStart: frameMode ? (_) => onSelect?.call() : null,
            onScaleUpdate: frameMode
                ? (d) {
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
                  }
                : null,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: frameMode && selected
                        ? accent
                        : Colors.transparent,
                    width: 1.5),
              ),
              child: box,
            ),
          ),
        ),
      ],
    );
  }
}

/// 裁剪框描边：实线或虚线圆角矩形（原型③：实线框=老师侧、虚线框=我的侧）。
class _FramePainter extends CustomPainter {
  _FramePainter({
    required this.color,
    required this.strokeWidth,
    required this.dashed,
    required this.radius,
  });

  final Color color;
  final double strokeWidth;
  final bool dashed;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, Radius.circular(radius)));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color;
    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final metric in path.computeMetrics()) {
      const dashLen = 7.0;
      const gapLen = 5.0;
      var dist = 0.0;
      while (dist < metric.length) {
        final next = (dist + dashLen).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(dist, next), paint);
        dist = next + gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) =>
      old.color != color || old.dashed != dashed || old.strokeWidth != strokeWidth;
}
