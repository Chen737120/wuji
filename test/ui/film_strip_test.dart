import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/ui/widgets/film_strip.dart';

/// P3 补强：胶片条换视频时旧取帧循环不得回写（路径代际）。
void main() {
  test('staleFilmstripGeneration：代际不同即丢弃旧循环结果', () {
    expect(staleFilmstripGeneration(1, 1), isFalse);
    expect(staleFilmstripGeneration(1, 2), isTrue);
    expect(staleFilmstripGeneration(2, 1), isTrue);
  });

  testWidgets('换视频后重建不抛，且按 stripCount 渲染格子', (tester) async {
    var path = '/tmp/a.mp4';
    late StateSetter setOuter;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (ctx, setState) {
          setOuter = setState;
          return FilmStrip(
            videoPath: path,
            duration: const Duration(seconds: 10),
            position: Duration.zero,
            stripCount: 4,
            onSeek: (_) {},
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 换视频：旧循环（测试环境取帧必失败）的结果不得让重建抛异常
    setOuter(() => path = '/tmp/b.mp4');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Image), findsNothing); // 取帧不可用 → 纯色占位
  });

  testWidgets('duration=0 不触发取帧、只渲染占位', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FilmStrip(
          videoPath: '/tmp/x.mp4',
          duration: Duration.zero,
          position: Duration.zero,
          stripCount: 3,
          onSeek: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Image), findsNothing);
  });
}
