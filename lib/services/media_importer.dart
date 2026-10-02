import 'package:flutter/material.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

/// 相册选择抽象：设备端 wechat_assets_picker（photo_manager 底座），测试用 fake 注入。
abstract class MediaImporter {
  Future<List<PickedMedia>> pick(BuildContext context, {int max = 30});
}

class PickedMedia {
  const PickedMedia({
    required this.path,
    required this.ext,
    required this.isVideo,
    this.durationSec,
    this.sizeBytes = 0,
  });

  final String path;
  final String ext;
  final bool isVideo;
  final int? durationSec;
  final int sizeBytes;
}

class PluginMediaImporter implements MediaImporter {
  const PluginMediaImporter();

  static Future<bool> requestPermission() async {
    final state = await PhotoManager.requestPermissionExtend();
    return state.isAuth;
  }

  @override
  Future<List<PickedMedia>> pick(BuildContext context, {int max = 30}) async {
    if (!await requestPermission()) return const [];
    if (!context.mounted) return const [];
    final assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        maxAssets: max,
        requestType: RequestType.common, // 视频＋图片
        themeColor: const Color(0xFF3FA26F),
      ),
    );
    if (assets == null) return const [];
    return _assetsToPicked(assets);
  }

  Future<List<PickedMedia>> _assetsToPicked(List<AssetEntity> assets) async {
    final out = <PickedMedia>[];
    for (final a in assets) {
      final file = await a.originFile;
      if (file == null) continue; // 读取失败的项跳过（规格 §8）
      out.add(PickedMedia(
        path: file.path,
        ext: a.type == AssetType.video ? 'mp4' : 'jpg',
        isVideo: a.type == AssetType.video,
        durationSec: a.type == AssetType.video ? a.duration : null,
        sizeBytes: await file.length(),
      ));
    }
    return out;
  }
}
