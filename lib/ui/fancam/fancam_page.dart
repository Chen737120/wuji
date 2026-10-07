import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../editing/crop_box.dart';
import '../../editing/keyframes.dart';
import '../../editing/media_source_picker.dart';
import 'fancam_preview_page.dart';
import '../widgets/app_route.dart';
import '../widgets/film_strip.dart';

/// 舞蹈直拍页（规格 §5.1）：画面最大化＋比例锁定框＋关键帧轨道。
/// 手势分工：单指拖框体=移动；拖翠芽角柄（右下）=缩放（比例锁定）；
/// 双指捏合=缩放预览（仅查看 1×~4×）；双击=复位预览；点画面=隐藏控件。
class FancamPage extends StatefulWidget {
  const FancamPage({
    super.key,
    required this.source,
    this.trimStart = Duration.zero,
    this.trimEnd,
  });

  final PickedSource source;

  /// 修剪区间（来自修剪长度页）；关键帧时间轴以修剪后（起点=0）计。
  final Duration trimStart;
  final Duration? trimEnd;

  Duration get trimmedEnd =>
      trimEnd ?? source.duration ?? const Duration(seconds: 10);

  @override
  State<FancamPage> createState() => _FancamPageState();
}

class _FancamPageState extends State<FancamPage> {
  VideoPlayerController? _ctl;
  String? _error;
  bool _controlsVisible = true;
  String _ratio = '9:16';

  KeyframeTrack? _track;
  CropBox _box = const CropBox(cx: 0.5, cy: 0.5, w: 0.5, h: 0.5);

  // 源视频真实尺寸（导出 crop 的像素域基准）。v1.5.6 前硬编码 1080×1920，
  // 横屏视频 crop 超界 → FFmpeg "Invalid too big size" → 直拍导出必败
  int _srcW = 0;
  int _srcH = 0;

  // 预览缩放（双指，仅查看）
  double _previewScale = 1.0;
  Offset _previewPan = Offset.zero;

  // 手势状态
  _GestureMode? _mode;
  Offset _panStart = Offset.zero;
  CropBox _boxAtStart = const CropBox(cx: 0.5, cy: 0.5, w: 0.5, h: 0.5);

