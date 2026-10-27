import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/stats.dart';
import '../../theme.dart';

/// 同色系加深（2026-10-08 需求 #4）：选中柱用点缀色向黑混合加深，
/// 保留原有色相（深绿），不跳到纯黑。
Color darkenChartColor(Color c, [double amount = .38]) =>
    Color.lerp(c, Colors.black, amount)!;

/// 跳舞趋势柱状图：非峰值柱 #ECECE8，峰值柱点缀色；顶部「按天 · 按月」切换。
/// 柱区可**左右滑动**查看按天（60 天）/按月（12 个月）的过往数据，
/// 进入/切换时自动定位到最右（最新）。
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
    // 只在模式切换（daily 60 根 / monthly 12 根）时定位到最右（P1-7）；
    // points 每次 build 都是新 List，引用比较恒真，会把用户左滑的历史位置弹回。
    if (old.mode != widget.mode) {
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
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, constraints) {
          // 柱区高度随卡片宽度自适应（夹在 96~168 之间，2026-10-08 需求 #4-1
          // 卡片整体纵向拉高），下方留 18 标签行
          final barH =
              (constraints.maxWidth * 0.44).clamp(96.0, 168.0).toDouble();
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
                                                        // 选中柱同色系加深（2026-10-08 需求 #4-3：
                                                        // 深绿等色相加深，不变纯黑）；其余柱
                                                        // 全部用点缀色
                                                        color: _selected ==
                                                                i
                                                            ? darkenChartColor(
                                                                accent)
                                                            : points[i].minutes >
                                                                    0
                                                                ? accent
                                                                : AppColors
                                                                    .hairline,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(3),
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
                                // 时长气泡（点击柱子时显示；2026-10-08 需求 #4-2
                                // 气泡尺寸与文字同步缩小一档）
                                if (_selected != null &&
                                    _selected! < points.length &&
                                    points[_selected!].minutes > 0)
                                  Positioned(
                                    top: 0,
                                    // clamp 到可视窗口（滚动到两端时气泡也可见）
                                    left: (_selected! * slotW +
                                            slotW / 2 -
                                            44)
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
                                                    88)),
                                    width: 88,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.ink
                                            .withValues(alpha: .88),
                                        borderRadius:
                                            BorderRadius.circular(7),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(points[_selected!].tooltip,
                                              textAlign: TextAlign.center,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 9,
                                                  color: Colors.white70)),
                                          Text(_minutesText(
                                              points[_selected!].minutes),
                                              textAlign: TextAlign.center,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 11,
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

/// 跳舞热力图（2026-10-08 需求 #3 改版）：**月历形式**——每页一个月，
/// 默认当前月，左右滑动或点箭头切换月份。格子颜色深浅=当天跳舞分钟数
/// （四档点缀色），今天描边，点按格子看当天详情；空=浅灰。
class DanceHeatmap extends StatefulWidget {
  const DanceHeatmap({super.key, required this.minutesByDay});

  final Map<String, int> minutesByDay; // 'yyyy-MM-dd' -> 当天分钟

  @override
  State<DanceHeatmap> createState() => _DanceHeatmapState();
}

class _DanceHeatmapState extends State<DanceHeatmap> {
  static int _indexOf(DateTime m) => (m.year - 2000) * 12 + (m.month - 1);
  static DateTime _monthOf(int page) => DateTime(2000, page + 1);

  late DateTime _shown;
  late PageController _pc;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _shown = DateTime(now.year, now.month);
    _pc = PageController(initialPage: _indexOf(_shown));
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final m = DateTime(_shown.year, _shown.month + delta);
    _pc.animateToPage(_indexOf(m),
        duration: const Duration(milliseconds: 250), curve: Curves.ease);
  }

  Color _colorFor(int minutes, Color accent) {
    if (minutes <= 0) return AppColors.hairline;
    if (minutes <= 15) return accent.withValues(alpha: .25);
    if (minutes <= 30) return accent.withValues(alpha: .45);
    if (minutes <= 60) return accent.withValues(alpha: .70);
    return accent;
  }

  String _minutesText(int m) =>
      m >= 60 ? '${(m / 60).toStringAsFixed(1)} 小时' : '$m 分钟';

  String _keyOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 年月切换行：‹ 2026年10月 ›（点箭头或直接左右滑动页面）
        Row(
          children: [
            IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _go(-1),
                icon: const Icon(Icons.chevron_left, size: 18)),
            Expanded(
              child: Center(
                child: Text('${_shown.year}年${_shown.month}月',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
            IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _go(1),
                icon: const Icon(Icons.chevron_right, size: 18)),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            for (final w in ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(
                child: Center(
                    child: Text(w,
                        style: TextStyle(fontSize: 10, color: AppColors.faint))),
              ),
          ],
        ),
        // 月页：高度=6 行格子（最大月行数），格子宽=可用宽/7
        LayoutBuilder(builder: (context, constraints) {
          final cell = constraints.maxWidth / 7;
          return SizedBox(
            height: cell * 6,
            child: PageView.builder(
              controller: _pc,
              onPageChanged: (page) =>
                  setState(() => _shown = _monthOf(page)),
              itemBuilder: (context, page) =>
                  _monthPage(_monthOf(page), accent),
            ),
          );
        }),
        // 图例（右对齐）
        Padding(
          padding: const EdgeInsets.only(top: 6),
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
        ),
      ],
    );
  }

  Widget _monthPage(DateTime month, Color accent) {
    final now = DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // 周一首列：Mon=1..Sun=7
    final leadingBlanks = (first.weekday + 6) % 7;

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1,
      padding: EdgeInsets.zero,
      children: [
        for (var i = 0; i < leadingBlanks; i++) const SizedBox(),
        for (var day = 1; day <= daysInMonth; day++)
          Builder(builder: (context) {
            final d = DateTime(month.year, month.month, day);
            final future = d.isAfter(today0);
            final isToday = d == today0;
            final minutes = future ? 0 : (widget.minutesByDay[_keyOf(d)] ?? 0);
            final bg = future ? Colors.transparent : _colorFor(minutes, accent);
            return Tooltip(
              message:
                  '${month.month}月$day日 · ${future ? '还没到' : _minutesText(minutes)}',
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(6),
                  border: isToday
                      ? Border.all(color: accent, width: 1.5)
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 10,
                    color: future
                        ? AppColors.faint
                        : (minutes > 60 ? Colors.white : AppColors.ink),
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}
