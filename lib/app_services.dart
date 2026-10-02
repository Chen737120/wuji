import 'package:flutter/material.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'data/app_repository.dart' show MediaInput;

/// 相册选择抽象：设备端 wechat_assets_picker（photo_manager 底座），测试用 fake 注入。
abstract class MediaImporter {
  Future<PickResult> pick(BuildContext context, {int max = 30});
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

  MediaInput toInput() => MediaInput(
        sourcePath: path,
        ext: ext,
        isVideo: isVideo,
        durationSec: durationSec,
        sizeBytes: sizeBytes,
      );
}

/// 选择结果：picked 是可用项；failedNames 是读取失败被跳过的文件名（规格 §8 要求列出）。
class PickResult {
  const PickResult({required this.picked, this.failedNames = const []});
  final List<PickedMedia> picked;
  final List<String> failedNames;
}

class PickResultEmpty implements PickResult {
  const PickResultEmpty()
      : picked = const [],
        failedNames = const [];
  @override
  final List<PickedMedia> picked;
  @override
  final List<String> failedNames;
}

class PluginMediaImporter implements MediaImporter {
  const PluginMediaImporter();

  static Future<bool> requestPermission() async {
    final state = await PhotoManager.requestPermissionExtend();
    return state.isAuth;
  }

  @override
  Future<PickResult> pick(BuildContext context, {int max = 30}) async {
    if (!await requestPermission()) return const PickResultEmpty();
    if (!context.mounted) return const PickResultEmpty();
    final assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        maxAssets: max,
        requestType: RequestType.common, // 视频＋图片
        themeColor: const Color(0xFF3FA26F),
      ),
    );
    if (assets == null) return const PickResultEmpty();
    final picked = <PickedMedia>[];
    final failed = <String>[];
    for (final a in assets) {
      try {
        final file = await a.originFile;
        if (file == null) {
          failed.add(a.title ?? '未知文件');
          continue; // 读取失败列出（规格 §8）
        }
        picked.add(PickedMedia(
          path: file.path,
          ext: a.type == AssetType.video ? 'mp4' : 'jpg',
          isVideo: a.type == AssetType.video,
          durationSec: a.type == AssetType.video ? a.duration : null,
          sizeBytes: await file.length(),
        ));
      } catch (_) {
        failed.add(a.title ?? '未知文件');
      }
    }
    return PickResult(picked: picked, failedNames: failed);
  }
}

/// 存档位置切换服务（规格 §5.1）：由 AppRoot 注册，「我的」页消费。
class ArchiveSwitcher {
  const ArchiveSwitcher(this.run);
  final Future<void> Function() run;
}