  VideoPlayerController? get ctl => _ctl;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final ctl = VideoPlayerController.file(File(widget.source.path));
      await ctl.initialize();
      if (!mounted) {
        await ctl.dispose();
        return;
      }
      ctl.addListener(_onTick);
      setState(() {
        _ctl = ctl;
        // 关键帧轨道 = 修剪后时间轴（起点=0）
        _track = KeyframeTrack(
            duration: widget.trimmedEnd - widget.trimStart);
        _box = CropBox.centered(_ratio);
        _track!.reset(_box);
        // video_player 的 size 已应用 rotation，与 FFmpeg 默认 autorotate
        // 后滤镜看到的尺寸一致，可作为 crop 像素域基准
        _srcW = ctl.value.size.width.round();
        _srcH = ctl.value.size.height.round();
      });
      await ctl.seekTo(widget.trimStart);
      // 不自动播放：先停在修剪起点让用户选区/加关键帧，控制条可手动播放
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '视频加载失败');
    }
  }

  /// 播放超出修剪终点时自动停住（保留区间外不可播）。
  void _onTick() {
    final c = _ctl;
    if (c == null || !c.value.isPlaying) return;
    if (c.value.position >= widget.trimmedEnd) {
      c.pause();
      c.seekTo(widget.trimmedEnd);
    }
  }

  /// 关键帧时刻 = 播放位置 - 修剪起点（轨道时间轴）。
  Duration get _trackTime =>
      (_ctl?.value.position ?? Duration.zero) - widget.trimStart;

  // 串行 seek（2026-10-07 需求 #9）：拖动胶片条时高频 seekTo 会排队堆积、
  // 画面只在松手后定格——这里保证同一时刻只有一个 seek 在跑，最新的目标
  // 位置在上一帧渲染完成后立刻执行，画面持续跟随
  Duration? _pendingSeek;
  bool _seeking = false;

  Future<void> _seekSmooth(Duration t) async {
    final c = _ctl;
    if (c == null) return;
    _pendingSeek = t;
    if (_seeking) return;
    _seeking = true;
    try {
      while (_pendingSeek != null) {
        final target = _pendingSeek!;
        _pendingSeek = null;
        await c.seekTo(target);
      }
    } finally {
      _seeking = false;
    }
  }


  void _setRatio(String r) {
    setState(() {
      _ratio = r;
      if (r == '自由') return; // 自由：保持当前框，角柄可独立改宽高
      // 比例切换：保持中心，按新比例重设框（h 不变，w=h*newAspect）
      final newAspect = _ratioAspect(r);
      var w = _box.h * newAspect;
      var h = _box.h;
      if (w > 1) {
        w = 1;
        h = w / newAspect;
      }
      _box = CropBox(cx: _box.cx, cy: _box.cy, w: w, h: h).clamped();
      _track!.upsert(_trackTime, _box);
    });
  }

  double _ratioAspect(String r) {
    switch (r) {
      case '1:1':
        return 1;
      case '9:16':
        return 9 / 16;
      case '自由':
        return 3 / 4; // 自由模式预览框仍用 3:4 基准（框可任意拖）
      default:
        return 3 / 4;
    }
  }

  void _addKeyframe() {
    final t = _trackTime;
    final ok = _track!.upsert(t, _box);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('关键帧已达 10 个上限。素材移动过大，建议分段处理')));
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ctl?.removeListener(_onTick);
    _ctl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      body: _error != null
          ? SafeArea(
              child: Center(
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white70)),
                  const SizedBox(height: 10),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('返回',
                          style: TextStyle(color: Colors.white))),
                ],
              )),
            )
          : _body(context, accent),
    );
  }

  Widget _body(BuildContext context, Color accent) {
    final ctl = _ctl;
    return Stack(
      children: [
        // 视频层（最大化 + 预览缩放/平移）
        Positioned.fill(
          child: GestureDetector(
            onTap: () => setState(() => _controlsVisible = !_controlsVisible),
            onDoubleTap: () => setState(() {
              _previewScale = 1.0;
              _previewPan = Offset.zero;
            }),
            onScaleStart: (d) {
              if (d.pointerCount >= 2) {
                _mode = _GestureMode.previewScale;
                _panStart = Offset(_previewScale, _previewPan.distance);
              }
            },
            onScaleUpdate: (d) {
              if (_mode == _GestureMode.previewScale && d.pointerCount >= 2) {
                setState(() {
                  _previewScale =
                      (d.scale * _previewScale / (_panStart.dx == 0 ? 1 : _panStart.dx))
                          .clamp(1.0, 4.0);
                });
              }
            },
            onScaleEnd: (_) => _mode = null,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..translateByDouble(_previewPan.dx, _previewPan.dy, 0, 1)
                ..scaleByDouble(_previewScale, _previewScale, 1, 1),
              child: Center(
                child: ctl != null && ctl.value.isInitialized
                    ? AspectRatio(
                        aspectRatio: ctl.value.aspectRatio,
                        child: VideoPlayer(ctl),
                      )
                    : const SizedBox.expand(),
              ),
            ),
          ),
        ),
        // 框叠加层（单指拖框/角柄）
        if (ctl != null && ctl.value.isInitialized)
          Positioned.fill(
            child: GestureDetector(
              onPanStart: (d) {
                _mode = _hitTest(d.localPosition, ctl.value.aspectRatio);
                _panStart = d.localPosition;
                _boxAtStart = _box;
              },
              onPanUpdate: (d) {
                if (_mode == null) return;
                final videoBox = _videoRect(ctl.value.aspectRatio);
                final dx =
                    (d.localPosition.dx - _panStart.dx) / videoBox.width;
                final dy =
                    (d.localPosition.dy - _panStart.dy) / videoBox.height;
                setState(() {
                  switch (_mode!) {
                    case _GestureMode.move:
                      _box = _boxAtStart
                          .movedBy(Offset(dx, dy))
                          .clamped();
                    case _GestureMode.resize:
                      if (_ratio == '自由') {
                        // 自由模式：宽高随拖动独立变化
                        var w = (_boxAtStart.w + dx * 2).clamp(0.1, 1.0);
                        var h = (_boxAtStart.h + dy * 2).clamp(0.1, 1.0);
                        _box = CropBox(
                            cx: _boxAtStart.cx + dx / 2,
                            cy: _boxAtStart.cy + dy / 2,
                            w: w,
                            h: h).clamped();
                      } else {
                        // 角柄：取位移在框宽方向上的投影作为缩放
                        final grow = (dx > dy ? dx : dy) * 2;
                        _box = _boxAtStart.scaledBy(1 + grow).clamped();
                      }
                    default:
                      break;
                  }
                });
              },
              onPanEnd: (_) {
                _mode = null;
                _track!.upsert(_trackTime, _box);
              },
              child: CustomPaint(
                painter: _CropOverlayPainter(
                    box: _box, aspect: ctl.value.aspectRatio, accent: accent),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        // 控件层（点画面切换）
        if (_controlsVisible) ...[
          // 顶部返回
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context)),
            ),
          ),
          // 底部一条：比例 chips + 关键帧轨道 + 主按钮
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 比例 chips
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final r in ['9:16', '3:4', '1:1', '自由'])
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text(r,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                              selected: _ratio == r,
                              selectedColor: accent,
                              backgroundColor: Colors.black45,
                              onSelected: (_) => _setRatio(r),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 播放/暂停 + 胶片进度条（2026-10-07 需求 #8：胶片条
                    // 移至原横线轨道位置，关键帧圆点叠加在胶片条上；
                    // seek 串行化让拖动中画面实时跟随——需求 #9）
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: _ctl!,
                      builder: (context, v, _) => Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: () async {
                              final c = _ctl;
                              if (c == null) return;
                              if (c.value.isPlaying) {
                                await c.pause();
                              } else {
                                if (c.value.position < widget.trimStart ||
                                    c.value.position >= widget.trimmedEnd) {
                                  await c.seekTo(widget.trimStart);
                                }
                                await c.play();
                              }
                              setState(() {});
                            },
                            icon: Icon(
                                v.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white),
                          ),
                          Expanded(
                            child: FilmStrip(
                              videoPath: widget.source.path,
                              duration: v.duration,
                              position: v.position,
                              onSeek: _seekSmooth,
                              accent: accent,
                              height: 52,
                              stripCount: 14,
                              keyframes: [
                                for (final f in _track!.frames) f.t,
                              ],
                              onKeyframeTap: (t) =>
                                  _seekSmooth(t + widget.trimStart),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        TextButton(
                            onPressed: _addKeyframe,
                            child: const Text('＋添加关键帧',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.white))),
                        const Spacer(),
                        TextButton(
                            onPressed: () {
                              setState(() {
                                _box = CropBox.centered(_ratio);
                                _track!.reset(_box);
                              });
                            },
                            child: const Text('还原',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.white70))),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 8),
                          ),
                          onPressed: () {
                          if (_srcW <= 0 || _srcH <= 0) return;
                          Navigator.push(
                            context,
                            AppRoute(
                                builder: (_) => FancamPreviewPage(
                                    sourcePath: widget.source.path,
                                    track: _track!,
                                    srcW: _srcW,
                                    srcH: _srcH,
                                    ratio: _ratio,
                                    keyframeCount: _track!.frames.length,
                                    trimStart: widget.trimStart,
                                    trimEnd: widget.trimmedEnd)),
                          );
                        },
                          child: const Text('下一步',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Rect _videoRect(double aspect) {
    // 视频在屏幕内实际渲染区（AspectRatio 居中）——近似：以屏宽/高算
    final screen = MediaQuery.sizeOf(context);
    double w = screen.width, h = screen.width / aspect;
    if (h > screen.height) {
      h = screen.height;
      w = screen.height * aspect;
    }
    final left = (screen.width - w) / 2;
    final top = (screen.height - h) / 2;
    return Rect.fromLTWH(left, top, w, h);
  }

  _GestureMode? _hitTest(Offset pos, double aspect) {
    final videoBox = _videoRect(aspect);
    final boxPix = Rect.fromLTWH(
        videoBox.left + _box.left * videoBox.width,
        videoBox.top + _box.top * videoBox.height,
        _box.w * videoBox.width,
        _box.h * videoBox.height);
    // 角柄命中：右下角 36px 方块
    final handle = Rect.fromCenter(
        center: boxPix.bottomRight,
        width: 36,
        height: 36);
    if (handle.contains(pos)) return _GestureMode.resize;
    if (boxPix.contains(pos)) return _GestureMode.move;
    return null;
  }
}

