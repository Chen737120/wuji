import 'package:flutter/material.dart';

import '../../services/photo_bridge.dart';

/// 保存到系统相册按钮（规格 §3.1）：默认走 PhotoManagerBridge.saveVideo，
/// saver 可注入供测试。saving 期间禁点防重入（避免双份文件）。
typedef GallerySaver = Future<void> Function(String path);

class SaveToGalleryButton extends StatefulWidget {
  const SaveToGalleryButton({super.key, required this.path, this.saver});

  final String path;
  final GallerySaver? saver;

  @override
  State<SaveToGalleryButton> createState() => _SaveToGalleryButtonState();
}

class _SaveToGalleryButtonState extends State<SaveToGalleryButton> {
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    final messenger = ScaffoldMessenger.of(context); // await 前取，防跨 async 用 context
    setState(() => _saving = true);
    try {
      await (widget.saver ?? PhotoManagerBridge.saveVideo)(widget.path);
      messenger.showSnackBar(const SnackBar(content: Text('已保存到相册')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('保存失败：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _saving ? null : _save,
      icon: _saving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2))
          : const Icon(Icons.download, color: Colors.white),
    );
  }
}
