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
import 'playback_plan.dart';

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
  // 方案一（2026-10-05 用户确认）：画面框＝裁剪框，**比例全局共享**，
  // 切换时老师/我的画面框同时变形；平移/缩放仍每侧独立。
  String _ratio = '3:4';
  final SideTransform _left = SideTransform(ratio: '3:4');
  final SideTransform _right = SideTransform(ratio: '3:4');

  /// 画面框高度＝每侧宽 / 比例（框即裁剪区，比例切换时框变形）。
  /// 每侧宽 = (屏宽 - 页边距 28 - 列间距 6) / 2。
  double _previewH(double screenW) {
    final sideW = (screenW - 34) / 2;
    return (sideW / _left.aspect).clamp(160.0, 340.0);
  }

  void _setRatio(String r) {
    setState(() {
      _ratio = r;
      _left.ratio = r;
      _right.ratio = r;
    });
  }

  double _scaleAtStart = 1.0; // 双指手势开始时的缩放基准

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
    VideoPlayerController? t;
    VideoPlayerController? m;
    try {
      // mixWithOthers（排查报告 P0）：不抢音频焦点——默认行为下第二个
      // 播放器请求焦点会把第一个卡住/暂停，表现为"只有一个视频能播"
      t = VideoPlayerController.file(File(widget.teacher.path),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
      m = VideoPlayerController.file(File(widget.mine.path),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
      await Future.wait([t.initialize(), m.initialize()]);
      if (!mounted) {
        await _disposeQuietly(t);
        await _disposeQuietly(m);
        return;
      }
      setState(() {
        _teacherCtl = t;
        _mineCtl = m;
      });
      t.addListener(_onTeacherTick);
      // 所有权已转交 State，避免 catch 里二次 dispose
      t = null;
      m = null;
    } catch (_) {
      // 初始化失败（文件缺失/测试环境）：已创建成功的控制器必须回收（P2-22），
      // 否则页面终身持有无法重试的 ExoPlayer
      await _disposeQuietly(t);
      await _disposeQuietly(m);
    }
  }

  /// initialize 失败的控制器 dispose 也可能抛，逐个吞掉。
  Future<void> _disposeQuietly(VideoPlayerController? c) async {
    if (c == null) return;
    try {
      await c.dispose();
    } catch (_) {}
  }

  /// 是否已播到结尾（video_player 无播放结束回调，用 80ms 阈值判定）。
  static bool _atEnd(VideoPlayerValue v) =>
      isAtEnd(v.position, v.duration);

  /// 老师播放器作为时钟主。播放期间**完全不做 seek**——
  /// 高频 seek 会把我的视频卡成一帧一帧跳（真机复现）。
  void _onTeacherTick() {
    final t = _teacherCtl;
    final m = _mineCtl;
    if (t == null || m == null || !mounted) return;
    if (t.value.isPlaying && !m.value.isPlaying) {
      if (!_atEnd(m.value)) m.play();
    } else if (!t.value.isPlaying && m.value.isPlaying) {
      // 老师自然播完到结尾（非用户暂停）→ 让「我的」继续播完自己的剩余
      // 时长：v1.5.22 起它被硬暂停在 dur-offset 处，永远差 offset 秒播不完
      // （用户反馈「时间微调失效」的可见表现之一，缺陷会话 2026-10-26）。
      // 「我的」播到自己结尾时 ExoPlayer 自动 ENDED，下一 tick 两分支都不
      // 命中，状态稳定。边界（接受）：用户恰在老师结尾 80ms 内手动暂停也
      // 会被视作播完，我的会多播完剩余部分。
      if (!_atEnd(t.value)) m.pause();
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
    // 起播/重播/续播统一由纯函数给出（缺陷会话 2026-10-26）：
    // v1.5.22 的归零重播块每路连发 2 次 seek（归零 + offset 起点）且在
    // 毫秒级内完成，ExoPlayer 逐次替换 seek 目标时真机出现 surface 灰块；
    // 现在重播只剩「每路 1 次直达 seek」，中途续播则完全不 seek（语义与
    // 改前一致）。null = 原地续播。
    final plan = planPlayStart(
      teacherPos: t.value.position,
      teacherDur: t.value.duration,
      minePos: m?.value.position ?? Duration.zero,
      offset: _offset,
    );
    if (plan != null) {
      await t.seekTo(plan.teacher);
      await m?.seekTo(plan.mine);
    }
    await t.play();
    // 已播完的「我的」不再 play()（P1-9）：ExoPlayer 对 ENDED 态 play()
    // 可能回零重播，而老师从当前位置续播 → 此后 tick 两分支都不命中，永久失步
    if (m != null && !isAtEnd(m.value.position, m.value.duration)) {
      await m.play();
    }
  }

  void _onOffsetChanged(Duration v) {
    setState(() => _offset = v);
    final t = _teacherCtl;
    if (t != null && !t.value.isPlaying) {
      // 暂停态即时预览偏移：offset>0 时老师至少走到 offset（模拟导出起点）
      if (v > Duration.zero && t.value.position < v) {
        t.seekTo(v);
      }
      _syncMineToTeacher(force: true);
    }
  }

  Future<void> _export() async {
    if (_exporting || _teacherCtl == null || _mineCtl == null) return;
    // 画面框＝裁剪框（方案一）：两侧同比例，containerAspect = 所选比例
    final containerAspect = _left.aspect;
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
        leftSrc: resolveSourceSize(
          // 显示域优先（与预览、mine 侧同域）；probe 只在控制器未就绪时兜底
          rendered: (_teacherCtl?.value.isInitialized ?? false)
              ? _teacherCtl!.value.size
              : null,
          probeW: teacherInfo?.width,
          probeH: teacherInfo?.height,
        ),
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
              // 画面框＝裁剪框：高度随比例变（3:4≈244、9:16≈325、1:1≈183）
              height: _previewH(MediaQuery.sizeOf(context).width),
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
                      ratio: _ratio,
                      onRatioChanged: _setRatio,
                    ),
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
                                      : '导出视频（1080p）')),
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

  /// 单侧画面（暗色，方案一：**画面框＝裁剪框**）：
  /// 容器本身按所选比例呈现，视频 cover 填满画面框（溢出即被裁掉，
  /// 所见即所得，无叠加框/遮罩）；时间微调与画面微调两个 tab 用同一呈现。
  /// 画面微调态：单指拖动/双指缩放框下的视频；选中侧描边高亮。
  Widget _side(
    BuildContext context,
    VideoPlayerController? ctl,
    String label, {
    required bool dashed,
    required SideTransform transform,
    bool selected = false,
    VoidCallback? onSelect,
    VoidCallback? onTransformed,
  }) {
    final ready = ctl != null && ctl.value.isInitialized;
    final accent = Theme.of(context).colorScheme.primary;
    final frameMode = _adjustingFrame;
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
                // 容器（画面框）归一化坐标：高=1、宽=比例 aspect。
                // 注意：Positioned 必须是 Stack 直接子级——LayoutBuilder
                // 内要再套一层本地 Stack，否则渲染树构建失败 → 灰色占位
                // （v1.5.9 灰块 bug 根因）。
                final unit = b.maxHeight;
                final ca = transform.aspect;
                final src = ctl.value.size;
                Rect px(Rect r) => Rect.fromLTWH(
                    r.left * unit, r.top * unit, r.width * unit, r.height * unit);
                final videoRect = transform.videoRectInContainer(src, ca);
                return Stack(
                  children: [
                    Positioned.fromRect(
                      rect: px(videoRect),
                      child: VideoPlayer(ctl),
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
            onScaleStart: frameMode
                ? (d) {
                    onSelect?.call();
                    // 记录手势开始时的缩放基准——d.scale 是相对手势开始的
                    // 累计比例，旧实现每帧再乘一次导致指数跳变（一捏就过大）
                    _scaleAtStart = transform.scale;
                  }
                : null,
            onScaleUpdate: frameMode
                ? (d) {
                    if (d.pointerCount >= 2) {
                      // 双指缩放：以手势开始时的缩放为基准 × 累计比例
                      transform.scale =
                          (_scaleAtStart * d.scale).clamp(1.0, 4.0);
                    } else {
                      // 单指拖动：移动视频（框像素 → 归一化单位，unit=框高）
                      final unit = _previewH(MediaQuery.sizeOf(context).width);
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
}
