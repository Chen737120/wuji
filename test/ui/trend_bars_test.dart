import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/services/stats.dart';
import 'package:wuji/ui/widgets/charts.dart';

/// P1-7：趋势图滚动位置只应在模式切换时回到最右，
/// 父级重建（points 每次都是新 List）不得把用户左滑的历史位置弹回。
void main() {
  testWidgets('父级重建不重置滚动位置；切模式才跳到最右', (tester) async {
    // 30 个点：daily 60 根的半量，保证 300px 宽下必然横向溢出
    final basePoints = [
      for (var i = 0; i < 30; i++) BarPoint('${i + 1}', (i % 6) * 8 + 10),
    ];
    var mode = TrendMode.daily;
    var points = basePoints;
    late StateSetter setOuter;
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 300,
          height: 220,
          child: StatefulBuilder(builder: (ctx, setState) {
            setOuter = setState;
            return TrendBars(
              points: points,
              mode: mode,
              onModeChanged: (_) {},
            );
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final pos = tester
        .state<ScrollableState>(find
            .descendant(
                of: find.byType(TrendBars), matching: find.byType(Scrollable))
            .first)
        .position;
    // 前置断言：数据量不足时滚动断言会平凡通过，本用例即无效
    expect(pos.maxScrollExtent, greaterThan(0),
        reason: '数据量不足，滚动断言会平凡通过');

    // 用例 1：用户左滑到最左，父级用同内容新 List 重建 → 位置不弹回
    pos.jumpTo(0);
    await tester.pump();
    setOuter(() {
      // 同内容新 List（模拟 stats_page 每次 build 新建）
      points = [
        for (final p in basePoints)
          BarPoint(p.label, p.minutes, tooltip: p.tooltip),
      ];
    });
    await tester.pumpAndSettle();
    expect(pos.pixels, 0, reason: '父级重建不应重置滚动位置（P1-7）');

    // 用例 2：切到按月 → 定位到最右
    setOuter(() => mode = TrendMode.monthly);
    await tester.pumpAndSettle();
    expect(pos.pixels, pos.maxScrollExtent);
  });
}
