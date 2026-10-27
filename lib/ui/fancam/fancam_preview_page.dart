import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../../editing/export_service.dart';
import '../../editing/fancam_export.dart';
import '../../editing/fancam_follow_controller.dart';
import '../../editing/keyframes.dart';
import '../../editing/mosaic_region.dart';
import '../../theme.dart';

/// 直拍预览页（规格 §5.3）：参数单＋「返回调整」＋「生成成片」，
/// 出片后进入成片预览再「保存到相册」两步确认（P2-34）。
/// 预览画面简化为参数单（参数即所见：框区域裁剪+1080 高）。
/// 手动模式命令同步构建；自动跟踪模式（[FancamPreviewPage.follow] 非空）在
/// initState 异步落盘 cmds 文件后构建 sendcmd 命令（ruling 5）。
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
    this.regions = const [],
    this.mosaicRegionCount = 0,
    this.trimStart = Duration.zero,
    this.trimEnd,
    this.follow,
  });

  final String sourcePath;
  final KeyframeTrack track;
  final int srcW;
  final int srcH;
  final String ratio;
  final int keyframeCount;
  final bool hasAudio;

  /// 打码区域（导出命令真源；空列表＝无打码直拍，spec §3.2 合法状态）。
  final List<MosaicRegion> regions;

  /// 参数单展示用区域数（同 [keyframeCount] 惯例：数据与展示行分开传）。
  final int mosaicRegionCount;

  /// 修剪区间（关键帧时间轴相对 trimStart）
  final Duration trimStart;
  final Duration? trimEnd;

  /// 自动跟踪会话（Task 4 ruling 5）：非空＝自动模式导出——cmds 落盘
  /// `<cache>/wuji-export/follow-<millis>.txt`（内容＝buildSendCmd）＋
  /// buildFancamFollowCommand；null＝手动路径（现状，命令同步构建）。
  final FollowSession? follow;

  @override
  State<FancamPreviewPage> createState() => _FancamPreviewPageState();
}

/// 未保存的临时成片是否需要删除（P2-34）：生成后直接返回不留垃圾。
bool shouldDiscardTemp({required String? path, required bool saved}) =>
    path != null && !saved;

class _FancamPreviewPageState extends State<FancamPreviewPage> {
  bool _exporting = false;
  double _progress = 0;
  bool _saving = false;
  /// 成片是否已写入相册；false 时页面销毁要删掉临时成片。
  bool _savedToGallery = false;
  // 手动模式 initState 同步构建；自动模式 cmds 落盘后异步赋值（落盘前按钮禁用）
  String? _command;
  int _outWidth = 0;
  int _outHeight = 0;
  String? _followError; // 自动模式 cmds 落盘失败（按钮禁用＋参数单提示）
  ExportService? _svc;

  /// 自动模式落盘的 sendcmd 命令文件；页面销毁或初始化失败时 best-effort 删除
  ///（v1.5.26 走查 F8：原实现写后不删，cache 里 follow-*.txt 持续累积）。
  String? _cmdsPath;

  @override
  void initState() {
    super.initState();
    final follow = widget.follow;
    if (follow == null) {
      // 手动模式：与旧版同流程（同步构建）。输出尺寸与导出命令共用
      // fancamOutputSize（不放大 + 16 宏块对齐，2026-10-12：非 16 倍数输出
      // 会被编码器 pad，部分设备预览渲染出右缘绿条/底部黑条），参数单展示
      // 的就是真实输出。
      final (cropW, cropH) =
          widget.track.fixedCropSize(widget.srcW, widget.srcH);
      final (outW, outH) = fancamOutputSize(cropW, cropH);
      _outWidth = outW;
      _outHeight = outH;
      _command = buildFancamCommand(
        srcPath: widget.sourcePath,
        track: widget.track,
        srcW: widget.srcW,
        srcH: widget.srcH,
        regions: widget.regions,
        hasAudio: widget.hasAudio,
        trimStart: widget.trimStart,
        trimEnd: widget.trimEnd,
      );
    } else {
      _initFollow(follow);
    }
  }

