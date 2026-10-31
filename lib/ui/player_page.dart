import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../services/abs_path_cache.dart';
import '../services/archive_fs.dart' show MediaPathResolver;
import '../theme.dart';
import 'widgets/save_to_gallery_button.dart';

const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// T10 控制层深色毛玻璃材质（spec §3）：rgba(24,24,24,.55)＋blur 20。
const Color _glassBarColor = Color(0x8C181818);

/// 视频基准渲染尺寸：AspectRatio 在视口松约束下的实际布局尺寸。
/// 钳位必须用它而非视口尺寸——视频未填满的轴用视口口径会把画面拖出
/// 屏外（2026-10-25 评审 Important 修正，见 spec §3.2）。
Size videoBaseSize(Size viewport, double aspect) {
  final w = math.min(viewport.width, viewport.height * aspect);
  final h = math.min(viewport.height, viewport.width / aspect);
  return Size(w, h);
}

/// 缩放平移钳位（视口中心系）：Transform.scale 绕中心缩放，视频放大后
/// 单侧可拖余量 = (scale×content − viewport)/2；未溢出轴余量 0（拖不动）。
/// scale=1 全轴归零＝与改前"拖动无反应"一致。
Offset clampViewOffset(
    Offset offset, double scale, Size content, Size viewport) {
  final lx = math.max(0.0, (scale * content.width - viewport.width) / 2);
  final ly = math.max(0.0, (scale * content.height - viewport.height) / 2);
  return Offset(offset.dx.clamp(-lx, lx), offset.dy.clamp(-ly, ly));
}

/// 视频播放页（规格 §3.5）：默认竖屏播放，点画面显示/隐藏底部控制条；
/// 控制条：播放暂停＋进度＋倍速＋全屏切换（全屏横屏沉浸）。支持捏合缩放。
class PlayerPage extends StatefulWidget {
  /// 直通模式：传已解析的绝对路径（SAF 模式已复制到缓存）。
  const PlayerPage({super.key, required this.fileName, this.title, this.loop = false})
      : pendingRel = null,
        pendingResolver = null;

  /// 页内加载模式（2026-10-28 反馈 #1）：点击立即进页，initState 先把
  /// [rel] 经 [resolver]（SAF 内容 URI 分块拷贝到缓存）解析成绝对路径，
  /// 再初始化播放器；解析失败页内提示且绝不初始化播放器（P1-13 语义）。
  const PlayerPage.pendingMedia({
    super.key,
    required String rel,
    required MediaPathResolver? resolver,
    this.title,
    this.loop = false,
  })  : pendingRel = rel,
        pendingResolver = resolver,
        fileName = '';

  final String fileName; // 直通模式的绝对路径
  final String? pendingRel; // 页内加载模式的存档相对路径
  final MediaPathResolver? pendingResolver;
  final String? title; // 顶栏标题（如「10月31日」），可空

  /// 播完循环（用户 2026-10-31 需求：首页记录流进入的播放循环；
  /// 其他入口默认播完暂停）
  final bool loop;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VideoPlayerController? _controller;
  double _speed = 1.0;
  bool _fullscreen = false;
  bool _controls = true;
  String? _error;

  /// 页内加载模式解析出的绝对路径（直通模式为 null，走 [widget.fileName]）。
  String? _resolvedPath;
  String get _path => _resolvedPath ?? widget.fileName;