enum _GestureMode { move, resize, previewScale }

/// 裁剪叠加层：框外半透明遮罩＋翠芽边框＋右下角柄。
class _CropOverlayPainter extends CustomPainter {
  _CropOverlayPainter({
    required this.box,
    required this.aspect,
    required this.accent,
  });

  final CropBox box; // 归一化
  final double aspect; // 视频宽高比
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    // 视频在画布中的实际渲染区（AspectRatio 居中）
    double vw = size.width, vh = size.width / aspect;
    if (vh > size.height) {
      vh = size.height;
      vw = size.height * aspect;
    }
    final vx = (size.width - vw) / 2;
    final vy = (size.height - vh) / 2;

    final bx = vx + box.left * vw;
    final by = vy + box.top * vh;
    final bw = box.w * vw;
    final bh = box.h * vh;
    final boxRect = Rect.fromLTWH(bx, by, bw, bh);

    // 框外遮罩（even-odd 挖洞）
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(boxRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black54);

    // 翠芽边框
    canvas.drawRect(
        boxRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = accent);

    // 右下角柄
    final handle = Rect.fromCenter(
        center: boxRect.bottomRight, width: 22, height: 22);
    canvas.drawCircle(
        handle.center, 11, Paint()..color = accent);
    canvas.drawCircle(
        handle.center,
        11,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter old) =>
      old.box != box || old.aspect != aspect;
}
