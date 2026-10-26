import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../../editing/crop_box.dart';
import '../../editing/fancam_follow_controller.dart';
import '../../editing/fancam_tracker.dart';
import '../../editing/ffmpeg_probe.dart';
import '../../editing/keyframes.dart';
import '../../editing/media_source_picker.dart';
import '../../editing/mosaic_region.dart';
import '../../editing/trim_timeline.dart';
import 'fancam_preview_page.dart';
import 'preview_geometry.dart';
import '../mosaic/mosaic_editor_page.dart';
import '../widgets/app_route.dart';
import '../widgets/film_strip.dart';

/// 编辑模式（Task 4）：手动打点＝现有功能原样保留；自动跟踪＝点选目标→
/// 逐帧轨迹→拖框插锚点纠正（spec §3）。
enum FancamEditMode { manual, follow }

/// 模式开关（ruling 6：抽成顶层小 widget 以便单测——FancamPage 全页测试受
/// video_player 平台通道限制，代码库无 fancam_page 测试先例；禁止为可测性
/// 大改页面结构，故只外提本开关，回调与选中态在 test/ui 测）。
class FancamModeSwitch extends StatelessWidget {
  const FancamModeSwitch({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final FancamEditMode mode;
  final ValueChanged<FancamEditMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<FancamEditMode>(
      segments: const [
        ButtonSegment(value: FancamEditMode.manual, label: Text('手动')),
        ButtonSegment(value: FancamEditMode.follow, label: Text('自动跟踪')),
      ],
      selected: {mode},
      onSelectionChanged: (s) => onChanged(s.first),
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        side: WidgetStatePropertyAll(BorderSide(color: Colors.white24)),
        backgroundColor: WidgetStatePropertyAll(Colors.black45),
        foregroundColor: WidgetStatePropertyAll(Colors.white),
      ),
    );
  }
}

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

  // 打码区域（会话内存，不落库；空列表＝无打码直拍的合法状态，spec §3.2）
  List<MosaicRegion> _mosaicRegions = [];

  // ---- 自动跟踪（Task 4，spec §3）----
  FancamEditMode _editMode = FancamEditMode.manual; // 默认手动（ruling 1）
  FollowSession? _session; // 跟踪会话（轨迹＋锚点）；null=未跟踪（导出走手动路径）
  TrackingRun? _tracking; // 进行中的跟踪运行（取消/释放用）
  final ValueNotifier<double> _trackProgress = ValueNotifier(0); // 模态进度
  double _fps = 30.0; // probeMedia 探测（video_player 无 fps）；失败兜底 30（ruling 2）
  // fps 探测 Future（F9）：init 起跑不阻塞首屏；点选跟踪解码前 await 它，
  // 避免 25/60fps 源在探测完成前按 30fps 建轨迹导致时间轴错位。
  Future<void>? _fpsProbe;

  // 源视频真实尺寸（导出 crop 的像素域基准）。v1.5.6 前硬编码 1080×1920，
  // 横屏视频 crop 超界 → FFmpeg "Invalid too big size" → 直拍导出必败
  int _srcW = 0;
  int _srcH = 0;

  // 预览缩放（双指，仅查看）
  double _previewScale = 1.0;
  Offset _previewPan = Offset.zero;
  // 捏合起点基准（F10）：d.scale 自手势起累计，直接乘当前 _previewScale 会
  // 复利放大（从 2× 起手第一下会跳到 ~1.1×）；与 player/mosaic 同口径。
  double? _previewScaleBase;

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
        // video_player 的 size 已应用 rotation，与 FFmpeg 默认 autorotate
        // 后滤镜看到的尺寸一致，可作为 crop 像素域基准。
        // 顺序铁律：先赋 _srcW/_srcH 再算默认框——反序会让
        // CropBox.centered 在 0 尺寸上产出 NaN 框写进轨道，预览页
        // 导出参数单 toInt 抛 Infinity or NaN（冒烟 d26 红屏，缺陷 1
        // 修复后暴露的掩盖问题）
        _srcW = ctl.value.size.width.round();
        _srcH = ctl.value.size.height.round();
        // 关键帧轨道 = 修剪后时间轴（起点=0）
        _track = KeyframeTrack(
            duration: widget.trimmedEnd - widget.trimStart);
        _box = CropBox.centered(_ratio, srcW: _srcW, srcH: _srcH);
        _track!.reset(_box);
      });
      await ctl.seekTo(widget.trimStart);
      // 不自动播放：先停在修剪起点让用户选区/加关键帧，控制条可手动播放
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '视频加载失败');
    }
    // fps 探测只服务跟踪/重建会话，不阻塞首屏；存 Future 供点选时等待（F9）
    _fpsProbe = _probeFps();
  }

  /// 跟踪帧率探测（ruling 2）：video_player 的 value 无 fps，用 ffprobe 异步
  /// 探测缓存一次；失败保持兜底 30.0。
  Future<void> _probeFps() async {
    try {
      final info = await probeMedia(widget.source.path);
      if (info != null && info.fps > 0) _fps = info.fps;
    } catch (_) {
      // 兜底 30.0
    }
  }

  /// 播放超出修剪终点时自动停住（保留区间外不可播）。
  /// 自动跟踪会话存在时顺带逐帧刷新跟随框（ruling 3：复用 player listener
  /// 的 setState 机制；暂停/seek 后 listener 仍会触发一次，框位置同步）。
  void _onTick() {
    final c = _ctl;
    if (c == null) return;
    if (_editMode == FancamEditMode.follow && _session != null) {
      setState(() {});
    }
    if (!c.value.isPlaying) return;
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
      // 比例切换：保持中心，按新比例重设框。比例锁定是像素域语义，
      // 归一化 w/h 须乘 srcH/srcW 修正（w×源宽、h×源高基准不同）
      final k = (_srcW <= 0 || _srcH <= 0) ? 1.0 : _srcH / _srcW;
      final newAspect = _ratioAspect(r) * k;
      var w = _box.h * newAspect;
      var h = _box.h;
      if (w > 1) {
        w = 1;
        h = w / newAspect;
      }
      _box = CropBox(cx: _box.cx, cy: _box.cy, w: w, h: h).clamped();
      if (_editMode == FancamEditMode.follow && _session != null) {
        // 自动模式：比例变化＝改跟随框尺寸（重建会话保留锚点），不写关键帧
        _session = _session!.withBox(_box,
            fps: _fps, duration: widget.trimmedEnd - widget.trimStart);
      } else {
        _track!.upsert(_trackTime, _box);
      }
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

  /// 「＋打码」：先暂停（brief Step 4），进内嵌打码编辑器（AppRoute 项目
  /// 转场惯例）。「完成」pop 回区域列表更新；顶部返回按钮 pop 不带回传
  /// （null）→ 保持原区域不变（mosaic_editor_page.dart 返回按钮注释）。
  /// 区域关键帧时间轴＝修剪后时间轴（durationMs 相对修剪起点，与 -ss
  /// 前置语义一致）。
  Future<void> _openMosaicEditor() async {
    if (_srcW <= 0 || _srcH <= 0) return;
    await _ctl?.pause();
    if (!mounted) return;
    final result = await Navigator.push<List<MosaicRegion>>(
      context,
      AppRoute(
        builder: (_) => MosaicEditorPage(
          srcPath: widget.source.path,
          srcW: _srcW,
          srcH: _srcH,
          durationMs: (widget.trimmedEnd - widget.trimStart).inMilliseconds,
          // 内嵌编辑器时间轴＝修剪后时间轴：编辑器内部 track 时间 0 = 源
          // trimStart，播放器/快照 seek 加此偏移（v1.5.26 走查 F1）
          trimStart: widget.trimStart,
          // 深拷贝隔离：MosaicEditorState 只浅拷列表，编辑器内拖框/改效果
          // 会原地写 MosaicRegion 与 KeyframeTrack——若共享对象，返回按钮
          // 「放弃编辑」后原区域仍带着改动，null=不变须对象级隔离才成立
          initialRegions: _cloneRegions(_mosaicRegions),
          embedded: true,
        ),
      ),
    );
    if (result != null) {
      setState(() => _mosaicRegions = result);
    }
  }

  /// 深拷贝打码区域（进编辑器前隔离，见 [_openMosaicEditor] 注释）。
  List<MosaicRegion> _cloneRegions(List<MosaicRegion> src) =>
      [for (final r in src) _cloneRegion(r)];

  MosaicRegion _cloneRegion(MosaicRegion r) {
    final track = KeyframeTrack(duration: r.track.duration);
    for (final f in r.track.frames) {
      track.upsert(f.t, f.box);
    }
    return MosaicRegion(id: r.id, track: track)
      ..effect = r.effect
      ..strength = r.strength;
  }

  /// 叠加框（painter/_hitTest 共用）：手动＝_box（现状）；自动且有会话＝
  /// 轨迹在当前轨道时刻的跟随框（拖动中显示拖动框——onPanStart 已用跟随框
  /// 快照初始化 _box，松手后由锚点混合接管）。
  CropBox get _displayBox {
    if (_editMode == FancamEditMode.follow && _session != null && _mode == null) {
      return followBoxAt(_session!, _trackTime);
    }
    return _box;
  }

  /// 模式切换（ruling 1/4）：切回手动＝丢弃 session（轨迹/锚点），_track
  /// 关键帧原样保留，叠加框回 _box；切入自动且尚无轨迹时轻提示点选（spec §3.1）。
  void _setEditMode(FancamEditMode m) {
    setState(() {
      _editMode = m;
      if (m == FancamEditMode.manual) {
        _session = null;
        _tracking?.cancel(); // 跟踪在途（进度框被系统返回键关掉的场景）直接终止
      }
    });
    if (m == FancamEditMode.follow && _session == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('点击画面中的人物开始自动跟踪')));
    }
  }

  /// 自动模式点画面（onTapUp）＝选定/重选跟踪目标（spec §3.1，位置无关）。
  /// 已有会话先确认（重选清除锚点）；确认后走完整跟踪流程。
  Future<void> _onTapSelectTarget(
      TapUpDetails d, VideoPlayerController ctl) async {
    if (_tracking != null) return; // 跟踪进行中忽略（模态进度框已挡住多数路径）
    final videoBox = _videoRect(ctl.value.aspectRatio);
    if (videoBox.width <= 0 || videoBox.height <= 0) return;
    // 预览可能被捏合放大：屏幕点先逆变换回视频内容坐标再归一化（F10）
    final norm = previewNormalizedPoint(
        d.localPosition, videoBox, _previewScale, _previewPan);
    final cx = norm.dx;
    final cy = norm.dy;
    if (_session != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dlgCtx) => AlertDialog(
          title: const Text('重新跟踪'),
          content: const Text('重新跟踪将清除现有锚点'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dlgCtx, false),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(dlgCtx, true),
                child: const Text('重新跟踪')),
          ],
        ),
      );
      if (ok != true) return;
      if (!mounted) return;
      setState(() => _session = null); // 锚点/轨迹一并丢弃（ruling 3）
    }
    await _startFollowTracking(cx, cy);
  }

  /// 自动跟踪主流程（ruling 2）：暂停 → 解码 raw（`<cache>/wuji-track/`）→
  /// Isolate 跟踪（模态进度＋可取消）→ 建 FollowSession → recompute →
  /// lossHint 一次性提示。raw 用后即删：正常完成由 isolate 侧 finally 删、
  /// 取消由 cancel 删，此处对 decode 失败残留兜底（双删吞异常）。
  Future<void> _startFollowTracking(double cxNorm, double cyNorm) async {
    final ctl = _ctl;
    if (ctl == null || !ctl.value.isInitialized || _srcW <= 0 || _srcH <= 0) {
      return;
    }
    await ctl.pause();
    if (!mounted) return;
    // 探测先完成再解码（F9）：_probeFps 内部已 catch，失败保持兜底 30
    await (_fpsProbe ??= _probeFps());
    if (!mounted) return;
    final trackDur = widget.trimmedEnd - widget.trimStart;
    var userCancelled = false;
    // 取消唯一入口（取消按钮）：decode 期 _tracking 尚为 null（no-op），
    // 由 decode 后的 userCancelled 短路兜住；跟踪期 run.cancel() 即刻终止
    void cancelTracking() {
      userCancelled = true;
      _tracking?.cancel();
    }

    // 进度模态与 main.dart 导出模态同款防线（评审 Important #1）：
    // ① PopScope(canPop:false)——barrierDismissible 只挡点击，系统返回键
    //    仍会关框；关框后跟踪继续，完成时 finally 的 pop 会误弹 FancamPage
    //    （用户被踢回上一页、编辑状态全丢）。返回键不关框，取消走「取消」按钮。
    // ② dialogOpen 标志——finally 只在本模态未关闭时 pop，双保险。
    var dialogOpen = true;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => PopScope(
        canPop: false, // 跟踪中不可返回键关框；取消走「取消」按钮（同 main.dart 导出模态）
        child: AlertDialog(
          title: const Text('正在跟踪目标'),
          content: ValueListenableBuilder<double>(
            valueListenable: _trackProgress,
            builder: (context, p, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: p <= 0 ? null : p.clamp(0.0, 1.0)),
                const SizedBox(height: 10),
                Text('${(p * 100).round()}%',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          actions: [
            TextButton(
              // 只 cancel（done 完成 null / decode 后短路 → 本流程 finally 收尾关框，
              // 留在自动模式）
              onPressed: cancelTracking,
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    ).whenComplete(() => dialogOpen = false));
    _trackProgress.value = 0;
    String? rawPath;
    try {
      final tmp = await getTemporaryDirectory();
      rawPath =
          '${tmp.path}/wuji-track/track-${DateTime.now().millisecondsSinceEpoch}.raw';
      await decodeRawFrames(
        videoPath: widget.source.path,
        ss: widget.trimStart,
        duration: trackDur,
        fps: _fps,
        outPath: rawPath,
      );
      if (!mounted) return;
      if (userCancelled) {
        // decode 期取消（评审 Important #2）：解码本身不可中断（数十秒内完
        // 成），但取消后不得再启动跟踪跑完全程；raw 由 finally 兜底删除，
        // 不写 session（清目标、留在自动模式，与跟踪期取消同语义）
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('跟踪已取消')));
        return;
      }
      final run = startTracking(
        rawPath: rawPath,
        initCxNorm: cxNorm,
        initCyNorm: cyNorm,
        srcW: _srcW,
        srcH: _srcH,
        fps: _fps,
        onProgress: (p) => _trackProgress.value = p,
      );
      _tracking = run;
      final pts = await run.done;
      if (!mounted || _editMode != FancamEditMode.follow) {
        return; // 跟踪期间页面退出或已切回手动 → 丢弃结果（session 不写入）
      }
      if (pts == null || pts.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text(userCancelled ? '跟踪已取消' : '跟踪失败，请重试')));
        }
        return;
      }
      if (!mounted) return;
      final session = FollowSession(
          points: pts, box: _box, srcW: _srcW, srcH: _srcH);
      session.recompute(fps: _fps, duration: trackDur);
      setState(() => _session = session);
      final hint = session.lossHint(); // 一次性提示（spec §2.1 / ruling 2）
      if (hint != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(hint)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('跟踪失败：$e')));
      }
    } finally {
      _tracking = null;
      _trackProgress.value = 0;
      if (rawPath != null) {
        try {
          final f = File(rawPath);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
      if (mounted && dialogOpen) {
        // 只在本模态仍在栈上时 pop（dialogOpen 由 whenComplete 置 false）——
        // 否则 canPop() 会 pop 掉 FancamPage 本身（评审 Important #1）。
        // 取消按钮只 cancel 不 pop，关框统一收口在此。
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) nav.pop();
      }
    }
  }

  @override
  void dispose() {
    _tracking?.cancel(); // 页面退出终止跟踪（isolate kill＋删 raw）
    _trackProgress.dispose();
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
        // 视频层（最大化 + 预览缩放/平移）。手动模式点按=切换控件（现状）；
        // 自动模式点按=选定/重选跟踪目标（spec §3.1，onTapUp 取落点坐标）
        Positioned.fill(
          child: GestureDetector(
            onTap: _editMode == FancamEditMode.manual
                ? () => setState(() => _controlsVisible = !_controlsVisible)
                : null,
            onTapUp: _editMode == FancamEditMode.follow &&
                    ctl != null &&
                    ctl.value.isInitialized
                ? (d) => unawaited(_onTapSelectTarget(d, ctl))
                : null,
            onDoubleTap: () => setState(() {
              _previewScale = 1.0;
              _previewPan = Offset.zero;
            }),
            onScaleStart: (d) {
              if (d.pointerCount >= 2) {
                _mode = _GestureMode.previewScale;
                _previewScaleBase = _previewScale;
              }
            },
            onScaleUpdate: (d) {
              if (_mode == _GestureMode.previewScale && d.pointerCount >= 2) {
                setState(() {
                  _previewScale =
                      ((_previewScaleBase ?? _previewScale) * d.scale)
                          .clamp(1.0, 4.0);
                });
              }
            },
            onScaleEnd: (_) {
              _mode = null;
              _previewScaleBase = null;
            },
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
        // 框叠加层（单指拖框/角柄）。自动模式：拖框体＝当时刻插锚（onPanEnd），
        // 角柄＝改跟随框尺寸（withBox 重建会话）；手动模式行为逐字节不变
        if (ctl != null && ctl.value.isInitialized)
          Positioned.fill(
            child: GestureDetector(
              onPanStart: (d) {
                // 先取拖动前显示框（此时 _mode 尚为 null：手动=_box，自动=跟随框）
                final startBox = _displayBox;
                _mode = _hitTest(d.localPosition, ctl.value.aspectRatio);
                _panStart = d.localPosition;
                _boxAtStart = startBox;
                if (_editMode == FancamEditMode.follow &&
                    _session != null &&
                    _mode != null) {
                  _box = startBox; // 拖动直接操作跟随框快照（尺寸=session.box）
                }
              },
              onPanUpdate: (d) {
                if (_mode == null) return;
                final videoBox = _videoRect(ctl.value.aspectRatio);
                // 屏幕位移 → 视频内容归一化位移：预览放大后同一屏幕位移
                // 对应的内容位移按 scale 缩小（与点选逆变换同源，F10）
                final dx = (d.localPosition.dx - _panStart.dx) /
                    (videoBox.width * _previewScale);
                final dy = (d.localPosition.dy - _panStart.dy) /
                    (videoBox.height * _previewScale);
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
                final gesture = _mode;
                _mode = null;
                if (_editMode == FancamEditMode.follow && _session != null) {
                  final dur = widget.trimmedEnd - widget.trimStart;
                  if (gesture == _GestureMode.resize) {
                    // 角柄缩放＝改跟随框尺寸（ruling 3，实现从简：右下柄生效）
                    setState(() => _session =
                        _session!.withBox(_box, fps: _fps, duration: dur));
                  } else if (gesture == _GestureMode.move) {
                    // 拖框体＝当时刻插锚（传拖后中心归一化值，spec §2.4 / ruling 3）
                    _session!.insertAnchor(_trackTime, cx: _box.cx, cy: _box.cy);
                    setState(() {});
                  }
                } else {
                  _track!.upsert(_trackTime, _box);
                }
              },
              child: CustomPaint(
                painter: _CropOverlayPainter(
                    box: _displayBox,
                    aspect: ctl.value.aspectRatio,
                    accent: accent,
                    viewScale: _previewScale,
                    viewPan: _previewPan),
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
          // 底部一条：比例 chips + 关键帧轨道 + 主按钮。
          // 初始化门（冒烟缺陷 1 根因）：首帧 build 时 _ctl/_track 均为
          // null（_init 异步），底条内 `valueListenable: _ctl!` 会立即抛
          // Null check 红屏（3/3 复现，堆栈 fancam_page.dart:707）。
          // _track 与 _ctl 在同一 setState 里赋值，ctl != null 即二者就绪。
          if (ctl != null)
            Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 模式开关（ruling 1：比例 chips 行上方；手动为默认且
                    // 手动模式页面行为与现状一致）
                    FancamModeSwitch(mode: _editMode, onChanged: _setEditMode),
                    const SizedBox(height: 6),
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
                              // 自动模式＝锚点时刻（ruling 3）；手动＝关键帧时刻（现状）。
                              // FilmStrip 的 duration/position 是源时间，轨道/锚点是
                              // track 时间——圆点统一换算为显示时间（F11）。
                              keyframes: displayKeyframeTimes(
                                (_editMode == FancamEditMode.follow &&
                                        _session != null)
                                    ? [for (final a in _session!.anchors) a.t]
                                    : [
                                        for (final f in _track!.frames) f.t,
                                      ],
                                widget.trimStart,
                              ),
                              // FilmStrip 回调已是显示（源）时间，直接 seek；
                              // 偏移只在这里加一次，禁止回调里再加 trimStart
                              onKeyframeTap: _seekSmooth,
                              // 锚点长按删除（自动模式；FilmStrip 可选回调，
                              // 手动模式不传＝现状零变化）——显示时间换回 track 时间
                              onKeyframeLongPress:
                                  (_editMode == FancamEditMode.follow &&
                                          _session != null)
                                      ? (t) => setState(() =>
                                          _session!.removeAnchor(
                                              trackTimeOfDisplay(
                                                  t, widget.trimStart)))
                                      : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        // ＋添加关键帧：自动模式下隐藏（锚点即语义，ruling 3；
                        // 切回手动恢复）
                        if (_editMode == FancamEditMode.manual)
                          TextButton(
                              onPressed: _addKeyframe,
                              child: const Text('＋添加关键帧',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.white))),
                        // ＋打码（内嵌编辑器入口；已配置区域数随按钮展示）
                        TextButton.icon(
                            onPressed: _openMosaicEditor,
                            icon: const Icon(Icons.blur_on,
                                size: 18, color: Colors.white),
                            label: Text(
                                '打码${_mosaicRegions.isEmpty ? '' : '(${_mosaicRegions.length})'}',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.white))),
                        const Spacer(),
                        TextButton(
                            onPressed: () {
                              setState(() {
                                _box = CropBox.centered(_ratio,
                                    srcW: _srcW, srcH: _srcH);
                                if (_editMode == FancamEditMode.follow &&
                                    _session != null) {
                                  // 自动模式：还原框尺寸（锚点保留）
                                  _session = _session!.withBox(_box,
                                      fps: _fps,
                                      duration:
                                          widget.trimmedEnd - widget.trimStart);
                                } else {
                                  _track!.reset(_box);
                                }
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
                          // 自动模式且有轨迹→带 session 走 sendcmd 导出（ruling 5）；
                          // 手动模式/自动未跟踪→follow=null 走手动路径（现状）
                          final follow = _editMode == FancamEditMode.follow
                              ? _session
                              : null;
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
                                    trimEnd: widget.trimmedEnd,
                                    regions: _mosaicRegions,
                                    mosaicRegionCount:
                                        _mosaicRegions.length,
                                    follow: follow)),
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
    // 命中检测用当前显示框（手动=_box；自动=跟随框）——onPanStart 调用时
    // _mode 尚为 null，_displayBox 即拖动前可见框；预览放大后框已映射到
    // 屏幕域，命中必须用同一映射（F10）
    final display = _displayBox;
    final videoBox = _videoRect(aspect);
    final contentBox = Rect.fromLTWH(
        videoBox.left + display.left * videoBox.width,
        videoBox.top + display.top * videoBox.height,
        display.w * videoBox.width,
        display.h * videoBox.height);
    final boxPix = previewMappedRect(
        contentBox, videoBox, _previewScale, _previewPan);
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
    this.viewScale = 1,
    this.viewPan = Offset.zero,
  });

  final CropBox box; // 归一化
  final double aspect; // 视频宽高比
  final Color accent;

  /// 预览查看变换（F10）：框 rect 与视频层同一映射；mask 仍铺满画布。
  final double viewScale;
  final Offset viewPan;

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

    final contentBox = Rect.fromLTWH(
        vx + box.left * vw, vy + box.top * vh, box.w * vw, box.h * vh);
    // 框随预览缩放/平移（与点选逆变换、视频 Transform 同源）
    final boxRect = previewMappedRect(
        contentBox, Rect.fromLTWH(vx, vy, vw, vh), viewScale, viewPan);

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
      old.box != box ||
      old.aspect != aspect ||
      old.viewScale != viewScale ||
      old.viewPan != viewPan;
}
