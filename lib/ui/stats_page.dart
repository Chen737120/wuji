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

class _StatsPageState extends State<StatsPage>
    with WidgetsBindingObserver {
  List<ClassRecord> _records = [];
  List<MediaAsset> _media = [];
  bool _loaded = false;
  // 2026-10-07 需求 #4：默认显示全部数据
  StatRange _range = StatRange.all;
  DateTime? _customStart;
  DateTime? _customEnd;
  TrendMode _trendMode = TrendMode.daily;

  // 2026-10-07 需求 #5：每次重新打开软件，选择状态恢复默认
  bool _wasPaused = false;

  ClassSaver get _saver => context.read<ClassSaver>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    ReloadBus.instance.addListener(_load);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ReloadBus.instance.removeListener(_load);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasPaused = true;
    } else if (state == AppLifecycleState.resumed && _wasPaused) {
      _wasPaused = false;
      if (!mounted) return;
      setState(() {
        _range = StatRange.all;
        _customStart = null;
        _customEnd = null;
        _trendMode = TrendMode.daily;
      });
    }
  }

  Future<void> _load() async {
    final records = await _saver.allRecords();
    // 一次查询取回全部附件（评审建议：替代逐课 N+1 查询）
    final byClass = await _saver.mediaByClass();
    final media = <MediaAsset>[
      for (final list in byClass.values) ...list,
    ];
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
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink)),
                    const SizedBox(height: 10),
                    StyleDonut(
                      slices: _stats.styleSlices,
                      totalSessions: _stats.sessionCount,
                      accent: Theme.of(context).colorScheme.primary,
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
              // 跳舞热力图（2026-10-08 需求 #8）：最近 26 周，
              // 颜色深浅=当天跳舞分钟数（基于全量记录，不随范围筛选）
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: _cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('跳舞热力图',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink)),
                    const SizedBox(height: 12),
                    DanceHeatmap(minutesByDay: _minutesByDay),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 日期 -> 当天跳舞分钟（热力图数据源；全量记录）。
  Map<String, int> get _minutesByDay {
    final map = <String, int>{};
    for (final r in _records) {
      map[r.date] = (map[r.date] ?? 0) + r.totalMinutes;
    }
    return map;
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
    // 顶部图标（2026-10-07 用户需求 #6，借鉴软件样式：浅色圆底+彩色图标）
    final cards = [
      (
        Icons.music_note,
        const Color(0xFFFDE7EF),
        const Color(0xFFEC6FA5),
        '跳舞节数',
        '${s.sessionCount}',
        '节'
      ),
      (
        Icons.local_fire_department,
        const Color(0xFFFFEDE3),
        const Color(0xFFF0641E),
        '跳舞时长',
        _hours(s.totalMinutes),
        '小时'
      ),
      (
        Icons.calendar_month,
        const Color(0xFFFDEFDD),
        const Color(0xFFF08C1E),
        '跳舞天数',
        '${s.activeDays}',
        '天'
      ),
      (
        Icons.videocam,
        const Color(0xFFE2F5E7),
        const Color(0xFF34B04A),
        '视频·图片',
        '${s.mediaCount}',
        '个'
      ),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 44,
                color: AppColors.hairline,
              ),
            Expanded(
              child: Column(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: cards[i].$2,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(cards[i].$1, size: 20, color: cards[i].$3),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(cards[i].$5,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()])),
                      const SizedBox(width: 2),
                      Text(cards[i].$6,
                          style: TextStyle(
                              fontSize: 10, color: AppColors.faint)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(cards[i].$4,
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
