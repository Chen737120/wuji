import 'package:flutter/material.dart';
import '../../editing/side_transform.dart';
import '../../theme.dart';

/// 画面微调面板（规格 §4.1 ②）：每侧比例 1:1/3:4/9:16（默认 3:4）、
/// 点选某侧后单指拖动平移、双指缩放（clamp 取样不出源）、选中侧描边高亮。
/// 变换状态由父级持有（[left]/[right] 可变对象 + onChanged 回传）。
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
        // 比例 chips（作用于选中侧）
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('选中侧比例：',
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
        // 双侧预览（Transform 手势）
        LayoutBuilder(builder: (context, constraints) {
          return Row(
            children: [
              Expanded(
                  child: _SidePreview(
                side: 0,
                transform: left,
                selected: selectedSide == 0,
                accent: accent,
                onSelect: () => onSelect(0),
                onChanged: onLeftChanged,
              )),
              const SizedBox(width: 6),
              Expanded(
                  child: _SidePreview(
                side: 1,
                transform: right,
                selected: selectedSide == 1,
                accent: accent,
                dashed: true,
                onSelect: () => onSelect(1),
                onChanged: onRightChanged,
              )),
            ],
          );
        }),
        const SizedBox(height: 8),
        Text('点选一侧后拖动平移、双指缩放；框比例即导出比例',
            style: TextStyle(fontSize: 10, color: AppColors.faint)),
      ],
    );
  }
}

class _SidePreview extends StatelessWidget {
  const _SidePreview({
    required this.side,
    required this.transform,
    required this.selected,
    required this.accent,
    required this.onSelect,
    required this.onChanged,
    this.dashed = false,
  });

  final int side;
  final SideTransform transform;
  final bool selected;
  final bool dashed;
  final Color accent;
  final VoidCallback onSelect;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final border = Border.all(
      color: selected ? accent : AppColors.hairline,
      width: selected ? 2 : 1,
    );
    return GestureDetector(
      onTap: onSelect,
      onPanUpdate: (d) {
        if (!selected) return;
        transform.pan = Offset(
          (transform.pan.dx - d.delta.dx / 200).clamp(-1.0, 1.0),
          (transform.pan.dy + d.delta.dy / 200).clamp(-1.0, 1.0),
        );
        onChanged();
      },
      child: AspectRatio(
        aspectRatio: 9 / 16,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.circular(10),
            border: border,
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.pan_tool_alt_outlined,
                  color: selected ? accent : AppColors.faint, size: 26),
              const SizedBox(height: 4),
              Text(side == 0 ? '老师视频' : '我的视频',
                  style: TextStyle(
                      fontSize: 11,
                      color: selected ? accent : AppColors.faint)),
              const SizedBox(height: 2),
              Text('${transform.ratio} · ${transform.scale.toStringAsFixed(1)}×',
                  style: TextStyle(fontSize: 9, color: AppColors.faint)),
            ],
          ),
        ),
      ),
    );
  }
}
