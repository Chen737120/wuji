import 'dart:async';
import 'package:flutter/material.dart';
import '../../editing/overlap.dart';
import '../../theme.dart';

/// 时间微调面板（规格 §4.1 ②）：提前/延后按钮（0.1s 步进、长按连发）＋
/// 偏移文案＋双时间条（老师翠芽 / 我的 米色 #D9B98A）＋还原时间。
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
            Text(describeOffset(widget.offset),
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 16),
            _StepButton(
              label: '延后',
              onTap: () => _bump(1),
              onLongPressStart: () => _startRepeat(1),
              onLongPressEnd: _stopRepeat,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _DualTimeline(
          offset: widget.offset,
          teacherDur: widget.teacherDur,
          myDur: widget.myDur,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              _dot(accent),
              const SizedBox(width: 4),
              const Text('老师视频',
                  style: TextStyle(fontSize: 10, color: AppColors.faint)),
              const SizedBox(width: 10),
              _dot(_myColor),
              const SizedBox(width: 4),
              const Text('我的视频',
                  style: TextStyle(fontSize: 10, color: AppColors.faint)),
            ]),
            TextButton(
                onPressed: widget.onReset,
                child: const Text('还原时间', style: TextStyle(fontSize: 12))),
          ],
        ),
      ],
    );
  }

  Widget _dot(Color c) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle));
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
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

/// 双时间条：按总跨度归一显示两段相对位置（含偏移）。
class _DualTimeline extends StatelessWidget {
  const _DualTimeline({
    required this.offset,
    required this.teacherDur,
    required this.myDur,
  });

  final Duration offset;
  final Duration teacherDur;
  final Duration myDur;

  static const _myColor = Color(0xFFD9B98A);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final total = _maxSpan();
      if (total <= Duration.zero) return const SizedBox(height: 34);
      final accent = Theme.of(context).colorScheme.primary;

      double fracMs(int ms) => ms / total.inMilliseconds;
      final teacherStartFrac =
          fracMs(offset < Duration.zero ? -offset.inMilliseconds : 0);
      final teacherWidthFrac = fracMs(teacherDur.inMilliseconds);
      final mineStartFrac =
          fracMs(offset > Duration.zero ? offset.inMilliseconds : 0);
      final mineWidthFrac = fracMs(myDur.inMilliseconds);

      Rect rect(double startFrac, double widthFrac, double height, double y) {
        var left = startFrac * w;
        var right = left + widthFrac * w;
        if (right > w) right = w;
        if (left > w) left = w;
        return Rect.fromLTRB(left, y, right, y + height);
      }

      return SizedBox(
        height: 34,
        child: Stack(
          children: [
            CustomPaint(
              size: Size(w, 34),
              painter: _BarsPainter(
                teacher: rect(teacherStartFrac, teacherWidthFrac, 12, 0),
                mine: rect(mineStartFrac, mineWidthFrac, 12, 22),
                teacherColor: accent,
                mineColor: _myColor,
              ),
            ),
          ],
        ),
      );
    });
  }

  Duration _maxSpan() {
    final endMine = myDur +
        (offset > Duration.zero ? offset : -offset);
    final list = [teacherDur, myDur, endMine];
    list.sort();
    return list.last;
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.teacher,
    required this.mine,
    required this.teacherColor,
    required this.mineColor,
  });

  final Rect teacher;
  final Rect mine;
  final Color teacherColor;
  final Color mineColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(teacher, Paint()..color = teacherColor);
    canvas.drawRect(mine, Paint()..color = mineColor);
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) =>
      old.teacher != teacher || old.mine != mine;
}
