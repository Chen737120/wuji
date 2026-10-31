import 'package:flutter/material.dart';

/// 按压反馈（spec §2.1 / 任务书 §0）：pointer-down 即缩至 0.97
/// （100ms ease-out），抬起/取消复原。Listener 不消费事件，可与
/// onTap/拖拽手势并存；替代水波纹（不新增 InkWell 波纹）。
/// disableAnimations 时不做按压缩放（直达静止终态）。
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.enabled == false ||
        MediaQuery.disableAnimationsOf(context);
    return Listener(
      onPointerDown: disabled ? null : (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
