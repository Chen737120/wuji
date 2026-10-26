// 直拍预览坐标映射（v1.5.26 走查 F10）。
// 视频层 Transform 为「绕视频中心缩放 scale + 平移 pan」（fancam_page 的
// Matrix4 translate→scale）；点选、框 painter、hitTest 必须用同一组映射，
// 否则预览放大后「点谁跟谁」与叠加框都会落到错误位置。
import 'dart:ui';

/// 视频内容坐标（未变换时的渲染区坐标）→ 屏幕坐标。
Offset previewToScreen(Offset content, Rect video, double scale, Offset pan) {
  final center = video.center;
  return center + (content - center) * scale + pan;
}

/// 屏幕坐标 → 视频内容坐标（[previewToScreen] 的逆变换）。
Offset previewToContent(Offset screen, Rect video, double scale, Offset pan) {
  final center = video.center;
  return center + (screen - pan - center) / scale;
}

/// 内容矩形 → 屏幕矩形（中心与尺寸同步缩放＋平移）。
Rect previewMappedRect(Rect content, Rect video, double scale, Offset pan) {
  final center = previewToScreen(content.center, video, scale, pan);
  return Rect.fromCenter(
    center: center,
    width: content.width * scale,
    height: content.height * scale,
  );
}

/// 屏幕点 → 视频归一化坐标（0..1，越界 clamp）。
Offset previewNormalizedPoint(
    Offset screen, Rect video, double scale, Offset pan) {
  final c = previewToContent(screen, video, scale, pan);
  return Offset(
    ((c.dx - video.left) / video.width).clamp(0.0, 1.0),
    ((c.dy - video.top) / video.height).clamp(0.0, 1.0),
  );
}
