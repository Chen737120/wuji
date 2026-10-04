import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../editing/side_transform.dart';
import '../../theme.dart';

/// 画面微调面板（规格 §4.1 ②）：每侧比例 1:1/3:4/9:16（默认 3:4）、
/// 点选某侧后单指拖动平移、双指缩放（clamp 取样不出源）、选中侧描边高亮。
/// 预览直接渲染对应播放器的画面（cover 裁切 + 平移/缩放变换），
/// 预览区撑满可用高度，不再用小占位块。
class FrameAdjustView extends StatelessWidget {
  const FrameAdjustView({
    super.key,
    required this.left,
    required this.right,
    required this.teacherCtl,
    required this.mineCtl,
    required this.selectedSide,
    required this.onSelect,
    required this.onLeftChanged,
    required this.onRightChanged,
  });

  final SideTransform left;
  final SideTransform right;
  final VideoPlayerController? teacherCtl;
  final VideoPlayerController? mineCtl;
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
        // 双侧预览（视频画面 + 变换手势），撑满剩余高度
        Expanded(
          child: Row(
            children: [
              Expanded(
                  child: _SidePreview(
                side: 0,
                transform: left,
                ctl: teacherCtl,
                selected: selectedSide == 0,
                accent: accent,
                onSelect: () => onSelect(0),
                onChanged: onLeftChanged,
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: _SidePreview(
                side: 1,
                transform: right,
                ctl: mineCtl,
                selected: selectedSide == 1,
                accent: accent,
                dashed: true,
                onSelect: () => onSelect(1),
                onChanged: onRightChanged,
              )),
            ],
          ),
        ),
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
    required this.ctl,
    required this.selected,
    required this.accent,
    required this.onSelect,
    required this.onChanged,
    this.dashed = false,
  });

  final int side;
  final SideTransform transform;
  final VideoPlayerController? ctl;
  final bool selected;
  final bool dashed;
  final Color accent;
  final VoidCallback onSelect;
  final VoidCallback onChanged;

  double get _ratioAspect {
    switch (transform.ratio) {
      case '1:1':
        return 1;
      case '9:16':
        return 9 / 16;
      default:
        return 3 / 4;
    }
  }

  @override
  Widget build(BuildContext context) {
    final border = Border.all(
      color: selected ? accent : AppColors.hairline,
      width: selected ? 2 : 1,
    );
    final c = ctl;
    final ready = c != null && c.value.isInitialized;
    return GestureDetector(
      onTap: onSelect,
      onScaleStart: (_) => onSelect(),
      onScaleUpdate: (d) {
        if (!selected) return;
        if (d.pointerCount >= 2) {
          transform.scale = (transform.scale * d.scale).clamp(1.0, 4.0);
        } else {
          transform.pan = Offset(
            (transform.pan.dx - d.focalPointDelta.dx / 250).clamp(-1.0, 1.0),
            (transform.pan.dy + d.focalPointDelta.dy / 250).clamp(-1.0, 1.0),
          );
        }
        onChanged();
      },
      child: AspectRatio(
        aspectRatio: _ratioAspect,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.circular(10),
            border: border,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: ready
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      // 视频画面：按视频比例 cover 填充预览框，随变换平移/缩放
                      LayoutBuilder(builder: (context, box) {
                        final va = c.value.aspectRatio;
                        double w = box.maxHeight * va;
                        double h = box.maxHeight;
                        if (w < box.maxWidth) {
                          w = box.maxWidth;
                          h = box.maxWidth / va;
                        }
                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..translateByDouble(
                                transform.pan.dx * w * 0.3,
                                transform.pan.dy * h * 0.3,
                                0,
                                1)
                            ..scaleByDouble(transform.scale,
                                transform.scale, 1, 1),
                          child: SizedBox(
                              width: w,
                              height: h,
                              child: VideoPlayer(c)),
                        );
                      }),
                      // 裁剪框参考线（比例框）
                      IgnorePointer(
                        child: Container(
                          margin: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: Colors.white70,
                                width: 1,
                                strokeAlign: BorderSide.strokeAlignInside),
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Text(
                        '${side == 0 ? '老师' : '我的'}视频加载中…',
                        style:
                            TextStyle(fontSize: 10, color: AppColors.faint)),
                  ),
          ),
        ),
      ),
    );
  }
}
