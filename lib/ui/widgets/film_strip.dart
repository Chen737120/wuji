import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// 视频缩略图胶片条（2026-10-07 需求 #2/#5 共用组件）：
/// 均匀采样帧图横向拼接；拖动/点按回调 seek（上方/本页视频跟随显示该帧）；
/// 可选区间遮罩（修剪页用：区间外暗化）+ 播放头指示。
/// 起点/终点手柄由调用方叠加（需要外部 LayoutBuilder 宽度对齐）。
class FilmStrip extends StatefulWidget {
  const FilmStrip({
    super.key,
    required this.videoPath,
    required this.duration,
    required this.position,
    required this.onSeek,
    this.maskStart,
    this.maskEnd,
    this.accent = const Color(0xFF3FA26F),
    this.height = 56,
    this.stripCount = 12,
  });

  final String videoPath;
  final Duration duration;
  final Duration position;
  final ValueChanged<Duration> onSeek; // 目标时刻（内部由拖动位置换算）
  final Duration? maskStart; // 区间遮罩（修剪页）
  final Duration? maskEnd;
  final Color accent;
  final double height;
  final int stripCount;

  @override
  State<FilmStrip> createState() => _FilmStripState();
}

class _FilmStripState extends State<FilmStrip> {
  final Map<int, Uint8List?> _strip = {};

  @override
  void initState() {
    super.initState();
    _buildFilmstrip();
  }

  @override
  void didUpdateWidget(covariant FilmStrip old) {
    super.didUpdateWidget(old);
    if (old.videoPath != widget.videoPath) {
      _strip.clear();
      _buildFilmstrip();
    }
  }

  Future<void> _buildFilmstrip() async {
    final dur = widget.duration;
    if (dur <= Duration.zero) return;
    for (var i = 0; i < widget.stripCount; i++) {
      final ms = dur.inMilliseconds * (2 * i + 1) ~/ (2 * widget.stripCount);
      try {
        final bytes = await VideoThumbnail.thumbnailData(
          video: widget.videoPath,
          imageFormat: ImageFormat.JPEG,
          quality: 50,
          timeMs: ms,
        );
        if (!mounted) return;
        setState(() => _strip[i] = bytes);
      } catch (_) {
        if (!mounted) return;
        setState(() => _strip[i] = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalMs =
        widget.duration.inMilliseconds.clamp(1, 1 << 30).toDouble();
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final leftX = widget.maskStart == null
          ? 0.0
          : widget.maskStart!.inMilliseconds / totalMs * w;
      final rightX = widget.maskEnd == null
          ? w
          : widget.maskEnd!.inMilliseconds / totalMs * w;
      void seekToX(double x) {
        final ms = (x.clamp(0.0, w) / w * totalMs).round();
        widget.onSeek(Duration(milliseconds: ms));
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => seekToX(d.localPosition.dx),
        onTapUp: (d) => seekToX(d.localPosition.dx),
        child: SizedBox(
          height: widget.height,
          // Positioneds 只能做 Stack 直接子级
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 胶片条：连续帧缩略图
              Positioned.fill(
                child: Row(
                  children: [
                    for (var i = 0; i < widget.stripCount; i++)
                      Expanded(
                        child: _strip[i] != null
                            ? Image.memory(
                                _strip[i]!,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              )
                            : Container(color: const Color(0xFF2A2A2E)),
                      ),
                  ],
                ),
              ),
              // 区间外暗化（修剪页）
              if (widget.maskStart != null)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: leftX,
                  child:
                      Container(color: Colors.black.withValues(alpha: .62)),
                ),
              if (widget.maskEnd != null)
                Positioned(
                  left: rightX,
                  top: 0,
                  bottom: 0,
                  width: (w - rightX).clamp(0.0, w - rightX),
                  child:
                      Container(color: Colors.black.withValues(alpha: .62)),
                ),
              // 保留区间白描边（修剪页）
              if (widget.maskStart != null && widget.maskEnd != null)
                Positioned(
                  left: leftX,
                  width: (rightX - leftX).clamp(2.0, w),
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              // 播放头
              Positioned(
                top: 0,
                bottom: 0,
                left: (widget.position.inMilliseconds / totalMs * w)
                        .clamp(0.0, w - 2) -
                    1,
                width: 2,
                child: Container(color: widget.accent),
              ),
            ],
          ),
        ),
      );
    });
  }
}
