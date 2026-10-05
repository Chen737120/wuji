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
import 'align_view.dart';

/// 同屏对比编辑页——深暗色（与选择页一致，用户 2026-10-05 指定风格）。
/// 结构：顶部小 tab → 双画面 → 播放行 → 大 tab → 面板 → 音源+导出。
/// 画面微调模式：视频 cover 打底，**比例裁剪框外的部分被遮罩盖住不可见**
/// （遮罩预览），手势只移动框内内容。
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

/// 暗色皮肤（页面级常量，点缀色仍取主题）。
abstract final class DarkSkin {
  static const bg = Color(0xFF0F0F11);
  static const card = Color(0xFF1C1C1F);
  static const line = Color(0xFF2E2E33);
  static const text = Color(0xFFF2F2F2);
  static const sub = Color(0xFF9A9AA0);
  static const faint = Color(0xFF6A6A70);
  static const track = Color(0xFF2A2A2E);
}

class _ComparePageState extends State<ComparePage> {
  /// 双画面预览容器高（逻辑像素）——SideTransform.frameInContainer 的
  /// 边距折算与导出 containerAspect 都依赖此值，改动需同步。
  static const double previewH = 210;

  VideoPlayerController? _teacherCtl;
  VideoPlayerController? _mineCtl;

  Duration _offset = Duration.zero;
  double _speed = 1.0;
  double _appliedSpeed = 1.0;
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
  void _onTeacherTick() {
    final t = _teacherCtl;
    final m = _mineCtl;
    if (t == null || m == null || !mounted) return;
    if (t.value.isPlaying && !m.value.isPlaying) {
      final ended = m.value.duration > Duration.zero &&
          m.value.position >=
              m.value.duration - const Duration(milliseconds: 80);
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

  /// 把我的播放器对齐到老师当前进度。漂移小于 250ms 不 seek。
  Future<void> _syncMineToTeacher({bool force = false}) async {
    final t = _teacherCtl;
    final m = _mineCtl;
    if (t == null || m == null) return;
    final want = t.value.position - _offset;
    if (want < Duration.zero || want > m.value.duration) return;
    final drift = (m.value.position - want).inMilliseconds.abs();
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
    await _syncMineToTeacher();
    await t.play();
    await m?.play();
  }

  void _onOffsetChanged(Duration v) {
    setState(() => _offset = v);
    final t = _teacherCtl;
    if (t != null && !t.value.isPlaying) {
      _syncMineToTeacher(force: true);
    }
  }

  Future<void> _export() async {
    if (_exporting || _teacherCtl == null || _mineCtl == null) return;
    // 预览容器宽高比（与 _side 的 LayoutBuilder 实际容器一致）：
    // 页面左右 Padding 14×2、两列间距 6 → 容器宽=(屏宽-34)/2，高=210
    final screenW = MediaQuery.sizeOf(context).width;
    final containerAspect = (screenW - 34) / 2 / previewH;
    setState(() => _exporting = true);
    try {
      _exportSvc ??= ExportService(
        runner: FFmpegKitRunner(),
        mover: GalleryMover(),
      );
      final teacherInfo = await probeMedia(widget.teacher.path);
      final overlapMs =
          overlapLength(teacherDur, myDur, _offset).inMilliseconds;
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
        rightSrc:
            Size(_mineCtl!.value.size.width, _mineCtl!.value.size.height),
        audio: _audioChoice!,
        fpsCap: teacherInfo?.fps == 0 ? 30 : (teacherInfo?.fps ?? 30),
        containerAspect: containerAspect,
      );
      await _exportSvc!.run(
        ExportJob(command: cmd, base: '对比', expectedDurationMs: overlapMs),
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
      backgroundColor: DarkSkin.bg,
      appBar: AppBar(
        backgroundColor: DarkSkin.bg,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: DarkSkin.text),
            onPressed: () => Navigator.pop(context)),
        centerTitle: true,
        title: const Text('同屏对比',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DarkSkin.text)),
      ),
      body: Column(
        children: [
          _topTabs(),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              height: previewH,
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
          if (!_adjustingFrame)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        _alignedConfirmed ? accent : DarkSkin.card,
                    foregroundColor:
                        _alignedConfirmed ? Colors.white : DarkSkin.sub,
                    side: _alignedConfirmed
                        ? null
                        : const BorderSide(color: DarkSkin.line),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () =>
                      setState(() => _alignedConfirmed = !_alignedConfirmed),
                  child: Text(_alignedConfirmed ? '已确认对齐 ✓' : '确认已对齐',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('音频：',
                          style: TextStyle(
                              fontSize: 11, color: DarkSkin.sub)),
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
                            backgroundColor: DarkSkin.card,
                            labelStyle: TextStyle(
                                color: _audioChoice == v
                                    ? Colors.white
                                    : DarkSkin.sub),
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
                            exportable ? accent : DarkSkin.card,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      onPressed:
                          (_exporting || !exportable || !_alignedConfirmed)
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
                                  : DarkSkin.faint)),
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
                  color: selected ? accent : DarkSkin.faint)),
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

