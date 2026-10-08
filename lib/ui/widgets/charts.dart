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
  int? _selected; // 点击选中的柱（需求 #9：气泡显示时长）

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

  /// 气泡里的时长文案：≥90 分钟显示小时（1 位小数），否则显示分钟。
  String _minutesText(int m) =>
      m >= 90 ? '${(m / 60).toStringAsFixed(1)} 小时' : '$m 分钟';

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
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _modeBtn(context, '按天', TrendMode.daily),
                Text(' · ', style: TextStyle(fontSize: 11, color: AppColors.faint)),
                _modeBtn(context, '按月', TrendMode.monthly),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, constraints) {
          // 柱区高度随卡片宽度自适应（夹在 72~132 之间），下方留 18 标签行
          final barH =
              (constraints.maxWidth * 0.36).clamp(72.0, 132.0).toDouble();
          // 纵轴刻度（分钟）：0 与峰值均分 4 段，左侧标签 + 横向网格线
          final ticks = <int>[
            0,
            (peak * 0.25).round(),
            (peak * 0.5).round(),
            (peak * 0.75).round(),
            peak,
          ];
          const labelW = 40.0;
          const labelH = 18.0;
          // 柱宽：按月 30px（12 根可滑动、图一观感），按天 17px
          final slotW = widget.mode == TrendMode.monthly ? 36.0 : 20.0;
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
                                fontSize: 10, color: AppColors.faint)),
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
                      // 柱区＋日期标签：横向滑动；点柱显示时长气泡（需求 #9）
                      Positioned.fill(
                        child: SingleChildScrollView(
                          controller: _scroll,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: contentW,
                            height: barH + labelH,
                            child: Stack(
                              children: [
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    for (var i = 0; i < points.length; i++)
                                      SizedBox(
                                        width: slotW,
                                        child: GestureDetector(
                                          behavior:
                                              HitTestBehavior.opaque,
                                          onTap: () => setState(() =>
                                              _selected = _selected == i
                                                  ? null
                                                  : i),
                                          child: Column(
                                            children: [
                                              SizedBox(
                                                height: barH,
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .end,
                                                  children: [
                                                    Container(
                                                      height: points[i]
                                                                  .minutes ==
                                                              0
                                                          ? 2
                                                          : (points[i].minutes /
                                                                  (peak == 0
                                                                      ? 1
                                                                      : peak)) *
                                                              (barH - 4),
                                                      margin: EdgeInsets
                                                          .symmetric(
                                                              horizontal: widget
                                                                          .mode ==
                                                                      TrendMode
                                                                          .monthly
                                                                  ? 4.0
                                                                  : 1.5),
                                                      decoration:
                                                          BoxDecoration(
                                                        // 选中柱加深；其余柱
                                                        // 全部用点缀色
                                                        color: _selected ==
                                                                i
                                                            ? AppColors.ink
                                                            : points[i].minutes >
                                                                    0
                                                                ? accent
                                                                : AppColors
                                                                    .hairline,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(2),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              SizedBox(
                                                height: labelH,
                                                child: Center(
                                                  child: Text(
                                                      points[i].label,
                                                      style: TextStyle(
                                                          fontSize: 10,
                                                          color: AppColors
                                                              .faint)),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                // 时长气泡（点击柱子时显示，需求 #9）
                                if (_selected != null &&
                                    _selected! < points.length &&
                                    points[_selected!].minutes > 0)
                                  Positioned(
                                    top: 0,
                                    // clamp 到可视窗口（滚动到两端时气泡也可见）
                                    left: (_selected! * slotW +
                                            slotW / 2 -
                                            60)
                                        .clamp(
                                            _scroll.hasClients
                                                ? _scroll.offset
                                                : 0.0,
                                            math.max(
                                                0.0,
                                                (_scroll.hasClients
                                                        ? _scroll.offset +
                                                            _scroll.position
                                                                .viewportDimension
                                                        : contentW) -
                                                    120)),
                                    width: 120,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: AppColors.ink
                                            .withValues(alpha: .88),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(points[_selected!].tooltip,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.white70)),
                                          Text(_minutesText(
                                              points[_selected!].minutes),
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight:
                                                      FontWeight.w700,
                                                  color: Colors.white)),
                                        ],
                                      ),
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
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? AppColors.ink : AppColors.faint)),
    );
  }
}

/// 舞种分布环形图＋图例（2026-10-07 调整：**颜色联动外观点缀色**——
/// 调色板中选与点缀色最接近的一色给占比最高的舞种，其余按调色板顺序
/// 循环；"其他"中性灰。中心显示"X种/舞种分布"）。
class StyleDonut extends StatelessWidget {
  const StyleDonut({
    super.key,
    required this.slices,
    required this.totalSessions,
    required this.accent,
  });

  final List<StyleSlice> slices;
  final int totalSessions;
  final Color accent; // 当前外观点缀色

  /// 各 slice 颜色：占比最高（slices[0]）取调色板中最接近点缀色的颜色，
  /// 后续按调色板顺序循环。
  Color sliceColor(StyleSlice s) {
    if (s.isOther) return kOtherSliceColor;
    var nearest = 0;
    var bestDist = double.maxFinite;
    for (var i = 0; i < kRainbowPalette.length; i++) {
      final a = kRainbowPalette[i];
      final d = (a.r - accent.r) * (a.r - accent.r) +
          (a.g - accent.g) * (a.g - accent.g) +
          (a.b - accent.b) * (a.b - accent.b);
      if (d < bestDist) {
        bestDist = d;
        nearest = i;
      }
    }
    final nonOtherIdx =
        slices.where((x) => !x.isOther).toList().indexOf(s);
    return kRainbowPalette[(nearest + nonOtherIdx) % kRainbowPalette.length];
  }

  @override
  Widget build(BuildContext context) {
    // 中心文字："X种 / 舞种分布"；盒子和画布同尺寸（116），孔径加大保证完整
    final kinds = slices.where((s) => !s.isOther).length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 116,
          height: 116,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Stack loose 约束下无 child 的 CustomPaint 尺寸会变 0——必须显式给 size
              CustomPaint(size: const Size(116, 116), painter: _DonutPainter(slices, sliceColor)),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$kinds种',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w400, // 2026-10-08：细一点
                          color: AppColors.ink)),
                  const Text('舞种分布',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.faint)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 28),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in slices)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: sliceColor(s),
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${s.name} ${_pct(s.sessions)}%（${s.sessions}节）',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.secondary),
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
  _DonutPainter(this.slices, this.colorOf);
  final List<StyleSlice> slices;
  final Color Function(StyleSlice) colorOf;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<int>(0, (a, s) => a + s.sessions);
    if (total == 0) {
      // 空态几何与有数据时一致（2026-10-08：避免"0 种时环更大"的观感差异）
      final paint = Paint()
        ..color = AppColors.hairline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22;
      canvas.drawCircle(Offset(size.width / 2, size.height / 2),
          size.width / 2 - 8, paint);
      return;
    }
    final rect = Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2), radius: size.width / 2 - 8);
    var start = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final sweep = slices[i].sessions / total * 2 * math.pi;
      canvas.drawArc(rect, start, sweep, true, Paint()..color = colorOf(slices[i]));
      start += sweep;
    }
    // 中孔加大（孔径 72px），保证"X种/舞种分布"完整显示不被环挡
    canvas.drawCircle(rect.center, rect.width / 2 - 14,
        Paint()..color = AppColors.bg);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.slices != slices || old.colorOf != colorOf;
}

