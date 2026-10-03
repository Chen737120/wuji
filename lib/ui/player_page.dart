import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// 全屏播放器（规格 §3.5）：点画面进入；播放/暂停＋倍速；退出恢复竖屏。
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.fileName});

  final String fileName; // 存档相对路径

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VideoPlayerController? _controller;
  double _speed = 1.0;
  String? _error;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
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

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _controller?.dispose();
    super.dispose();
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
                  alignment: Alignment.bottomCenter,
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
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() {
                        c.value.isPlaying ? c.pause() : c.play();
                      }),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: PopupMenuButton<double>(
                        icon: Text('$_speed×',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13)),
                        onSelected: (s) {
                          setState(() => _speed = s);
                          c.setPlaybackSpeed(s);
                        },
                        itemBuilder: (_) => [
                          for (final s in _speeds)
                            PopupMenuItem(
                                value: s,
                                child: Text('$s×',
                                    style: const TextStyle(fontSize: 13))),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 12,
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              c.value.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: Colors.white,
                            ),
                            onPressed: () => setState(() {
                              c.value.isPlaying ? c.pause() : c.play();
                            }),
                          ),
                          Expanded(
                            child: VideoProgressIndicator(
                              c,
                              allowScrubbing: true,
                              colors: VideoProgressColors(playedColor: accent),
                            ),
                          ),
                          Text(
                            '${_fmt(c.value.position)} / ${_fmt(c.value.duration)}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 10),
                          ),
                        ],
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
