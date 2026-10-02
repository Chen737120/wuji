import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/app_repository.dart' show ClassSaver;
import '../data/db.dart';
import '../services/stats.dart';
import '../theme.dart';
import 'widgets/charts.dart';

/// 首页统计面板（规格 §3.2）。
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  List<ClassRecord> _records = [];
  List<MediaAsset> _media = [];
  bool _loaded = false;
  StatRange _range = StatRange.all;
  DateTime? _customStart;
  DateTime? _customEnd;
  TrendMode _trendMode = TrendMode.daily;

  ClassSaver get _saver => context.read<ClassSaver>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await _saver.allRecords();
    final media = <MediaAsset>[];
    for (final r in records) {
      media.addAll(await _saver.mediaOf(r.id));
    }
    if (!mounted) return;
    setState(() {
      _records = records;
      _media = media;
      _loaded = true;
    });
  }

  StatsResult get _stats {
    final now = DateTime.now();
    final f = StatFilter(
      range: _range,
      start: _customStart,
      end: _customEnd,
    );
    return StatsComputer.compute(
        _records, _media, f, now,
        mode: _trendMode);
  }

  Future<void> _pickCustomRange() async {
    final initial = DateTime.now();
    final first = await showDatePicker(
      context: context,
      initialDate: _customStart ?? initial.subtract(const Duration(days: 30)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择开始日期',
    );
    if (first == null) return;
    final last = await showDatePicker(
      context: context,
      initialDate: _customEnd ?? initial,
      firstDate: first,
      lastDate: DateTime(2100),
      helpText: '选择结束日期',
    );
    if (last == null) return;
    setState(() {
      _customStart = first;
      _customEnd = last;
      _range = StatRange.custom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: _loaded && _records.isEmpty
            ? _emptyState(accent)
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                  children: [
                    _header(context),
                    const SizedBox(height: 10),
                    _filterChips(),
                    const SizedBox(height: 12),
                    _statCards(),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: _cardDecoration(),
                      child: TrendBars(
                        points: _stats.trend,
                        mode: _trendMode,
                        onModeChanged: (m) => setState(() => _trendMode = m),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: _cardDecoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('舞种分布',
                              style: TextStyle(
                                  fontSize: 11,
                                  letterSpacing: 2,
                                  color: AppColors.secondary)),
                          const SizedBox(height: 10),
                          StyleDonut(
                            slices: _stats.styleSlices,
                            totalSessions: _stats.sessionCount,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: _cardDecoration(),
                      child: NameBars(
                        title: '老师统计',
                        items: _stats.teacherStats,
                        totalSessions: _stats.sessionCount,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: _cardDecoration(),
                      child: NameBars(
                        title: '舞室统计',
                        items: _stats.studioStats,
                        totalSessions: _stats.sessionCount,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      );

  Widget _header(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Text('舞记',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4)),
            const SizedBox(width: 6),
            SizedBox(
              width: 30,
              height: 14,
              child: CustomPaint(painter: _LogoPainter(
                  Theme.of(context).colorScheme.primary)),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined,
              size: 20, color: AppColors.faint),
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('「我的」页在下一步接入'))),
        ),
      ],
    );
  }

  Widget _filterChips() {
    return Row(
      children: [
        for (final (label, range) in [
          ('全部', StatRange.all),
          ('近1月', StatRange.last30),
          ('近1年', StatRange.last365),
        ])
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: () => setState(() => _range = range),
              child: _chip(label, _range == range),
            ),
          ),
        GestureDetector(
          onTap: _pickCustomRange,
          child: _chip('自定义', _range == StatRange.custom),
        ),
      ],
    );
  }

  Widget _chip(String label, bool selected) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? AppColors.ink : AppColors.faint)),
        const SizedBox(height: 3),
        Container(
          height: 2,
          width: 28,
          decoration: BoxDecoration(
            color: selected ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ],
    );
  }

  Widget _statCards() {
    final s = _stats;
    final cards = [
      ('跳舞节数', '${s.sessionCount}'),
      ('跳舞时长', '${s.totalMinutes}'),
      ('跳舞天数', '${s.activeDays}'),
      ('视频·图片', '${s.mediaCount}'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 30,
                color: AppColors.hairline,
              ),
            Expanded(
              child: Column(
                children: [
                  Text(cards[i].$2,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()])),
                  const SizedBox(height: 2),
                  Text(cards[i].$1,
                      style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1,
                          color: AppColors.faint)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyState(Color accent) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 60,
            height: 28,
            child: CustomPaint(painter: _LogoPainter(accent)),
          ),
          const SizedBox(height: 16),
          const Text('还没有课堂记录',
              style: TextStyle(fontSize: 13, color: AppColors.secondary)),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              shape: const StadiumBorder(),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            onPressed: () {},
            child: const Text('去记录第一节课',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * 0.85)
      ..cubicTo(size.width * 0.25, size.height * 0.1, size.width * 0.4,
          size.height, size.width * 0.62, size.height * 0.4);
    path.cubicTo(size.width * 0.78, size.height * 0.15, size.width * 0.9,
        size.height * 0.35, size.width, size.height * 0.5);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.color != color;
}
