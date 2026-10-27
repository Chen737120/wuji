import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../editing/media_source_picker.dart';

/// 同屏对比·选择对比视频页（原型 03-compare-flow 图五）：
/// 先在此页分别选定 老师视频/我的视频（可更换/移除），
/// 点「开始对齐」后才进入编辑界面。
class ComparePickPage extends StatefulWidget {
  const ComparePickPage({super.key});

  @override
  State<ComparePickPage> createState() => _ComparePickPageState();
}

class _ComparePickPageState extends State<ComparePickPage> {
  PickedSource? _teacher;
  PickedSource? _mine;

  Future<void> _pick(bool isTeacher) async {
    final src = await showVideoSourceSheet(
      context,
      title: isTeacher ? '选择老师视频' : '选择我的视频',
      albumPicker: pickSingleVideoFromAlbum,
      archivePicker: showRecordMediaPicker,
    );
    if (src == null || !mounted) return;
    setState(() => isTeacher ? _teacher = src : _mine = src);
  }

  Future<void> _startAlign() async {
    final t = _teacher;
    final m = _mine;
    if (t == null || m == null) return;
    Navigator.pop(context, (teacher: t, mine: m));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
        centerTitle: true,
        title: const Text('同屏对比',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('选择对比视频',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text('自动对齐节拍，支持手动微调',
                  style: TextStyle(fontSize: 12, color: Colors.white54)),
            ),
            Row(
              children: [
                Expanded(
                    child: _SourceCard(
                        label: '老师视频',
                        source: _teacher,
                        onPick: () => _pick(true),
                        onRemove: () => setState(() => _teacher = null))),
                const SizedBox(width: 10),
                Expanded(
                    child: _SourceCard(
                        label: '我的视频',
                        source: _mine,
                        onPick: () => _pick(false),
                        onRemove: () => setState(() => _mine = null))),
              ],
            ),
            const Spacer(),
            SafeArea(
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE8506B),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed:
                      (_teacher != null && _mine != null) ? _startAlign : null,
                  child: const Text('开始对齐',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单张来源卡：未选=占位＋选取；已选=视频首帧画面＋时长＋更换/移除。
class _SourceCard extends StatefulWidget {
  const _SourceCard({
    required this.label,
    required this.source,
    required this.onPick,
    required this.onRemove,
  });

  final String label;
  final PickedSource? source;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

/// 异步初始化是否已被更新的一次操作淘汰（P2-23）：快速换源时旧控制器
/// 的回写会覆盖新预览（画面与文件名不符）并泄漏。
bool staleGeneration(int gen, int current) => gen != current;

class _SourceCardState extends State<_SourceCard> {
  VideoPlayerController? _ctl;

  /// 预览初始化代际：换源/移除都会 +1，作废在途的旧初始化
  int _initGen = 0;

  @override
  void didUpdateWidget(covariant _SourceCard old) {
    super.didUpdateWidget(old);
    final newPath = widget.source?.path;
    if (newPath != old.source?.path) {
      _initGen++; // 作废在途初始化（换源/移除都算）
      _ctl?.dispose();
      _ctl = null;
      if (newPath != null) _initPreview(newPath);
    }
  }

  Future<void> _initPreview(String path) async {
    final gen = ++_initGen;
    VideoPlayerController? c;
    try {
      c = VideoPlayerController.file(File(path));
      await c.initialize();
      await c.pause();
      await c.seekTo(Duration.zero);
      if (staleGeneration(gen, _initGen) || !mounted) {
        await _disposeQuietly(c);
        return;
      }
      setState(() => _ctl = c);
    } catch (_) {
      await _disposeQuietly(c);
    }
  }

  /// initialize 失败的控制器 dispose 也可能抛，吞掉。
  Future<void> _disposeQuietly(VideoPlayerController? c) async {
    if (c == null) return;
    try {
      await c.dispose();
    } catch (_) {}
  }

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  String get _durationText {
    final d = widget.source?.duration ?? _ctl?.value.duration;
    if (d == null || d.inMilliseconds <= 0) return '';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final src = widget.source;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF141418),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: widget.onPick,
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24),
                ),
                child: (_ctl != null && _ctl!.value.isInitialized)
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          FittedBox(
                            fit: BoxFit.cover,
                            // cover 会把子树放大到超出预选框，必须裁掉溢出
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox(
                              width: _ctl!.value.size.width == 0
                                  ? 1080
                                  : _ctl!.value.size.width,
                              height: _ctl!.value.size.height == 0
                                  ? 1920
                                  : _ctl!.value.size.height,
                              child: VideoPlayer(_ctl!),
                            ),
                          ),
                          Center(
                            child: Icon(Icons.play_circle_outline,
                                color: Colors.white.withValues(alpha: .9),
                                size: 44),
                          ),
                        ],
                      )
                    : const Center(
                        child: Icon(Icons.video_collection_outlined,
                            color: Colors.white24, size: 34),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(src == null ? '点击选取' : src.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
          if (_durationText.isNotEmpty)
            Text(_durationText,
                style: const TextStyle(fontSize: 11, color: Colors.white54)),
          Row(
            children: [
              TextButton(
                  onPressed: widget.onPick,
                  child: const Text('更换',
                      style: TextStyle(fontSize: 12, color: Colors.white))),
              const SizedBox(width: 8),
              TextButton(
                  onPressed: src == null ? null : widget.onRemove,
                  child: Text('移除',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              src == null ? Colors.white24 : Colors.white))),
            ],
          ),
        ],
      ),
    );
  }
}
