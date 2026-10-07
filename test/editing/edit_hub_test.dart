import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wuji/ui/edit_hub_page.dart';
import 'package:wuji/ui/home_shell.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('剪辑落地页两张入口卡＋页脚说明', (tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var fancam = false, compare = false;
    await tester.pumpWidget(MaterialApp(
        home: EditHubPage(onFancam: () => fancam = true,
            onCompare: () => compare = true)));
    await tester.pumpAndSettle();

    expect(find.text('舞蹈直拍'), findsOneWidget);
    expect(find.text('同屏对比'), findsOneWidget);
    expect(find.text('生成的视频保存在相册，原始课堂记录不受影响'), findsOneWidget);

    await tester.tap(find.text('舞蹈直拍'));
    expect(fancam, isTrue);
    await tester.tap(find.text('同屏对比'));
    expect(compare, isTrue);
  });

  testWidgets('HomeShell 三 tab：首页｜剪辑｜统计，悬浮球可见', (tester) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    var fabTapped = false;
    await tester.pumpWidget(MaterialApp(
        home: HomeShell(
            pages: [
              SizedBox(),
              EditHubPage(),
              SizedBox(),
            ],
            onFabPressed: () => fabTapped = true)));
    await tester.pumpAndSettle();

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('剪辑'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(find.byIcon(Icons.content_cut), findsOneWidget);

    // 切到剪辑 tab
    await tester.tap(find.text('剪辑'));
    await tester.pumpAndSettle();
    expect(find.text('舞蹈直拍'), findsOneWidget);
    expect(find.text('同屏对比'), findsOneWidget);
    // 切回首页，无空态图表干扰
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();

    // 悬浮球点击 = 新增课
    await tester.tap(find.byIcon(Icons.add));
    expect(fabTapped, isTrue);
  });

  testWidgets('进二级页悬浮球隐藏，返回恢复', (tester) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      navigatorObservers: [RootRouteObserver()],
      home: HomeShell(
        pages: [
          SizedBox(),
          EditHubPage(
            onFancam: () => Navigator.push(navKey.currentContext!,
                MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar()))),
            onCompare: null,
          ),
          SizedBox(),
        ],
        onFabPressed: null,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add), findsOneWidget);

    await tester.tap(find.text('剪辑'));
    await tester.pumpAndSettle();
    // 从剪辑 tab push 一个二级页
    await tester.tap(find.text('舞蹈直拍'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add), findsNothing); // 隐藏

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add), findsOneWidget); // 恢复
  });
}
