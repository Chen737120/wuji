import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../editing/export_service.dart';
import '../../editing/fancam_export.dart';
import '../../editing/keyframes.dart';
import '../../theme.dart';

/// 直拍预览页（规格 §5.3）：参数单＋「返回调整」＋「保存到相册」。
/// 预览画面简化为参数单（参数即所见：框区域裁剪+720 高）。
class FancamPreviewPage extends StatefulWidget {
  const FancamPreviewPage({
    super.key,
    required this.sourcePath,
    required this.track,
    required this.srcW,
    required this.srcH,
    required this.ratio,
    required this.keyframeCount,
    this.hasAudio = true,
  });

  final String sourcePath;
  final KeyframeTrack track;
  final int srcW;
  final int srcH;
  final String ratio;
  final int keyframeCount;
  final bool hasAudio;

  @override
  State<FancamPreviewPage> createState() => _FancamPreviewPageState();
}

class _FancamPreviewPageState extends State<FancamPreviewPage> {
  bool _exporting = false;
  double _progress = 0;
  late final String _command;
  late final int _outHeight;

  @override
  void initState() {
    super.initState();
    // 不放大规则：输出高 = min(720, 最小框像素高)
    var h = 720;
    for (final f in widget.track.frames) {
      final ph = (f.box.h * widget.srcH).round();
      if (ph < h) h = ph;
    }
    _outHeight = h.clamp(1, 720);
    _command = buildFancamCommand(
      srcPath: widget.sourcePath,
      track: widget.track,
      srcW: widget.srcW,
      srcH: widget.srcH,
      hasAudio: widget.hasAudio,
    );
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final svc = ExportService(runner: FFmpegKitRunner(), mover: GalleryMover());
      final info = await _probeDur();
      final rel = await svc.run(
        ExportJob(
            command: _command,
            base: '直拍',
            expectedDurationMs: info),
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存到相册 Movies/wuji/')));
      // 导出成功：原地预览成片（预览确认环节），完成后返回编辑页
      setState(() {
        _exportedPath = '/storage/emulated/0/$rel';
        _exporting = false;
      });
    } on ExportCancelled {
      if (mounted) setState(() => _exporting = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$e')));
        setState(() => _exporting = false);
      }
    }
  }

  Future<int?> _probeDur() async => null; // 时长进度由 T3 选择器补挂；预留

  String? _exportedPath; // 导出成功后的成片路径（预览确认环节）

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final outW = (widget.ratio == '1:1'
            ? _outHeight
            : widget.ratio == '9:16'
                ? _outHeight * 9 / 16
                : _outHeight * 3 / 4)
        .round();
    if (_exportedPath != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context)),
          centerTitle: true,
          title: const Text('成片预览',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _ResultPreview(path: _exportedPath!),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.bg,
                      foregroundColor: AppColors.ink,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('完成',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
            onPressed: () => Navigator.pop(context)),
        centerTitle: true,
        title: const Text('直拍预览',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Column(
              children: [
                Text('参数单',
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 2,
                        color: AppColors.secondary)),
                const SizedBox(height: 12),
                _row('比例', widget.ratio),
                _row('输出分辨率', '$outW × $_outHeight'),
                _row('音频', widget.hasAudio ? '源视频完整原声' : '静音'),
                _row('关键帧', '${widget.keyframeCount} 个'),
                _row('保存位置', '相册 Movies/wuji/'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_exporting)
            Column(
              children: [
                LinearProgressIndicator(value: _progress <= 0 ? null : _progress),
                const SizedBox(height: 8),
                Text('导出中 ${(_progress * 100).round()}%',
                    style: TextStyle(fontSize: 11, color: AppColors.secondary)),
              ],
            )
          else ...[
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _export,
              child: const Text('保存到相册',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('← 返回调整',
                      style: TextStyle(fontSize: 12))),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: TextStyle(fontSize: 12, color: AppColors.secondary)),
            Text(v,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [])),
          ],
        ),
      );
}

/// 导出成片预览：自动播放，支持暂停/拖动，作为「预览确认环节」。
class _ResultPreview extends StatefulWidget {
  const _ResultPreview({required this.path});

  final String path;

  @override
  State<_ResultPreview> createState() => _ResultPreviewState();
}

class _ResultPreviewState extends State<_ResultPreview> {
  late final VideoPlayerController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = VideoPlayerController.file(File(widget.path));
    _ctl.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _ctl.play();
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ctl.value.isInitialized) {
      return const Center(
          child: Text('成片准备中…',
              style: TextStyle(fontSize: 11, color: Colors.white54)));
    }
    return Column(
      children: [
        AspectRatio(
          aspectRatio: _ctl.value.aspectRatio,
          child: VideoPlayer(_ctl),
        ),
        VideoProgressIndicator(
          _ctl,
          allowScrubbing: true,
          colors: VideoProgressColors(playedColor: AppColors.bg),
        ),
      ],
    );
  }
}
