import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/overlap.dart';

void main() {
  group('OverlapCalc（规格 §4.2 偏移语义：正值＝我的视频延后）', () {
    test('offset=0：整段重叠', () {
      final start = OverlapCalc.start(Duration.zero);
      final end = OverlapCalc.end(
          const Duration(seconds: 60), const Duration(seconds: 60), Duration.zero);
      expect(start, Duration.zero);
      expect(end, const Duration(seconds: 60));
    });

    test('offset>0（我的延后）：区间从 offset 起', () {
      // 我的视频 60s、延后 10s → 老师先出画 10s
      // 重叠区间 = [max(0,offset), min(teacherDur, myDur+offset))
      //         = [10s, min(60, 70)) = [10s, 60s)
      final start = OverlapCalc.start(const Duration(seconds: 10));
      final end = OverlapCalc.end(const Duration(seconds: 60),
          const Duration(seconds: 60), const Duration(seconds: 10));
      expect(start, const Duration(seconds: 10));
      expect(end, const Duration(seconds: 60));
    });

    test('offset<0（我的提前）：区间从 0 起、终点含我的偏移', () {
      // 我的提前 10s：老师 60s、我的 60s → [0, min(60, 60-10)) = [0, 50s)
      final start = OverlapCalc.start(const Duration(seconds: -10));
      final end = OverlapCalc.end(const Duration(seconds: 60),
          const Duration(seconds: 60), const Duration(seconds: -10));
      expect(start, Duration.zero);
      expect(end, const Duration(seconds: 50));
    });

    test('超长 offset 把区间顶成 0 → 不可导出', () {
      final start = OverlapCalc.start(const Duration(seconds: 120));
      final end = OverlapCalc.end(const Duration(seconds: 60),
          const Duration(seconds: 60), const Duration(seconds: 120));
      expect(end, start); // 区间为 0
      expect(OverlapCalc.exportable(end, start), isFalse);
    });

    test('exportable：重叠 ≥1s 才可导出', () {
      expect(
          OverlapCalc.exportable(const Duration(seconds: 1), Duration.zero),
          isTrue);
      expect(
          OverlapCalc.exportable(
              const Duration(milliseconds: 900), Duration.zero),
          isFalse);
    });
  });
}