/// 老师/舞室水平条（2026-10-07 调整）：**超过 8 条只显示前 8 条**，
/// 底部居中"加载更多 ∨"胶囊按钮展开/收起（替代原右上角小字，参考图一）。
class NameBars extends StatefulWidget {
  const NameBars({
    super.key,
    required this.title,
    required this.items,
    required this.totalSessions,
    this.collapsedTop = 8,
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
    final overflow = items.length > widget.collapsedTop;
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.ink)),
        const SizedBox(height: 12),
        for (final item in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              children: [
                SizedBox(
                    width: 88,
                    child: Text(item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14))),
                Expanded(
                  child: Container(
                    // 条形增粗（随整体调大一档）
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppColors.hairline,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: totalSessions == 0
                          ? 0
                          : item.sessions / totalSessions,
                      child: Container(
                        decoration: BoxDecoration(
                          // 前十色循环 + 整体调亮一档（2026-10-07：轻松活泼）
                          color: brightenChartColor(kRainbowPalette[
                              items.indexOf(item) % kRainbowPalette.length]),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                    width: 96,
                    child: Text(_countLabel(item.sessions, totalSessions),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 13, color: AppColors.secondary))),
              ],
            ),
          ),
        if (overflow)
          // 底部居中"加载更多 ∨"胶囊按钮（参考图一）
          Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_expanded ? '收起' : '加载更多',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: accent)),
                    const SizedBox(width: 4),
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                        size: 16, color: accent),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 跳舞热力图（2026-10-08 需求 #8，样式参考 GitHub 提交墙）：
/// 列=周（周一起）、行=周一..周日，颜色深浅=当天跳舞分钟数；可横向滑动
/// 查看最近 26 周。空=浅灰；有数据按分钟分四档点缀色深浅。长按格子看详情。
class DanceHeatmap extends StatelessWidget {
  const DanceHeatmap({super.key, required this.minutesByDay});