  // 捏合缩放（规格 §3.2）：只做捏合（1×~5×）＋放大后单指拖动看局部。
  // _scaleBase 是手势起点基准——onScaleUpdate 里 setState 会更新
  // _viewScale，而 d.scale 是自手势起点累计的值，直接相乘会复利放大
  // （lib/ui/mosaic/mosaic_editor_page.dart:303 已文档化的同款坑）。
  double _viewScale = 1.0;
  Offset _viewOffset = Offset.zero;
  double? _scaleBase;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    VideoPlayerController? created;
    try {
      // 页内加载模式：先解析（SAF 分块拷贝让出 UI 线程），失败绝不建控制器
      final rel = widget.pendingRel;
      if (rel != null) {
        final resolved = await AbsPathCache.resolve(
            widget.pendingResolver, rel,
            paced: true);
        if (!mounted) return;
        if (resolved == null) {
          setState(() => _error = '视频文件已丢失，可从备份导入恢复');
          return; // P1-13：相对路径/解析失败不交给播放器
        }
        _resolvedPath = resolved;
      }
      final c = VideoPlayerController.file(File(_path));
      created = c;
      await c.initialize();
      // 首页记录流入口循环播放（用户 2026-10-31 需求）；其他入口保持
      // ExoPlayer 默认的播完停在末帧
      if (widget.loop) await c.setLooping(true);
      await c.setPlaybackSpeed(_speed);
      await c.play();
      if (!mounted) {
        // 加载大文件期间退出：必须回收持 GB 级文件句柄的 ExoPlayer（P2-21）
        await _disposeQuietly(created);
        return;
      }
      setState(() => _controller = c);
    } catch (e) {
      await _disposeQuietly(created); // 初始化失败同样回收
      if (!mounted) return;
      setState(() => _error = '视频加载失败：$e');
    }
  }

  /// initialize 失败的控制器 dispose 也可能抛，逐个吞掉。
  Future<void> _disposeQuietly(VideoPlayerController? c) async {
    if (c == null) return;
    try {
      await c.dispose();
    } catch (_) {}
  }

  void _setFullscreen(bool v) {
    setState(() => _fullscreen = v);
    SystemChrome.setEnabledSystemUIMode(
        v ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(v
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : [DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    c.value.isPlaying ? c.pause() : c.play();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final c = _controller;
    // 顶部按钮避开状态栏/刘海（F14）：竖屏正常态加状态栏高度，
    // 全屏沉浸态 padding 为 0 时仍保留 10dp 边距。
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Colors.black,
      body: _error != null
          ? Center(
              child: Text(_error!,
                  style: const TextStyle(fontSize: 12, color: Colors.white70)))
          : c == null || !c.value.isInitialized
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 12),
                      Text('正在加载视频，大文件首次打开需要一点时间…',
                          style: TextStyle(
                              fontSize: 11, color: Colors.white70)),
                    ],
                  ),
                )
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    // 渲染：Transform.translate 用 build 内钳位后的有效偏移——
                    // 全屏旋转后视口变化，下一帧自动按新边界重钳
                    // （_setFullscreen 无需特殊处理）。
                    Center(
                      child: Transform.translate(
                        offset: clampViewOffset(
                            _viewOffset,
                            _viewScale,
                            videoBaseSize(
                                MediaQuery.sizeOf(context), c.value.aspectRatio),
                            MediaQuery.sizeOf(context)),
                        child: Transform.scale(
                          scale: _viewScale,
                          child: AspectRatio(
                            aspectRatio: c.value.aspectRatio,
                            child: VideoPlayer(c),
                          ),
                        ),
                      ),
                    ),
                    // 手势层：translucent 才能让下层不再被挡；一个识别器同时
                    // 管 tap（切控制条）与 scale（捏合缩放／放大后拖动）。
                    // 改前是 opaque + 只注册 onTap，InteractiveViewer 收不到
                    // 任何事件——捏合缩放是死代码（spec §1 现状核实）。
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => setState(() => _controls = !_controls),
                        onScaleStart: (_) => _scaleBase = _viewScale,
                        onScaleUpdate: (d) {
                          final vp = MediaQuery.sizeOf(context);
                          final content =
                              videoBaseSize(vp, c.value.aspectRatio);
                          setState(() {
                            if (d.pointerCount >= 2) {
                              _viewScale =
                                  ((_scaleBase ?? 1.0) * d.scale).clamp(1.0, 5.0);
                            }
                            _viewOffset = clampViewOffset(
                                _viewOffset + d.focalPointDelta,
                                _viewScale,
                                content,
                                vp);
                          });
                        },
                        onScaleEnd: (_) => _scaleBase = null,
                      ),
                    ),
                    // T10b（用户 2026-10-31 反馈 4）：顶栏改通栏深色毛玻璃，
                    // 随控制条一起浮现/隐藏（保存钮也跟随——用户已确认接受）
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: AnimatedOpacity(
                        opacity: _controls ? 1 : 0,
                        duration: const Duration(milliseconds: 250),
                        child: AnimatedSlide(
                          // 隐藏时上移 8px（原型 translateY(-8px)，条高约 52）
                          offset:
                              _controls ? Offset.zero : const Offset(0, -0.16),
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                          child: IgnorePointer(
                            ignoring: !_controls,
                            child: ClipRect(
                              child: BackdropFilter(
                                filter:
                                    ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                                child: Container(
                                  color: _glassBarColor,
                                  padding:
                                      EdgeInsets.only(top: topInset, left: 4),
                                  foregroundDecoration: const BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                          color: Color(0x1AFFFFFF),
                                          width: 0.5),
                                    ),
                                  ),
                                  child: SizedBox(
                                    height: 52,
                                    child: Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.close,
                                              color: Colors.white),
                                          onPressed: () =>
                                              Navigator.pop(context),
                                        ),
                                        Expanded(
                                          child: Center(
                                            child: Text(
                                              widget.title ?? '',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style:
                                                  AppText.appBarTitle.copyWith(
                                                      color: Colors.white),
                                            ),
                                          ),
                                        ),
                                        SaveToGalleryButton(path: _path),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: AnimatedOpacity(
                        opacity: _controls ? 1 : 0,
                        duration: const Duration(milliseconds: 250),
                        child: AnimatedSlide(
                          // T10：浮现/隐藏带 8px 纵向位移（原型 translateY(8px)，
                          // 底部条约 66px 高 → fraction ≈ 0.12）
                          offset: _controls
                              ? Offset.zero
                              : const Offset(0, 0.12),
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                          child: IgnorePointer(
                            ignoring: !_controls,
                            child: ClipRect(
                              // T10：底栏深色毛玻璃（黑 55%＋blur 20）
                              child: BackdropFilter(
                                filter:
                                    ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                                child: Container(
                                  color: _glassBarColor,
                                  padding: EdgeInsets.only(
                                      left: 4,
                                      right: 0,
                                      top: 4,
                                      bottom:
                                          MediaQuery.paddingOf(context).bottom +
                                              4),
                            // 时间文本/播放图标必须跟随 controller 值刷新
                            // （用户 2026-10-31 反馈：进度条右侧时间一直是
                            // 00:00/00:18，只有点暂停触发 setState 才更新）
                            child: ValueListenableBuilder<VideoPlayerValue>(
                              valueListenable: c,
                              builder: (context, v, _) => Row(
                              children: [
                                IconButton(
                                  icon: Icon(
                                      v.isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      color: Colors.white),
                                  onPressed: _togglePlay,
                                ),
                                Expanded(
                                  child: VideoProgressIndicator(
                                    c,
                                    allowScrubbing: true,
                                    colors: VideoProgressColors(
                                        playedColor: accent),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${_fmt(v.position)} / ${_fmt(v.duration)}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 10),
                                ),
                                PopupMenuButton<double>(
                                  icon: Text('$_speed×',
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 12)),
                                  onSelected: (s) {
                                    setState(() => _speed = s);
                                    c.setPlaybackSpeed(s);
                                  },
                                  itemBuilder: (_) => [
                                    for (final s in _speeds)
                                      PopupMenuItem(
                                          value: s,
                                          child: Text('$s×',
                                              style: const TextStyle(
                                                  fontSize: 13))),
                                  ],
                                ),
                                IconButton(
                                  icon: Icon(
                                      _fullscreen
                                          ? Icons.fullscreen_exit
                                          : Icons.fullscreen,
                                      color: Colors.white),
                                  onPressed: () =>
                                      _setFullscreen(!_fullscreen),
                                ),
                              ],
                            ),
                            ),
                          ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }
}
