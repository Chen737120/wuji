import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../editing/media_source_picker.dart';
import '../widgets/app_route.dart';

Duration _clampDur(Duration d, Duration lo, Duration hi) =>
    d < lo ? lo : (d > hi ? hi : d);

/// 舞蹈直拍·修剪长度页（2026-10-05 用户需求 #3，流程新增的第一步）：
/// 选完视频先在此播放预览、拖动起点/终点手柄设定保留区间（最短 1 秒），
/// 确认后进入圈选框编辑；导出只含修剪区间。
class TrimPage extends StatefulWidget {
  const TrimPage({super.key, required this.source});

  final PickedSource source;

  @override
  State<TrimPage> createState() => _TrimPageState();
}

class _TrimPageState extends State<TrimPage> {
  VideoPlayerController? _ctl;
  Duration _start = Duration.zero;
  Duration _end = Duration.zero;
  bool _initialized = false;

  VideoPlayerController? get ctl => _ctl;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.file(File(widget.source.path),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _ctl = c;
        _end = c.value.duration;
        _initialized = true;
      });
      c.addListener(_onTick);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('视频加载失败')));
    }
  }

  /// 播放到终点自动停；起点前开播时先跳到起点。
  void _onTick() {
    final c = _ctl;
    if (c == null) return;
    if (c.value.position >= _end && c.value.isPlaying) {
      c.pause();
      c.seekTo(_end);
    }
  }

  @override
  void dispose() {
    _ctl?.removeListener(_onTick);
    _ctl?.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final c = _ctl;
    if (c == null) return;
    if (c.value.isPlaying) {
      await c.pause();
      return;
    }
    if (c.value.position < _start || c.value.position >= _end) {
      await c.seekTo(_start);
    }
    await c.play();
  }

  Future<void> _setStart(Duration d) async {
    final c = _ctl;
    if (c == null) return;
    final v = _clampDur(
        d, Duration.zero, _end - const Duration(milliseconds: 1000));
    setState(() => _start = v);
    await c.pause();
    await c.seekTo(v);
  }

  Future<void> _setEnd(Duration d) async {
    final c = _ctl;
    if (c == null) return;
    final v = _clampDur(
        d, _start + const Duration(milliseconds: 1000), c.value.duration);
    setState(() => _end = v);
    await c.pause();
    await c.seekTo(v);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final ready = _initialized && ctl != null && ctl!.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
        centerTitle: true,
        title: const Text('修剪长度',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ready
                    ? AspectRatio(
                        aspectRatio: ctl!.value.aspectRatio,
                        child: VideoPlayer(ctl!),
                      )
                    : const CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            if (ready) ...[
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: ctl!,
                builder: (context, v, _) {
                  final dur = v.duration;
                  final totalMs =
                      dur.inMilliseconds.clamp(1, 1 << 30).toDouble();
                  String fmt(Duration d) {
                    final m =
                        d.inMinutes.remainder(60).toString().padLeft(2, '0');
                    final s =
                        d.inSeconds.remainder(60).toString().padLeft(2, '0');
                    return '$m:$s';
                  }

                  return Column(
                    children: [
                      // 播放控制行
                      Row(
                        children: [
                          Expanded(
                            child: IconButton(
                              onPressed: _togglePlay,
                              icon: Icon(
                                v.isPlaying
                                    ? Icons.pause_circle_outline
                                    : Icons.play_circle_outline,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          ),
                          Text('${fmt(v.position)} / ${fmt(dur)}',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.white70)),
                        ],
                      ),
                      // 修剪轨道：高亮区间 + 起点/终点手柄（拖动设定）
                      LayoutBuilder(builder: (context, box) {
                        final w = box.maxWidth;
                        final trackH = 44.0;
                        final leftX = _start.inMilliseconds / totalMs * w;
                        final rightX = _end.inMilliseconds / totalMs * w;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          child: SizedBox(
                            height: trackH,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                // 底轨
                                Positioned(
                                  top: trackH / 2 - 2,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                      height: 4, color: Colors.white24),
                                ),
                                // 保留区间高亮
                                Positioned(
                                  top: trackH / 2 - 3,
                                  left: leftX,
                                  width: (rightX - leftX)
                                      .clamp(2.0, w - leftX),
                                  child: Container(height: 6, color: accent),
                                ),
                                // 视频当前进度指示
                                Positioned(
                                  top: trackH / 2 - 6,
                                  left: (v.position.inMilliseconds / totalMs * w)
                                      .clamp(0.0, w - 8),
                                  child: Container(
                                    width: 4,
                                    height: 12,
                                    color: Colors.white,
                                  ),
                                ),
                                // 起点/终点手柄（触摸热区放大）
                                _trimHandle(trackH, leftX, true, w, totalMs),
                                _trimHandle(trackH, rightX, false, w, totalMs),
                              ],
                            ),
                          ),
                        );
                      }),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                            '保留 ${_fmt(_end - _start)}（起点 ${_fmt(_start)} ～ 终点 ${_fmt(_end)}），拖动手柄调整',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white70)),
                      ),
                    ],
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.pop(context, (start: _start, end: _end)),
                    child: const Text('下一步：圈选画面',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 起点/终点手柄：白竖条＋触摸热区，横向拖动改区间。
  Widget _trimHandle(
      double trackH, double x, bool isStart, double trackW, double totalMs) {
    return Positioned(
      left: (x - 14).clamp(0.0, trackW - 28),
      top: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) {
          final ms =
              ((x + d.delta.dx).clamp(0.0, trackW) / trackW * totalMs).round();
          final dur = Duration(milliseconds: ms);
          isStart ? _setStart(dur) : _setEnd(dur);
        },
        child: Container(
          width: 28,
          height: trackH,
          alignment: Alignment.center,
          child: Container(
            width: 4,
            height: trackH - 8,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

/// 直拍流程第一步入口：选完视频 → 修剪长度 →（返回区间）→ 圈选框编辑。
Future<({Duration start, Duration end})?> pushFancamTrim(
    BuildContext context, PickedSource source) {
  return Navigator.push<({Duration start, Duration end})>(
    context,
    AppRoute(builder: (_) => TrimPage(source: source)),
  );
}
