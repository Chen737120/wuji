import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../editing/media_source_picker.dart';
import '../../editing/overlap.dart';
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

  /// 老师播放器作为时钟主：位置/播放状态/速度变化时同步我的播放器。
  void _onTeacherTick() {
    final t = _teacherCtl;
    final m = _mineCtl;
    if (t == null || m == null || !mounted) return;
    final want = t.value.position - _offset;
    final drift = (m.value.position - want).inMilliseconds.abs();
    if (drift > 80 && want >= Duration.zero && want <= m.value.duration) {
      m.seekTo(want);
    }
    if (t.value.isPlaying != m.value.isPlaying) {
      t.value.isPlaying ? m.play() : m.pause();
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
    t.value.isPlaying ? await t.pause() : await t.play();
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
                // 双画面（左右同屏）
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(child: _side(context, t, '老师视频')),
                      const SizedBox(width: 6),
                      Expanded(child: _side(context, _mineCtl, '我的视频')),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // 播放/速度
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                        onPressed: _togglePlay,
                        icon: Icon(
                            (t?.value.isPlaying ?? false)
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: AppColors.ink)),
                    const SizedBox(width: 8),
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
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _adjustingFrame
                        ? Center(
                            child: Text('画面微调（下一步接入）',
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.faint)))
                        : AlignView(
                            offset: _offset,
                            teacherDur: teacherDur,
                            myDur: myDur,
                            onStep: (v) => setState(() => _offset = v),
                            onReset: () =>
                                setState(() => _offset = Duration.zero),
                          ),
                  ),
                ),
                // 底部导出按钮（T6 接线；先按重叠区间做可用性提示）
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
                        onPressed: exportable ? () {} : null,
                        child: Text(
                            exportable ? '导出视频' : '重叠区间不足 1 秒，无法导出',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color:
                                    exportable ? Colors.white : AppColors.faint)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _side(BuildContext context, VideoPlayerController? ctl, String label) {
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
          child: ctl != null && ctl.value.isInitialized
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

