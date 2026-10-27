import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/services/stats.dart';
import 'package:wuji/ui/widgets/charts.dart';

/// 统计图表边界（P3 补强）：空数据不画 5 个 0、donut 空态、热力图翻月不崩。
void main() {
  testWidgets('趋势图空数据：纵轴只有一个 0 刻度', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 240,
          child: TrendBars(
            points: [],
            mode: TrendMode.daily,
            onModeChanged: _noop,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // P3-7：旧实现 5 个刻度全为 0（[0,0,0,0,0]）
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('趋势图单点峰值：纵轴 5 个刻度且峰值可见', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 240,
          child: TrendBars(
            points: [BarPoint('1', 40)],
            mode: TrendMode.daily,
            onModeChanged: _noop,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('40'), findsOneWidget); // 峰值刻度
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('舞种分布空态：0 种占位，无图例项，不抛', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: StyleDonut(
          slices: [],
          totalSessions: 0,
          accent: Colors.green,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('0种'), findsOneWidget);
    expect(find.text('舞种分布'), findsOneWidget);
    expect(find.textContaining('节）', findRichText: true), findsNothing);
  });

  testWidgets('热力图空数据翻月：标题跟随且不抛', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 480,
          child: DanceHeatmap(minutesByDay: {}),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    String label(DateTime m) => '${m.year}年${m.month}月';
    expect(find.text(label(DateTime(now.year, now.month))), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    final next = DateTime(now.year, now.month + 1);
    expect(find.text(label(next)), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text(label(DateTime(now.year, now.month))), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _noop(TrendMode _) {}