  Widget _bigTab(BuildContext context, IconData icon, String label,
      bool selected, VoidCallback onTap) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: DarkSkin.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? accent : DarkSkin.line,
              width: selected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? accent : DarkSkin.faint),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? accent : DarkSkin.sub)),
          ],
        ),
      ),
    );
  }

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
                    fontSize: 11, color: DarkSkin.sub)),
            Expanded(
              child: IconButton(
                  onPressed: _togglePlay,
                  icon: Icon(
                    t.value.isPlaying
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                    color: DarkSkin.text,
                    size: 28,
                  )),
            ),
            GestureDetector(
              onTap: () => _showSpeedMenu(context),
              child: Text('$_speed×',
                  style:
                      TextStyle(fontSize: 12, color: DarkSkin.sub)),
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
              inactiveTrackColor: DarkSkin.track,
              thumbColor: Colors.white,
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

  /// 单侧画面（暗色）。**遮罩裁剪语义（2026-10-05 用户反馈重做）**：
  /// 视频以正常大小完整打底（contain，不变形不预裁切）；
  /// 画面微调态叠加固定比例裁剪框（实线=老师、虚线=我的），
  /// **框外遮住不可见**；单指拖/双指缩放移动的是框下面的视频画面；
  /// 切换比例=改变框的大小；框内即导出画面。
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
        color: Colors.black,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready)
              LayoutBuilder(builder: (context, b) {
                // 容器归一化坐标（高=1）→ 像素
                final unit = b.maxHeight;
                final ca = b.maxWidth / b.maxHeight;
                final src = ctl.value.size;
                Rect px(Rect r) => Rect.fromLTWH(
                    r.left * unit, r.top * unit, r.width * unit, r.height * unit);
                final videoRect = frameMode
                    ? transform.videoRectInContainer(src, ca)
                    : _containRect(src, ca);
                final frameRect =
                    frameMode ? transform.frameInContainer(ca) : null;
                return Stack(
                  children: [
                    Positioned.fromRect(
                      rect: px(videoRect),
                      child: VideoPlayer(ctl),
                    ),
                    if (frameRect != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _MaskPainter(
                              frame: px(frameRect),
                              strokeColor: selected
                                  ? accent
                                  : Colors.white.withValues(alpha: .8),
                              strokeWidth: selected ? 2 : 1.2,
                              dashed: dashed,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              })
            else
              const Center(
                child: Icon(Icons.play_arrow, color: DarkSkin.faint, size: 30),
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
                fontWeight: frameMode && selected
                    ? FontWeight.w700
                    : FontWeight.w400,
                color: frameMode && selected ? accent : DarkSkin.faint)),
        const SizedBox(height: 4),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: frameMode ? onSelect : null,
            onScaleStart: frameMode ? (_) => onSelect?.call() : null,
            onScaleUpdate: frameMode
                ? (d) {
                    if (d.pointerCount >= 2) {
                      // 双指缩放：放大框下面的视频画面
                      transform.scale =
                          (transform.scale * d.scale).clamp(1.0, 4.0);
                    } else {
                      // 单指拖动：移动视频（容器像素 → 归一化单位）
                      final unit = previewH;
                      transform.pan = Offset(
                        transform.pan.dx +
                            d.focalPointDelta.dx / unit,
                        transform.pan.dy +
                            d.focalPointDelta.dy / unit,
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

  /// 非微调态：完整画面 contain 打底（与画面微调态同一视觉基准）。
  Rect _containRect(Size src, double containerAspect) {
    final sa = src.width / src.height;
    double w, h;
    if (sa > containerAspect) {
      w = containerAspect;
      h = containerAspect / sa;
    } else {
      h = 1.0;
      w = sa;
    }
    return Rect.fromCenter(
        center: Offset(containerAspect / 2, 0.5), width: w, height: h);
  }
}

/// 遮罩预览：比例框外四块黑遮罩＋框描边（实线/虚线）。
class _MaskPainter extends CustomPainter {
  _MaskPainter({
    required this.frame,
    required this.strokeColor,
    required this.strokeWidth,
    required this.dashed,
  });

  final Rect frame;
  final Color strokeColor;
  final double strokeWidth;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final maskPaint = Paint()..color = Colors.black.withValues(alpha: .88);
    final outer = Offset.zero & size;
    // 四块：上、下、左、右
    canvas.drawRect(
        Rect.fromLTRB(outer.left, outer.top, outer.right, frame.top),
        maskPaint);
    canvas.drawRect(
        Rect.fromLTRB(outer.left, frame.bottom, outer.right, outer.bottom),
        maskPaint);
    canvas.drawRect(
        Rect.fromLTRB(outer.left, frame.top, frame.left, frame.bottom),
        maskPaint);
    canvas.drawRect(
        Rect.fromLTRB(frame.right, frame.top, outer.right, frame.bottom),
        maskPaint);

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(4)));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = strokeColor;
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
  bool shouldRepaint(covariant _MaskPainter old) =>
      old.frame != frame ||
      old.strokeColor != strokeColor ||
      old.dashed != dashed;
}
