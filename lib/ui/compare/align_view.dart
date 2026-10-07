import 'dart:async';
import 'package:flutter/material.dart';
import '../../editing/overlap.dart';

/// 时间微调面板（规格 §4.1 ② + 原型②）：提前/延后按钮（0.1s 步进、长按连发）
/// ＋偏移文案＋双时间条（白卡片内「老师／我」两行、圆角条）＋还原时间。
class AlignView extends StatefulWidget {
  const AlignView({
    super.key,
    required this.offset,
    required this.teacherDur,
    required this.myDur,
    required this.onStep,
    required this.onReset,
  });

  final Duration offset;
  final Duration teacherDur;
  final Duration myDur;
  final ValueChanged<Duration> onStep; // 步进 ±0.1s
  final VoidCallback onReset;

  @override
  State<AlignView> createState() => _AlignViewState();
}

class _AlignViewState extends State<AlignView> {
  static const _step = Duration(milliseconds: 100);
  static const _myColor = Color(0xFFD9B98A);
  Timer? _repeatTimer;
  Timer? _repeatStart;

  void _bump(int sign) {
    final next = widget.offset + Duration(milliseconds: sign * _step.inMilliseconds);
    widget.onStep(next);
  }

  void _startRepeat(int sign) {
    // 长按：400ms 起步延迟，之后每 80ms 一步
    _repeatStart = Timer(const Duration(milliseconds: 400), () {
      _repeatTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
        _bump(sign);
      });
    });
  }

  void _stopRepeat() {
    _repeatStart?.cancel();
    _repeatTimer?.cancel();
    _repeatStart = null;
    _repeatTimer = null;
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StepButton(
              label: '提前',
              onTap: () => _bump(-1),
              onLongPressStart: () => _startRepeat(-1),
              onLongPressEnd: _stopRepeat,
            ),
            const SizedBox(width: 16),
            Flexible(
                child: Text(describeOffset(widget.offset),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF2F2F2)))),
            const SizedBox(width: 16),
            _StepButton(
              label: '延后',
              onTap: () => _bump(1),
              onLongPressStart: () => _startRepeat(1),
              onLongPressEnd: _stopRepeat,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1F),
            border: Border.all(color: const Color(0xFF2E2E33)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _TimelineRow(
                label: '老师',
                color: accent,
                startFrac: _teacherStartFrac,
                widthFrac: _teacherWidthFrac,
                onDragStart: () => _dragSpan = _maxSpan,
                // 拖老师条向右 = 老师延后 = 我的相对提前 → offset 减
                onDrag: (dx, w) => _onRowDrag(false, dx, w),
              ),
              const SizedBox(height: 6),
              _TimelineRow(
                label: '我',
                color: _myColor,
                startFrac: _mineStartFrac,
                widthFrac: _mineWidthFrac,
                onDragStart: () => _dragSpan = _maxSpan,
                // 拖我的条向右 = 我的延后 → offset 加
                onDrag: (dx, w) => _onRowDrag(true, dx, w),
              ),
              const SizedBox(height: 6),
              Text('← 左右拖动时间条也可调节偏移 →',
                  style: const TextStyle(
                      fontSize: 9, color: Color(0xFF6A6A70))),
            ],
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
            onPressed: widget.onReset,
            child: const Text('还原时间', style: TextStyle(fontSize: 12))),
      ],
    );
  }

  Duration _dragSpan = Duration.zero;

  /// 拖动时间条改偏移：拖动像素 → 时间（以拖动开始时的总跨度换算）。
  void _onRowDrag(bool isMine, double dxPx, double rowW) {
    if (_dragSpan <= Duration.zero || rowW <= 0) return;
    final deltaMs = dxPx / rowW * _dragSpan.inMilliseconds;
    final delta = Duration(milliseconds: deltaMs.round());
    widget.onStep(isMine ? widget.offset + delta : widget.offset - delta);
  }

  // 双时间条归一化（原型②：老师条按偏移右移，我的条从 0 起）
  double get _teacherStartFrac {
    final total = _maxSpan.inMilliseconds;
    if (total <= 0) return 0;
    return (widget.offset < Duration.zero
            ? -widget.offset.inMilliseconds
            : 0) /
        total;
  }

  double get _teacherWidthFrac {
    final total = _maxSpan.inMilliseconds;
    if (total <= 0) return 0;
    var w = widget.teacherDur.inMilliseconds / total;
    if (_teacherStartFrac + w > 1) w = 1 - _teacherStartFrac;
    return w;
  }

  double get _mineStartFrac {
    final total = _maxSpan.inMilliseconds;
    if (total <= 0) return 0;
    return (widget.offset > Duration.zero ? widget.offset.inMilliseconds : 0) /
        total;
  }

  double get _mineWidthFrac {
    final total = _maxSpan.inMilliseconds;
    if (total <= 0) return 0;
    var w = widget.myDur.inMilliseconds / total;
    if (_mineStartFrac + w > 1) w = 1 - _mineStartFrac;
    return w;
  }

  Duration get _maxSpan {
    final o = widget.offset;
    final endMine = widget.myDur + (o > Duration.zero ? o : -o);
    final list = [widget.teacherDur, widget.myDur, endMine];
    list.sort();
    return list.last;
  }
}

/// 提前/延后步进按钮：点按一步、长按连发。
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.label,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      onLongPressStart: (_) => onLongPressStart(),
      onLongPressEnd: (_) => onLongPressEnd(),
      onLongPressCancel: onLongPressEnd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1F),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: .5)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: accent)),
      ),
    );
  }
}

/// 单行时间条：左标签＋圆角条（可左右拖动改偏移，触摸热区加高）。
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.label,
    required this.color,
    required this.startFrac,
    required this.widthFrac,
    required this.onDragStart,
    required this.onDrag,
  });

  final String label;
  final Color color;
  final double startFrac;
  final double widthFrac;
  final VoidCallback onDragStart;
  final void Function(double dxPx, double rowWidth) onDrag;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 26,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 10, color: Color(0xFF6A6A70))),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            final left = (startFrac * w).clamp(0.0, w);
            final barW = (widthFrac * w).clamp(0.0, w - left);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => onDragStart(),
              onHorizontalDragUpdate: (d) => onDrag(d.delta.dx, w),
              child: Container(
                height: 22,
                alignment: Alignment.center,
                // 扁平化（2026-10-07 用户反馈）：去掉底轨——那层比背景亮的
                // 轨道就是"浮雕/阴影"感的来源；只留彩色条本身，纯二维平面
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: left,
                      width: barW,
                      top: (22 - 8) / 2,
                      height: 8,
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
