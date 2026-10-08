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

  @override
  Future<PickResult> pick(BuildContext context, {int max = 30}) async {
    // 权限已在系统层完成（含「部分照片」）；跳过选择器自带的权限中间页，
    // 否则 limited 用户每次都要额外点一遍「继续访问部分资源」
    try {
      await PhotoManager.setIgnorePermissionCheck(true);
    } catch (_) {}
    final state = await PhotoManager.requestPermissionExtend();
    // hasAccess 覆盖「已授权」与 Android 14+ 的「仅部分照片」；
    // 只看 isAuth 会把 limited 误判成未授权（系统已允许仍弹引导）
    if (!state.isAuth && !state.hasAccess) {
      // 权限被拒（历史拒绝/仅部分授权被收回）：弹窗引导，而不是静默返回空
      if (!context.mounted) return const PickResultEmpty();
      final open = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('需要「照片和视频」权限',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: const Text(
              '选择课堂视频/图片需要访问相册。\n点击「去开启」后在系统设置中允许，或重选可访问的照片范围。',
              style: TextStyle(fontSize: 13, height: 1.7)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('去开启')),
          ],
        ),
      );
      if (open == true) await PhotoManager.openSetting();
      return const PickResultEmpty();
    }
    if (!context.mounted) return const PickResultEmpty();
    // 「仅部分照片」一次性引导（2026-10-08 需求 #6/#7）：解释可选列表
    // 少于 Recent 总数属正常，引导去系统设置允许所有照片；每次冷启动至多一次
    if (state == PermissionState.limited) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('相册权限是「仅部分照片」',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: const Text(
              '选择器里只能看到已允许的那部分照片（Recent 总数多于列表属正常现象）。\n\n'
              '建议在系统设置 → 照片和视频 中允许「访问所有照片」，即可看到全部相册。',
              style: TextStyle(fontSize: 13, height: 1.7)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('仍用部分照片')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('前往设置')),
          ],
        ),
      );
      if (go == true) {
        await PhotoManager.openSetting();
        if (!context.mounted) return const PickResultEmpty();
        // 从设置回来后不自动打开选择器，用户手动重选一次即可
        return const PickResultEmpty();
      }
      if (!context.mounted) return const PickResultEmpty();
    }
    final List<AssetEntity>? assets;
    try {
      assets = await AssetPicker.pickAssets(
        context,
        pickerConfig: AssetPickerConfig(
          maxAssets: max,
          requestType: RequestType.common, // 视频＋图片
          themeColor: const Color(0xFF3FA26F),
          // 关掉选择器自带的整页提示（上面已引导过）
          limitedPermissionOverlayPredicate: (_) => false,
        ),
      );
    } catch (e) {
      debugPrint('打开相册失败: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('打开相册失败，请重试')));
      }
      return const PickResultEmpty();
    }
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
