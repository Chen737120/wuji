import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/data/db.dart' show ClassRecord, MediaAsset;
import 'package:wuji/services/stats.dart';

void main() {
  final now = DateTime(2026, 9, 30, 12);

  Iterable<ClassRecord> rec(int daysAgo, int sessions, int minutesEach,
      {String? style, String? teacher, String? studio}) sync* {
    final d = now.subtract(Duration(days: daysAgo));
    yield ClassRecord(
      id: 'r$daysAgo-$style-$sessions-$minutesEach',
      date: '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      styleName: style,
      teacherName: teacher,
      studioName: studio,
      sessionCount: sessions,
      minutesEach: minutesEach,
      createdAt: d,
      updatedAt: d,
    );
  }

  test('session totals are sums of sessionCount, minutes are products', () {
    final rs = [
      ...rec(0, 2, 90, style: '爵士'),
      ...rec(3, 1, 60, style: '韩舞'),
    ];
    final s = StatsComputer.compute(
        rs, const [], StatFilter(range: StatRange.all), now);
    expect(s.sessionCount, 3);
    expect(s.totalMinutes, 240);
    expect(s.activeDays, 2);
  });

  test('last30 is rolling 30 days including today, excludes older', () {
    final rs = [...rec(29, 1, 60), ...rec(30, 1, 60)];
    final s = StatsComputer.compute(
        rs, const [], StatFilter(range: StatRange.last30), now);
    expect(s.sessionCount, 1); // daysAgo=30 的那条被排除
  });

  test('last365 excludes beyond one year', () {
    final rs = [...rec(364, 1, 60), ...rec(365, 1, 60)];
    final s = StatsComputer.compute(
        rs, const [], StatFilter(range: StatRange.last365), now);
    expect(s.sessionCount, 1);
  });

  test('custom range filters by start/end dates inclusive', () {
    final rs = [...rec(1, 1, 60), ...rec(5, 1, 60), ...rec(10, 1, 60)];
    final f = StatFilter(
      range: StatRange.custom,
      start: now.subtract(const Duration(days: 7)),
      end: now,
    );
    final s = StatsComputer.compute(rs, const [], f, now);
    expect(s.sessionCount, 2); // daysAgo=1、5 在界内，10 出界
  });

  test('future-dated records do not shift daily trend window', () {
    final rs = [...rec(0, 1, 60), ...rec(-5, 3, 60)]; // daysAgo=-5 是未来
    final s = StatsComputer.compute(rs, const [],
        StatFilter(range: StatRange.last30), now,
        mode: TrendMode.daily);
    // 2026-10-05：趋势扩到 60 天可滑动
    expect(s.trend, hasLength(60));
    expect(s.trend.last.minutes, 60); // 今天：1节×60分
    expect(s.trend.any((b) => b.minutes == 180), isFalse); // 未来的3节×60不入桶
    expect(s.sessionCount, 4); // 统计总数仍含未来记录
  });

  test('monthly trend covers 12 calendar months', () {
    final rs = [
      ...rec(0, 1, 60),
      ...rec(40, 2, 60), // 两个月前
    ];
    final s = StatsComputer.compute(rs, const [],
        StatFilter(range: StatRange.last365), now,
        mode: TrendMode.monthly);
    expect(s.trend, hasLength(12));
    expect(s.trend.last.minutes, 60); // 本月：1节×60分
    expect(s.trend.any((b) => b.minutes == 120), isTrue); // 两个月前2节×60分
  });

  test('style distribution caps at 6 slices + 其他 by sessions', () {
    final rs = [
      ...rec(1, 3, 60, style: 'A'),
      ...rec(2, 2, 60, style: 'B'),
      ...rec(3, 2, 60, style: 'C'),
      ...rec(4, 2, 60, style: 'D'),
      ...rec(5, 2, 60, style: 'E'),
      ...rec(6, 2, 60, style: 'F'),
      ...rec(7, 1, 60, style: 'G'),
      ...rec(8, 1, 60, style: 'H'),
    ];
    final s = StatsComputer.compute(
        rs, const [], StatFilter(range: StatRange.all), now);
    expect(s.styleSlices.length, 7); // 6 + 其他
    expect(s.styleSlices.last.isOther, isTrue);
    expect(s.styleSlices.last.sessions, 2);
    expect(s.styleSlices.first.sessions, 3);
  });

  test('teacher/studio stats sorted desc by sessions, null-named skipped', () {
    final rs = [
      ...rec(1, 1, 60, teacher: '小鹿'),
      ...rec(2, 2, 60, teacher: '阿哲'),
      ...rec(3, 1, 60), // 无老师
    ];
    final s = StatsComputer.compute(
        rs, const [], StatFilter(range: StatRange.all), now);
    expect(s.teacherStats.first.name, '阿哲');
    expect(s.teacherStats.first.sessions, 2);
    expect(s.teacherStats, hasLength(2));
  });

  test('mediaCount counts media of records in range only', () {
    final r = rec(1, 1, 60).first;
    final out = rec(100, 1, 60).first;
    final media = [
      MediaAsset(
          id: 'm1',
          classId: r.id,
          type: 'video',
          fileName: 'a.mp4',
          sizeBytes: 1,
          createdAt: now),
      MediaAsset(
          id: 'm2',
          classId: out.id,
          type: 'video',
          fileName: 'b.mp4',
          sizeBytes: 1,
          createdAt: now),
    ];
    final s = StatsComputer.compute(
        [r, out], media, StatFilter(range: StatRange.last30), now);
    expect(s.mediaCount, 1);
  });
}
