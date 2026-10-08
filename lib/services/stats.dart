import '../data/db.dart' show ClassRecord, MediaAsset, ClassRecordRowX;

/// 统计口径（规格 §3.2，全部为纯函数，不依赖 Flutter）：
/// 跳舞节数 = Σ节数；时长 = Σ(节数×每节)；近1月=滚动30天、近1年=滚动365天（含今天）；
/// 分布/老师/舞室按节数；趋势按天=最近60天、按月=最近12个自然月
/// （2026-10-05 用户需求：图表可左右滑动查看过往数据，故趋势**不按范围过滤**，
/// 永远基于全量记录，未来日期不进趋势桶）。

enum StatRange { all, last30, last365, custom }

enum TrendMode { daily, monthly }

class StatFilter {
  const StatFilter({required this.range, this.start, this.end});

  final StatRange range;
  final DateTime? start; // custom 起（含）
  final DateTime? end; // custom 止（含）
}

class BarPoint {
  const BarPoint(this.label, this.minutes, {this.tooltip = ''});
  final String label;
  final int minutes; // 柱值=该桶内跳舞总时长（分钟）
  final String tooltip; // 点柱气泡的完整时间描述（如 10月7日 / 2026年9月）
}

class NameCount {
  const NameCount(this.name, this.sessions);
  final String name;
  final int sessions;
}

class StyleSlice {
  const StyleSlice(this.name, this.sessions, this.colorIndex,
      {required this.isOther});
  final String name;
  final int sessions;
  final int colorIndex; // 环形图取色阶梯序号
  final bool isOther;
}

class StatsResult {
  const StatsResult({
    required this.sessionCount,
    required this.totalMinutes,
    required this.activeDays,
    required this.mediaCount,
    required this.trend,
    required this.styleSlices,
    required this.teacherStats,
    required this.studioStats,
  });

  final int sessionCount;
  final int totalMinutes;
  final int activeDays;
  final int mediaCount;
  final List<BarPoint> trend;
  final List<StyleSlice> styleSlices;
  final List<NameCount> teacherStats;
  final List<NameCount> studioStats;
}

class StatsComputer {
  /// [records]/[media] 传全量，由本函数按 [f] 过滤。
  static StatsResult compute(
    List<ClassRecord> records,
    List<MediaAsset> media,
    StatFilter f,
    DateTime now, {
    TrendMode mode = TrendMode.daily,
  }) {
    final inRange = records.where((r) => _inRange(r, f, now)).toList();

    final sessionCount = inRange.fold<int>(0, (a, r) => a + r.sessionCount);
    final totalMinutes =
        inRange.fold<int>(0, (a, r) => a + r.totalMinutes);
    final activeDays = inRange.map((r) => r.date).toSet().length;

    final inRangeIds = inRange.map((r) => r.id).toSet();
    final mediaCount = media.where((m) => inRangeIds.contains(m.classId)).length;

    // 趋势基于全量记录（不随上方范围过滤）——滑动往左能看到更早的历史
    final trend = mode == TrendMode.daily
        ? _dailyTrend(records, now)
        : _monthlyTrend(records, now);

    return StatsResult(
      sessionCount: sessionCount,
      totalMinutes: totalMinutes,
      activeDays: activeDays,
      mediaCount: mediaCount,
      trend: trend,
      styleSlices: _styleSlices(inRange),
      teacherStats: _nameStats(inRange, (r) => r.teacherName),
      studioStats: _nameStats(inRange, (r) => r.studioName),
    );
  }

  static bool _inRange(ClassRecord r, StatFilter f, DateTime now) {
    final d = DateTime.parse(r.date);
    switch (f.range) {
      case StatRange.all:
        return true;
      case StatRange.last30:
        final start = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 29));
        // 不设上界：未来日期（补录笔误）计入总数，仅趋势桶排除（Review Focus #5）
        return !d.isBefore(start);
      case StatRange.last365:
        final start = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 364));
        return !d.isBefore(start);
      case StatRange.custom:
        final start = f.start!;
        final end = f.end!;
        final dayStart =
            DateTime(start.year, start.month, start.day);
        final dayEnd = DateTime(end.year, end.month, end.day, 23, 59, 59);
        return !d.isBefore(dayStart) && !d.isAfter(dayEnd);
    }
  }

  /// 最近 60 天（含今天），未来日期不入桶（桶锚定 now）。柱值=分钟。
  static List<BarPoint> _dailyTrend(List<ClassRecord> rs, DateTime now) {
    const days = 60;
    final today = DateTime(now.year, now.month, now.day);
    final buckets = List<int>.filled(days, 0);
    for (final r in rs) {
      final d = DateTime.parse(r.date);
      if (d.isAfter(today)) continue;
      final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
      if (diff >= 0 && diff < days) buckets[days - 1 - diff] += r.totalMinutes;
    }
    return List.generate(days, (i) {
      final day = today.subtract(Duration(days: days - 1 - i));
      return BarPoint('${day.day}', buckets[i],
          tooltip: '${day.month}月${day.day}日');
    });
  }

  /// 最近 12 个自然月（含本月），未来日期不入桶。柱值=分钟。
  static List<BarPoint> _monthlyTrend(List<ClassRecord> rs, DateTime now) {
    const months = 12;
    final thisMonth = DateTime(now.year, now.month);
    final keys = <String>[];
    final buckets = List<int>.filled(months, 0);
    for (var i = 0; i < months; i++) {
      final m = DateTime(thisMonth.year, thisMonth.month - (months - 1 - i));
      keys.add('${m.year}-${m.month}');
    }
    for (final r in rs) {
      final d = DateTime.parse(r.date);
      final dm = DateTime(d.year, d.month);
      if (dm.isAfter(thisMonth)) continue;
      final idx = keys.indexOf('${d.year}-${d.month}');
      if (idx >= 0) buckets[idx] += r.totalMinutes;
    }
    return List.generate(
        months,
        (i) => BarPoint('${keys[i].split('-')[1]}月', buckets[i],
            tooltip: '${keys[i].split('-')[0]}年${keys[i].split('-')[1]}月'));
  }

  /// 舞种分布：按节数降序取前 6，其余并入"其他"。
  static List<StyleSlice> _styleSlices(List<ClassRecord> rs) {
    final byName = <String, int>{};
    for (final r in rs) {
      final name = r.styleName;
      if (name == null || name.isEmpty) continue;
      byName[name] = (byName[name] ?? 0) + r.sessionCount;
    }
    final sorted = byName.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(6).toList();
    final restSessions =
        sorted.skip(6).fold<int>(0, (a, e) => a + e.value);
    final slices = <StyleSlice>[
      for (var i = 0; i < top.length; i++)
        StyleSlice(top[i].key, top[i].value, i, isOther: false),
    ];
    if (restSessions > 0) {
      slices.add(StyleSlice('其他', restSessions, slices.length, isOther: true));
    }
    return slices;
  }

  static List<NameCount> _nameStats(
      List<ClassRecord> rs, String? Function(ClassRecord) pick) {
    final byName = <String, int>{};
    for (final r in rs) {
      final name = pick(r);
      if (name == null || name.isEmpty) continue;
      byName[name] = (byName[name] ?? 0) + r.sessionCount;
    }
    final list = byName.entries.map((e) => NameCount(e.key, e.value)).toList()
      ..sort((a, b) => b.sessions.compareTo(a.sessions));
    return list;
  }
}
