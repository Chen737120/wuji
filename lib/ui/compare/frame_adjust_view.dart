import 'package:flutter/material.dart';
import '../../editing/side_transform.dart';
import '../../theme.dart';

/// 画面微调面板（规格 §4.1 ②）：每侧比例 1:1/3:4/9:16（默认 3:4）。
/// 预览与手势在上方放大的双画面上进行（见 compare_page._side），
/// 本面板只负责比例切换与操作提示。
class FrameAdjustView extends StatelessWidget {
  const FrameAdjustView({
    super.key,
    required this.left,
    required this.right,
    required this.selectedSide,
    required this.onSelect,
    required this.onLeftChanged,
    required this.onRightChanged,
  });

  final SideTransform left;
  final SideTransform right;
  final int selectedSide; // 0=老师 1=我
  final ValueChanged<int> onSelect;
  final VoidCallback onLeftChanged;
  final VoidCallback onRightChanged;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        // 比例 chips（作用于选中侧；原型③「每侧比例」）
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('每侧比例（选中侧）:',
                style: TextStyle(fontSize: 11, color: AppColors.secondary)),
            for (final r in ['1:1', '3:4', '9:16'])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(r, style: const TextStyle(fontSize: 11)),
                  selected:
                      (selectedSide == 0 ? left : right).ratio == r,
                  selectedColor: accent,
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                      fontSize: 11,
                      color: (selectedSide == 0 ? left : right).ratio == r
                          ? Colors.white
                          : AppColors.ink),
                  onSelected: (_) {
                    if (selectedSide == 0) {
                      left.ratio = r;
                      onLeftChanged();
                    } else {
                      right.ratio = r;
                      onRightChanged();
                    }
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text('点选一侧视频后，可单指拖动、双指缩放（框内内容移动，裁剪框不动）。\n实线框＝老师侧，虚线框＝我的侧，框比例即导出比例',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: AppColors.faint)),
      ],
    );
  }
}
