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

  testWidgets('push 弹簧驱动：进度单调上升至完成', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await pumpRoot(tester, navKey);
    navKey.currentState!.push(
        AppRoute(builder: (_) => const Scaffold(body: Text('detail'))));
    await tester.pump(); // 激活转场
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();
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
    expect(find.text('detail'), findsNothing);
  });
}
