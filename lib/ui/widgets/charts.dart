import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/stats.dart';
import '../../theme.dart';

/// 跳舞趋势柱状图：非峰值柱 #ECECE8，峰值柱点缀色；顶部「按天 · 按月」切换。
/// 2026-10-05 用户需求：柱区可**左右滑动**查看按天（60 天）/按月（12 个月）
/// 的过往数据，进入/切换时自动定位到最右（最新）。
class TrendBars extends StatefulWidget {
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
  State<TrendBars> createState() => _TrendBarsState();
}

class _TrendBarsState extends State<TrendBars> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _jumpToEnd();
  }

  @override
  void didUpdateWidget(covariant TrendBars old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode || old.points != widget.points) {
      _jumpToEnd();
    }
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final points = widget.points;
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
          // 柱区高度随卡片宽度自适应（夹在 56~112 之间），下方留 14 标签行
          final barH =
              (constraints.maxWidth * 0.30).clamp(56.0, 108.0).toDouble();
          // 纵轴刻度（分钟）：0 与峰值均分 4 段，左侧标签 + 横向网格线
          final ticks = <int>[
            0,
            (peak * 0.25).round(),
            (peak * 0.5).round(),
            (peak * 0.75).round(),
            peak,
          ];
          const labelW = 30.0;
          const labelH = 14.0;
          // 柱宽：按月 30px（12 根可滑动、图一观感），按天 17px
          final slotW = widget.mode == TrendMode.monthly ? 30.0 : 17.0;
          final contentW = math.max(constraints.maxWidth, points.length * slotW);
          return SizedBox(
            height: barH + labelH,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: labelW,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final t in ticks.reversed)
                        Text('$t',
                            style: TextStyle(
                                fontSize: 8, color: AppColors.faint)),
                      const SizedBox(height: labelH),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Stack(
                    children: [
                      // 固定网格线（不随柱区滚动）
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: barH,
                        child: Column(
                          children: [
                            for (final _ in ticks)
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                          color: AppColors.hairline,
                                          width: 0.5),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // 柱区＋日期标签：横向滑动
                      Positioned.fill(
                        child: SingleChildScrollView(
                          controller: _scroll,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: contentW,
                            height: barH + labelH,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final p in points)
                                  SizedBox(
                                    width: slotW,
                                    child: Column(
                                      children: [
                                        SizedBox(
                                          height: barH,
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              Container(
                                                height: p.minutes == 0
                                                    ? 2
                                                    : (p.minutes /
                                                            (peak == 0
                                                                ? 1
                                                                : peak)) *
                                                        (barH - 4),
                                                margin: EdgeInsets.symmetric(
                                                    horizontal:
                                                        widget.mode ==
                                                                TrendMode
                                                                    .monthly
                                                            ? 4.0
                                                            : 1.5),
                                                decoration: BoxDecoration(
                                                  color: p.minutes > 0 &&
                                                          p.minutes == peak
                                                      ? accent
                                                      : AppColors.hairline,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          2),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(
                                          height: labelH,
                                          child: Center(
                                            child: Text(p.label,
                                                style: TextStyle(
                                                    fontSize: 8,
                                                    color:
                                                        AppColors.faint)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _modeBtn(BuildContext context, String label, TrendMode m) {
    final selected = m == widget.mode;
    return GestureDetector(
      onTap: () => widget.onModeChanged(m),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: CustomPaint(painter: _DonutPainter(slices)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in slices)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: s.isOther
                                ? kOtherSliceColor
                                : kRainbowPalette[
                                    s.colorIndex % kRainbowPalette.length],
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${s.name} ${_pct(s.sessions)}%（${s.sessions}节）',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.secondary),
                        ),
                      ),
                    ],
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
  _DonutPainter(this.slices);
  final List<StyleSlice> slices;

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
    // 彩虹七色：每个舞种一色（超过 7 个循环），「其他」中性灰
    for (var i = 0; i < slices.length; i++) {
      final sweep = slices[i].sessions / total * 2 * math.pi;
      final color = slices[i].isOther
          ? kOtherSliceColor
          : kRainbowPalette[slices[i].colorIndex % kRainbowPalette.length];
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
                    // 2026-10-05 用户反馈：条形增粗、整体圆润
                    height: 9,
                    decoration: BoxDecoration(
                      color: AppColors.hairline,
                      borderRadius: BorderRadius.circular(4.5),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: totalSessions == 0
                          ? 0
                          : item.sessions / totalSessions,
                      child: Container(
                        decoration: BoxDecoration(
                          // 彩虹七色：每个条目一色（第 i 项取 i%7），不再单色系
                          color: kRainbowPalette[
                              items.indexOf(item) % kRainbowPalette.length],
                          borderRadius: BorderRadius.circular(4.5),
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
