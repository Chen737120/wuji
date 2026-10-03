import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/app_repository.dart' show ClassSaver;
import '../data/db.dart';
import '../reload_bus.dart';
import '../services/stats.dart';
import '../theme.dart';
import 'my_page.dart';
import 'sheets/date_range_sheet.dart';
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
  StatRange _range = StatRange.last30; // 默认看近 1 个月
  DateTime? _customStart;
  DateTime? _customEnd;
  TrendMode _trendMode = TrendMode.daily;

  ClassSaver get _saver => context.read<ClassSaver>();

  @override
  void initState() {
    super.initState();
    _load();
    ReloadBus.instance.addListener(_load);
  }

  @override
  void dispose() {
    ReloadBus.instance.removeListener(_load);
    super.dispose();
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
    final r = await showDateRangeSheet(
      context,
      initialStart: _customStart,
      initialEnd: _customEnd,
    );
    if (r == null || !mounted) return;
    setState(() {
      _customStart = r.$1;
      _customEnd = r.$2;
      _range = StatRange.custom;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
            children: [
              _header(context),
              const SizedBox(height: 10),
              _filterChips(),
              if (_loaded && _records.isEmpty) ...[
                const SizedBox(height: 12),
                _emptyHint(),
              ],
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
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const MyPage())),
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

  /// 时长分钟 → 小时显示（整除不带小数，否则保留 1 位）
  String _hours(int minutes) {
    final v = minutes / 60;
    return v == v.roundToDouble()
        ? v.round().toString()
        : v.toStringAsFixed(1);
  }

  Widget _statCards() {
    final s = _stats;
    final cards = [
      ('跳舞节数', '${s.sessionCount}', '节'),
      ('跳舞时长', _hours(s.totalMinutes), '小时'),
      ('跳舞天数', '${s.activeDays}', '天'),
      ('视频·图片', '${s.mediaCount}', '个'),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(cards[i].$2,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()])),
                      const SizedBox(width: 2),
                      Text(cards[i].$3,
                          style: TextStyle(
                              fontSize: 10, color: AppColors.faint)),
                    ],
                  ),
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

  /// 无记录时图表照常展示（全零），仅加一条引导。
  Widget _emptyHint() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: _cardDecoration(),
      alignment: Alignment.center,
      child: const Text('还没有课堂记录，点下方 ＋ 记录第一节课',
          style: TextStyle(fontSize: 12, color: AppColors.secondary)),
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
