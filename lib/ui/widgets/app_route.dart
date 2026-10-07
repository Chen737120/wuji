import 'package:flutter/cupertino.dart';

/// 全局自定义转场（2026-10-05 用户需求 #7）：
/// - Hero 元素（如记录卡片封面）由 Navigator 内置 HeroController 驱动，
///   "卡片展开成详情页 / 返回收缩回卡片"——飞行时长跟随 [transitionDuration]；
/// - 非 Hero 元素（背景、正文）用 FadeTransition 淡入淡出兜底；
/// - 曲线 easeOutQuint、时长 450ms（返回 400ms），无第三方包；
/// - 混入 CupertinoRouteTransitionMixin：iOS 边缘右滑返回可用，
///   手势中断时 Hero 与页面动画自动回弹（框架行为）。
///
/// Hero tag 命名规范：`<对象类型>-<业务字段>-<唯一id>`，例如
/// `record-cover-<记录id>`、`record-title-<记录id>`——同一次导航
/// 源/目标页各放一个同 tag 的 Hero；列表页多卡片用记录 id（**不要用
/// index**：滚动/增删后 index 会变，跨页 tag 配对会错）。
class AppRoute<T> extends PageRoute<T> with CupertinoRouteTransitionMixin<T> {
  AppRoute({required this.builder});

  final WidgetBuilder builder;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 450);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 400);

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  String? get title => null;

  @override
  bool get maintainState => true;

  // CupertinoRouteTransitionMixin 的页面构建入口（mixin 的 buildPage 调它）
  @override
  Widget buildContent(BuildContext context) {
    return builder(context);
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    // 非 Hero 元素的淡入（Hero 飞行不受影响，由框架接管）
    final fade = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutQuint,
        reverseCurve: Curves.easeInQuart);
    return FadeTransition(
      opacity: fade,
      child: super.buildTransitions(context, animation, secondaryAnimation, child),
    );
  }
}
