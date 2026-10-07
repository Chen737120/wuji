import 'package:flutter/material.dart';

/// 画面微调面板（v1.5.9 方案一）：**比例全局共享**——切换时老师/我的
/// 画面框同时变形（不再每侧独立）。平移/缩放在上方画面框上单指/双指操作。
class FrameAdjustView extends StatelessWidget {
  const FrameAdjustView({
    super.key,
    required this.ratio,
    required this.onRatioChanged,
  });

  final String ratio; // 全局比例（两侧共用）
  final ValueChanged<String> onRatioChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('比例：',
                style: TextStyle(
                    fontSize: 11, color: const Color(0xFF9A9AA0))),
            for (final r in ['1:1', '3:4', '9:16'])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(r, style: const TextStyle(fontSize: 11)),
                  selected: ratio == r,
                  selectedColor: Theme.of(context).colorScheme.primary,
                  backgroundColor: const Color(0xFF1C1C1F),
                  labelStyle: TextStyle(
                      fontSize: 11,
                      color: ratio == r
                          ? Colors.white
                          : const Color(0xFF9A9AA0)),
                  onSelected: (_) => onRatioChanged(r),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
            '比例切换时老师/我的画面同时变形（画面框＝裁剪区）；\n点选一侧后单指拖动、双指缩放框下的视频，溢出部分即被裁掉',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: const Color(0xFF6A6A70))),
      ],
    );
  }
}