  final Map<String, int> minutesByDay; // 'yyyy-MM-dd' -> 当天分钟

  static const _cell = 13.0;
  static const _gap = 3.0;
  static const _weeks = 26;

  Color _colorFor(int minutes, Color accent) {
    if (minutes <= 0) return AppColors.hairline;
    if (minutes <= 15) return accent.withValues(alpha: .25);
    if (minutes <= 30) return accent.withValues(alpha: .45);
    if (minutes <= 60) return accent.withValues(alpha: .70);
    return accent;
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final now = DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    final thisMonday = today0.subtract(Duration(days: today0.weekday - 1));
    final start = thisMonday.subtract(const Duration(days: 7 * (_weeks - 1)));

    String keyOf(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    // 月份标签行：某列周一的月份与前列不同时，在该列标注「M月」
    Widget monthLabels() {
      return SizedBox(
        height: 14,
        child: Row(
          children: [
            for (var c = 0; c < _weeks; c++)
              SizedBox(
                width: _cell + _gap,
                child: Builder(builder: (context) {
                  final monday = start.add(Duration(days: 7 * c));
                  final prev = monday.subtract(const Duration(days: 7));
                  final show = c > 0 && monday.month != prev.month;
                  return Text(show ? '${monday.month}月' : '',
                      style: TextStyle(
                          fontSize: 9, color: AppColors.faint));
                }),
              ),
          ],
        ),
      );
    }

    Widget weekColumn(int c) {
      return Column(
        children: [
          for (var d = 0; d < 7; d++)
            Builder(builder: (context) {
              final day = start.add(Duration(days: 7 * c + d));
              final future = day.isAfter(today0);
              final minutes =
                  future ? 0 : (minutesByDay[keyOf(day)] ?? 0);
              final cell = Container(
                width: _cell,
                height: _cell,
                margin: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  color: future
                      ? Colors.transparent
                      : _colorFor(minutes, accent),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
              if (future) return cell;
              return Tooltip(
                message:
                    '${day.month}月${day.day}日 · ${minutes >= 60 ? '${(minutes / 60).toStringAsFixed(1)} 小时' : '$minutes 分钟'}',
                child: cell,
              );
            }),
        ],
      );
    }

    Widget legend() {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Text('少',
                style: TextStyle(fontSize: 10, color: AppColors.faint)),
            for (final m in [0, 10, 25, 45, 90])
              Container(
                width: 11,
                height: 11,
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: _colorFor(m, accent),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            const Text('多',
                style: TextStyle(fontSize: 10, color: AppColors.faint)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          monthLabels(),
          Row(
            children: [
              for (var c = 0; c < _weeks; c++) weekColumn(c),
            ],
          ),
          legend(),
        ],
      ),
    );
  }
}