  /// 自动跟踪模式（ruling 5）：cmds 落盘 `<cache>/wuji-export/follow-<millis>.txt`
  /// （内容＝`follow.buildSendCmd()` 三段式）→ `buildFancamFollowCommand`
  /// （crop 尺寸＝followCropSize，centers＝轨迹，打码 regions 沿用）。
  Future<void> _initFollow(FollowSession follow) async {
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/wuji-export');
      await dir.create(recursive: true);
      // 落盘前再查 mounted：若页面在 await 期间退出，dispose 已执行过，
      // 此时再写文件就会留下无人清理的 cmds（F8 的同一个缓存累积问题）
      if (!mounted) return;
      final cmdsPath =
          '${dir.path}/follow-${DateTime.now().millisecondsSinceEpoch}.txt';
      // 先记路径再写：写入中途失败也能在 catch 里清掉半截文件
      _cmdsPath = cmdsPath;
      await File(cmdsPath).writeAsString(follow.buildSendCmd());
      if (!mounted) {
        _deleteCmdsFile(); // 写完才发现已退出：直接清掉
        return;
      }
      final (cropW, cropH) =
          followCropSize(follow.box, widget.srcW, widget.srcH);
      final (outW, outH) = fancamOutputSize(cropW, cropH);
      if (!mounted) return;
      setState(() {
        _outWidth = outW;
        _outHeight = outH;
        _command = buildFancamFollowCommand(
          srcPath: widget.sourcePath,
          cmdsPath: cmdsPath,
          cropW: cropW,
          cropH: cropH,
          srcW: widget.srcW,
          srcH: widget.srcH,
          centers: follow.centers,
          hasAudio: widget.hasAudio,
          trimStart: widget.trimStart,
          trimEnd: widget.trimEnd,
          regions: widget.regions,
        );
      });
    } catch (e) {
      _deleteCmdsFile(); // 初始化失败：已落盘的 cmds 不再被引用，立即清
      if (mounted) setState(() => _followError = '跟踪数据准备失败：$e');
    }
  }

  /// 删除 cmds 临时文件（best-effort；缓存目录系统可回收，失败不打断流程）。
  void _deleteCmdsFile() {
    final p = _cmdsPath;
    _cmdsPath = null;
    if (p == null) return;
    try {
      final f = File(p);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  @override
  void dispose() {
    _deleteCmdsFile();
    if (shouldDiscardTemp(path: _exportedPath, saved: _savedToGallery)) {
      try {
        final f = File(_exportedPath!);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  /// 第一步「保存到相册」：先只导出到临时文件并进入成片预览；
  /// 用户在预览里确认没问题、点「完成」后才真正写入系统相册（[_finish]）。
  Future<void> _export() async {
    final cmd = _command;
    if (_exporting || cmd == null) return; // 自动模式 cmds 未就绪时不导出
    setState(() => _exporting = true);
    try {
      _svc = ExportService(runner: FFmpegKitRunner(), mover: GalleryMover());
      final info = await _probeDur();
      final tempPath = await _svc!.run(
        ExportJob(
            command: cmd,
            base: '直拍',
            expectedDurationMs: info),
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        autoSave: false,
      );
      if (!mounted) return;
      setState(() {
        _exportedPath = tempPath;
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

  /// 预览确认后「保存到相册」：此时才把成片写入系统相册，然后返回编辑页。
  Future<void> _finish() async {
    if (_saving || _exportedPath == null || _svc == null) return;
    setState(() => _saving = true);
    try {
      final fileName = _exportedPath!.split(Platform.pathSeparator).last;
      await _svc!.saveToGallery(_exportedPath!, fileName);
      _savedToGallery = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存到相册 Movies/wuji/')));
      Navigator.of(context).pop(); // 回编辑页
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
        setState(() => _saving = false);
      }
    }
  }

  /// 导出进度分母 = 修剪后时长（未修剪时 null 不显示进度）
  Future<int?> _probeDur() async => widget.trimEnd == null
      ? null
      : (widget.trimEnd! - widget.trimStart).inMilliseconds;

  String? _exportedPath; // 导出成功后的成片路径（预览确认环节）

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
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
                      backgroundColor:
                          _saving ? AppColors.hairline : AppColors.bg,
                      foregroundColor: AppColors.ink,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: _saving ? null : _finish,
                    child: Text(_saving ? '保存中…' : '保存到相册',
                        style: const TextStyle(
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
                _row('输出分辨率',
                    _outWidth <= 0 ? '—' : '$_outWidth × $_outHeight'),
                _row('音频', widget.hasAudio ? '源视频完整原声' : '静音'),
                // 模式行（Task 4 ruling 5）：自动跟踪（锚点 N 个）/ 手动打点
                // （关键帧 M 个）——自动模式锚点数取 session，手动取关键帧数
                _row('模式', widget.follow != null
                    ? '自动跟踪（锚点 ${widget.follow!.anchors.length} 个）'
                    : '手动打点（关键帧 ${widget.keyframeCount} 个）'),
                _row('打码',
                    widget.mosaicRegionCount == 0 ? '无' : '${widget.mosaicRegionCount} 个区域'),
                if (widget.trimEnd != null)
                  _row('时长',
                      '${((widget.trimEnd! - widget.trimStart).inMilliseconds / 1000).toStringAsFixed(1)} 秒（已修剪）'),
                _row('保存位置', '确认预览后存入相册 Movies/wuji/'),
                if (_followError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_followError!,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.redAccent)),
                  ),
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
              onPressed: _command == null ? null : _export,
              child: const Text('生成成片',
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

/// 导出成片预览：自动播放，播放/暂停＋可拖动进度条（预览确认环节）。
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
    _ctl = VideoPlayerController.file(File(widget.path),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
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
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _ctl,
      builder: (context, v, _) {
        String fmt(Duration d) {
          final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
          final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
          return '$m:$s';
        }

        return Column(
          children: [
            AspectRatio(
              aspectRatio: _ctl.value.aspectRatio,
              child: VideoPlayer(_ctl),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () =>
                        v.isPlaying ? _ctl.pause() : _ctl.play(),
                    icon: Icon(
                      v.isPlaying
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  Text('${fmt(v.position)} / ${fmt(v.duration)}',
                      style: const TextStyle(
                          fontSize: 10, color: Colors.white54)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 5),
                        overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 9),
                        activeTrackColor: AppColors.bg,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                      ),
                      child: Slider(
                        value: v.position.inMilliseconds
                            .clamp(0, v.duration.inMilliseconds)
                            .toDouble(),
                        max: v.duration.inMilliseconds
                            .toDouble()
                            .clamp(1, double.infinity)
                            .toDouble(),
                        onChanged: (ms) =>
                            _ctl.seekTo(Duration(milliseconds: ms.round())),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
