import 'dart:async';

import 'package:flutter/material.dart';

/// 顶部轻提示（2026-10-28 反馈 #2）：SnackBar 固定渲染在 Scaffold 底部，
/// 会遮住打码页底部操作条；本组件把提示显示在屏幕顶部（SafeArea 下方居中），
/// [duration] 后自动消失。
///
/// 单例：同时只有一条，新消息替换旧条（旧 Timer 作废）。所有 remove 前一律
/// 判断 [OverlayEntry.mounted]——Timer 回调防二次 remove；跨测试用例/跨页时
/// 旧 Overlay 可能已销毁，未挂载 entry 直接 remove 会抛异常。
OverlayEntry? _entry;
Timer? _timer;

void showTopTip(
  BuildContext context,
  String msg, {
  Duration duration = const Duration(milliseconds: 2000),
}) {
  _dismiss();
  final overlay = Overlay.of(context, rootOverlay: true);
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(msg,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  _entry = entry;
  _timer = Timer(duration, () {
    if (entry.mounted) entry.remove();
    if (identical(_entry, entry)) _entry = null;
  });
}

/// 立即移除在显示的提示（页面 dispose 时调用，防提示跨页残留）。
void dismissTopTip() => _dismiss();

void _dismiss() {
  _timer?.cancel();
  _timer = null;
  final e = _entry;
  _entry = null;
  if (e != null && e.mounted) e.remove();
}
