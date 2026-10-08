import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// 「仅部分照片」权限统一引导（2026-10-08 需求 #7）。
///
/// 根因说明：Android 14+ 的「部分照片」授权是**系统级过滤**——应用只被
/// 允许看到用户勾选过的那部分媒体，MediaStore 查询天然只返回这部分，
/// 所以选择器里 Recent 少于相册总数是权限状态使然，不是数据丢失。
/// 每个入口当初授权时选的范围不同，就会观察到"有的入口全、有的入口少"。
///
/// 统一策略（新增记录/舞蹈直拍/同屏对比共用）：
/// - 每次冷启动至多提示一次（`_hintShownThisSession`）；
/// - 提供三个出口：**重新选择照片范围**（`presentLimited` 弹系统照片
///   选择界面，可勾选全部，选完直接继续）、**前往系统设置**、仍用部分照片；
/// - 返回 false = 用户选了离开应用去设置，调用方不要再打开选择器。
bool _hintShownThisSession = false;

/// 测试用：重置会话内已提示标记。
void resetGalleryPermissionHint() => _hintShownThisSession = false;

Future<bool> ensureGalleryAccess(BuildContext context) async {
  PermissionState ps;
  try {
    ps = await PhotoManager.getPermissionState(
        requestOption: const PermissionRequestOption());
  } catch (_) {
    return true; // 拿不到权限态就不打扰
  }
  if (ps != PermissionState.limited) return true;
  if (_hintShownThisSession || !context.mounted) return true;
  _hintShownThisSession = true;
  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('相册权限是「仅部分照片」',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: const Text(
          '选择器里只能看到你勾选过的那部分照片/视频（Recent 总数多于列表属正常现象，数据没有丢）。\n\n'
          '想看到完整相册：点「重新选择照片范围」后勾选全部，或到系统设置允许「访问所有照片」。',
          style: TextStyle(fontSize: 13, height: 1.7)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, 'keep'),
            child: const Text('仍用部分照片')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, 'settings'),
            child: const Text('前往设置')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, 'reselect'),
            child: const Text('重新选择照片范围')),
      ],
    ),
  );
  if (!context.mounted) return false;
  switch (action) {
    case 'reselect':
      // Android 14+/iOS 14+：弹系统照片选择界面，用户可勾选更多或全选；
      // 老系统未实现 → 回退打开系统设置
      try {
        await PhotoManager.presentLimited();
      } catch (_) {
        await PhotoManager.openSetting();
        return false; // 去设置后回来手动重试
      }
      return true; // 选完范围直接继续打开选择器
    case 'settings':
      await PhotoManager.openSetting();
      return false;
    default:
      return true; // 仍用部分照片 → 照常打开选择器
  }
}
