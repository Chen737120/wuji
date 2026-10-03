import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/stats.dart';
import '../../theme.dart';

/// 跳舞趋势柱状图：非峰值柱 #ECECE8，峰值柱点缀色；顶部「按天 · 按月」切换。
class TrendBars extends StatelessWidget {
  const TrendBars({
    super.key,
    required this.points,
    required this.mode,
    required this.onModeChanged,
  });

  final List<BarPoint> points;
  final TrendMode mode;
  final ValueChanged<TrendMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final peak = points.fold<int>(0, (a, b) => math.max(a, b.minutes));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('跳舞趋势（分钟）',
                style: TextStyle(fontSize: 11, letterSpacing: 2, color: AppColors.secondary)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _modeBtn(context, '按天', TrendMode.daily),
                Text(' · ', style: TextStyle(fontSize: 10, color: AppColors.faint)),
                _modeBtn(context, '按月', TrendMode.monthly),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, constraints) {
          // 柱区高度随卡片宽度自适应（有封面/大屏时更高，夹在 56~112 之间）
          final barH =
              (constraints.maxWidth * 0.32).clamp(56.0, 112.0).toDouble();
          return SizedBox(
            height: barH,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final p in points)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Container(
                        height: p.minutes == 0
                            ? 2
                            : (p.minutes / (peak == 0 ? 1 : peak)) * barH,
                        decoration: BoxDecoration(
                          color: p.minutes > 0 && p.minutes == peak
                              ? accent
                              : AppColors.hairline,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        // 终审 C4：按月只有 6 个点，skip(length-7) 会抛 RangeError；≤7 全显
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final p in (points.length > 7
                ? points.sublist(points.length - 7)
                : points))
              Expanded(
                child: Center(
                    child: Text(p.label,
                        style:
                            TextStyle(fontSize: 9, color: AppColors.faint))),
              ),
          ],
        ),
      ],
    );
  }

  Widget _modeBtn(BuildContext context, String label, TrendMode m) {
    final selected = m == mode;
    return GestureDetector(
      onTap: () => onModeChanged(m),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? AppColors.ink : AppColors.faint)),
    );
  }
}

/// 舞种分布环形图＋图例（点缀色亮度阶梯，最多 6 类＋其他）。
class StyleDonut extends StatelessWidget {
  const StyleDonut({super.key, required this.slices, required this.totalSessions});

  final List<StyleSlice> slices;
  final int totalSessions;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: CustomPaint(painter: _DonutPainter(slices, accent)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in slices)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '● ${s.name} ${_pct(s.sessions)}%（${s.sessions}节）',
                    style: TextStyle(fontSize: 11, color: AppColors.secondary),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _pct(int sessions) =>
      totalSessions == 0 ? '0' : (sessions * 100 / totalSessions).round().toString();
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices, this.accent);
  final List<StyleSlice> slices;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<int>(0, (a, s) => a + s.sessions);
    if (total == 0) {
      final paint = Paint()
        ..color = AppColors.hairline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12;
      canvas.drawCircle(Offset(size.width / 2, size.height / 2),
          size.width / 2 - 6, paint);
      return;
    }
    final rect = Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2), radius: size.width / 2 - 6);
    var start = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final sweep = slices[i].sessions / total * 2 * math.pi;
      final hsl = HSLColor.fromColor(accent);
      final color = slices[i].isOther
          ? AppColors.hairline
          : hsl.withLightness((0.62 - i * 0.08).clamp(0.25, 0.62)).toColor();
      canvas.drawArc(rect, start, sweep, true, Paint()..color = color);
      start += sweep;
    }
    // 中孔
    canvas.drawCircle(rect.center, rect.width / 2 - 12,
        Paint()..color = AppColors.bg);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.slices != slices;
}

/// 老师/舞室水平条：第一名点缀色，其余墨色；默认前 3＋展开全部。
class NameBars extends StatefulWidget {
  const NameBars({
    super.key,
    required this.title,
    required this.items,
    required this.totalSessions,
    this.collapsedTop = 3,
  });

  final String title;
  final List<NameCount> items;
  final int totalSessions;
  final int collapsedTop;

  @override
  State<NameBars> createState() => _NameBarsState();
}

class _NameBarsState extends State<NameBars> {
  bool _expanded = false;

  /// 「2节（50%）」；总节数为 0 时只显示节数。
  String _countLabel(int sessions, int total) {
    if (total <= 0) return '$sessions节';
    final pct = (sessions * 100 / total).round();
    return '$sessions节（$pct%）';
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final items = widget.items;
    final totalSessions = widget.totalSessions;
    final visible = _expanded ? items : items.take(widget.collapsedTop).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(widget.title,
                style: TextStyle(
                    fontSize: 11, letterSpacing: 2, color: AppColors.secondary)),
            if (items.length > widget.collapsedTop)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? '收起 ↑' : '展开全部 ↓',
                    style: TextStyle(fontSize: 10, color: AppColors.faint)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final item in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              children: [
                SizedBox(
                    width: 72,
                    child: Text(item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12))),
                Expanded(
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: AppColors.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: totalSessions == 0
                          ? 0
                          : item.sessions / totalSessions,
                      child: Container(
                        decoration: BoxDecoration(
                          color: item == items.first ? accent : AppColors.ink,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                    width: 88,
                    child: Text(_countLabel(item.sessions, totalSessions),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11, color: AppColors.secondary))),
              ],
            ),
          ),
      ],
    );
  }
}
