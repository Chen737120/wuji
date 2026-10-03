import 'dart:io';
import 'package:flutter/material.dart';

/// 图片全屏查看：捏合缩放/双指平移，点 ✕ 返回。
class ImageViewerPage extends StatelessWidget {
  const ImageViewerPage({super.key, required this.path});

  final String path; // 绝对路径

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              maxScale: 5,
              child: Image.file(File(path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Center(
                      child: Text('图片无法显示',
                          style:
                              TextStyle(fontSize: 12, color: Colors.white70))),
            ),
          )),
          Positioned(
            top: 10,
            left: 10,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
