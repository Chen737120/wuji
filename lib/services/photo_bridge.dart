import 'dart:io';
import 'package:photo_manager/photo_manager.dart';

/// 保存到系统相册的薄封装（规格 §3.5「保存到相册」）。
class PhotoManagerBridge {
  PhotoManagerBridge._();

  static Future<void> saveVideo(String path) async {
    await PhotoManager.editor.saveVideo(
      File(path),
      title: 'WUJI_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );
  }

  static Future<void> saveImage(String path) async {
    await PhotoManager.editor.saveImageWithPath(path);
  }
}
