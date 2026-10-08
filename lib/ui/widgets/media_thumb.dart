import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/abs_path_cache.dart';
import '../../services/archive_fs.dart';
import '../../theme.dart';

/// 存档媒体封面小图（课堂视频选择页 / 按时间段导出页共用）：
/// [rel] = 存档内相对路径（视频传 thumbName、图片传原图路径）。
/// 解析失败/为空时回退 [fallbackIcon]（黑底▶/图片图标）。
class MediaThumb extends StatelessWidget {
  const MediaThumb({
    super.key,
    required this.rel,
    this.fallbackIcon = Icons.play_arrow,
    this.width = 56,
    this.height = 42,
  });

  final String? rel;
  final IconData fallbackIcon;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: rel == null
          ? Icon(fallbackIcon, color: AppColors.bg, size: 20)
          : FutureBuilder<String?>(
              future:
                  AbsPathCache.resolve(context.read<MediaPathResolver?>(), rel!),
              builder: (context, snap) {
                final path = snap.data;
                if (path == null) {
                  return Icon(fallbackIcon, color: AppColors.bg, size: 20);
                }
                return Image.file(File(path),
                    fit: BoxFit.cover,
                    cacheWidth: 200, // 列表小图：限解码宽防卡顿
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (_, _, _) =>
                        Icon(fallbackIcon, color: AppColors.bg, size: 20));
              },
            ),
    );
  }
}
