import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'widgets/save_to_gallery_button.dart';

const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// 视频播放页（规格 §3.5）：默认竖屏播放，点画面显示/隐藏底部控制条；
/// 控制条：播放暂停＋进度＋倍速＋全屏切换（全屏横屏沉浸）。支持捏合缩放。
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.fileName});

  final String fileName; // 绝对路径（SAF 模式已复制到缓存）

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VideoPlayerController? _controller;
  double _speed = 1.0;
  bool _fullscreen = false;
  bool _controls = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.file(File(widget.fileName));
      await c.initialize();
      await c.setPlaybackSpeed(_speed);
      await c.play();
      if (!mounted) return;
      setState(() => _controller = c);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '视频加载失败：$e');
    }
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
                    Center(
                      child: InteractiveViewer(
                        maxScale: 5,
                        child: AspectRatio(
                          aspectRatio: c.value.aspectRatio,
                          child: VideoPlayer(c),
                        ),
                      ),
                    ),
                    // 手势层：点画面切换控制条
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _controls = !_controls),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    // 保存到相册（规格 §3.1）：与左上关闭按钮对称、常驻显示，
                    // 不随控制条显隐——记录列表直达播放页时这是唯一保存入口
                    Positioned(
                      top: 10,
                      right: 10,
                      child: SaveToGalleryButton(path: widget.fileName),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: AnimatedOpacity(
                        opacity: _controls ? 1 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: IgnorePointer(
                          ignoring: !_controls,
                          child: Container(
                            color: Colors.black54,
                            padding: EdgeInsets.only(
                                left: 4,
                                right: 0,
                                top: 4,
                                bottom:
                                    MediaQuery.paddingOf(context).bottom + 4),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: Icon(
                                      c.value.isPlaying
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
                                  '${_fmt(c.value.position)} / ${_fmt(c.value.duration)}',
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
