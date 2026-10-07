import 'dart:io';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

/// 保存到系统相册的薄封装（规格 §3.5「保存到相册」）。
/// 保存后触发系统媒体扫描：部分 ROM 上 MediaStore 条目建立滞后，
/// 文件已落盘但相册看不到——扫描后立刻可见。
class PhotoManagerBridge {
  PhotoManagerBridge._();

  static const _native = MethodChannel('wuji/native');

  static Future<void> saveVideo(String path) async {
    await PhotoManager.editor.saveVideo(
      File(path),
      title: 'WUJI_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );
    await _scan(path);
  }

  static Future<void> saveImage(String path) async {
    await PhotoManager.editor.saveImageWithPath(path);
    await _scan(path);
  }

  static Future<void> _scan(String path) async {
    try {
      await _native.invokeMethod('scanMedia', {'path': path});
    } catch (_) {
      // 非 Android 宿主/测试环境没有原生端：忽略，相册刷新交给系统
    }
  }

  /// 导入/导出期间屏幕常亮（FLAG_KEEP_SCREEN_ON，无需权限）。
  /// 非 Android 宿主静默忽略。
  static Future<void> setKeepScreenOn(bool on) async {
    try {
      await _native.invokeMethod('setKeepScreenOn', {'on': on});
    } catch (_) {}
  }
}
