import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/ui/widgets/app_route.dart';

// T4 spike 验证（任务书 §T4）：弹簧转场基本行为契约。
// 右滑返回手势松手回弹/Hero 飞行属于真机走查项（附B）。
void main() {
  Future<void> pumpRoot(WidgetTester tester, GlobalKey<NavigatorState> navKey) {
    return tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: Text('root')),
    ));
  }

  testWidgets('push 弹簧驱动：120ms 时处于 (0,1)，终态到 1', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await pumpRoot(tester, navKey);
    final route =
        AppRoute(builder: (_) => const Scaffold(body: Text('detail')));
    navKey.currentState!.push(route);
    await tester.pump(); // 激活转场
    await tester.pump(const Duration(milliseconds: 120));
    expect(route.animation!.value, greaterThan(0.0));
    expect(route.animation!.value, lessThan(1.0)); // 证明是动画而非瞬切
    await tester.pumpAndSettle();
    // 弹簧收尾停在 isDone 容差内（实测 0.99996），不要求精确 1.0
    expect(route.animation!.value, closeTo(1.0, 0.001));
    expect(find.text('detail'), findsOneWidget);
  });

  testWidgets('pop 弹簧驱动：转场中 pop 仍正确收场', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await pumpRoot(tester, navKey);
    navKey.currentState!.push(
        AppRoute(builder: (_) => const Scaffold(body: Text('detail'))));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);

    navKey.currentState!.pop();
    await tester.pump(); // 激活 pop 转场
    await tester.pump(const Duration(milliseconds: 100));
    // pop 转场中 detail 仍在树上（转场未完）
    expect(find.text('detail'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    expect(find.text('root'), findsOneWidget);
  });

  testWidgets('快速连开连关：push 未完成即 pop，无跳变收场', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await pumpRoot(tester, navKey);
    navKey.currentState!.push(
        AppRoute(builder: (_) => const Scaffold(body: Text('detail'))));
    await tester.pump(const Duration(milliseconds: 150)); // push 转场中途
    navKey.currentState!.pop(); // 立即 pop
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    expect(find.text('root'), findsOneWidget);
  });

  testWidgets('disableAnimations：push/pop 瞬切（修前 450ms 弹簧）', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: const Scaffold(body: Text('root')),
    ));
    final route =
        AppRoute(builder: (_) => const Scaffold(body: Text('detail')));
    navKey.currentState!.push(route);
    await tester.pump();
    expect(route.animation!.isCompleted, isTrue); // 修前为 false
    expect(find.text('detail'), findsOneWidget);

    // pop 也瞬切：一帧后 detail 已从树上移除（修前 400ms 反向弹簧仍在，会 findsOneWidget）
    navKey.currentState!.pop();
    await tester.pump();
    expect(find.text('detail'), findsNothing);
  });

  testWidgets('Hero 飞行与弹簧转场兼容：push/pop 均无异常收场', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: Scaffold(
        body: Hero(
          tag: 'record-cover-1',
          child: const SizedBox(width: 80, height: 60, child: Text('cover')),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    navKey.currentState!.push(AppRoute(
        builder: (_) => Scaffold(
              body: Hero(
                tag: 'record-cover-1',
                child:
                    const SizedBox(width: 300, height: 200, child: Text('cover')),
              ),
            )));
    await tester.pump(); // Hero 起飞帧
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    navKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 回到底层页：root 里的 Hero 内容仍在（原断言查的 'detail' 两边都不存在）
    expect(find.text('cover'), findsOneWidget);
  });
}
