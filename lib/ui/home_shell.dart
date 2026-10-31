import 'package:flutter/material.dart';
import '../editing/fab_logic.dart';
import '../theme.dart';
import 'widgets/draggable_fab.dart';

/// 根路由深度广播：悬浮球只在四个根 tab 可见，进二级页隐藏（规格 §3）。
class RootRouteTracker extends ChangeNotifier {
  RootRouteTracker._();
  static final RootRouteTracker instance = RootRouteTracker._();

  int _depth = 1;
  bool get isRoot => _depth <= 1;

  void _set(int d) {
    final clamped = d < 1 ? 1 : d;
    if (clamped == _depth) return;
    _depth = clamped;
    notifyListeners();
  }

  void pushed() => _set(_depth + 1);
  void popped() => _set(_depth - 1);
}

class RootRouteObserver extends NavigatorObserver {
  bool _homeCounted = false;

  @override
  void didPush(Route route, Route? previousRoute) {
    // MaterialApp 启动时 home 路由的首次 push 不计数（深度从 1 起）
    if (!_homeCounted) {
      _homeCounted = true;
      return;
    }
    RootRouteTracker.instance.pushed();
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    // home 路由不会被 pop；防御：深度不低于 1（tracker 内部 clamp）
    RootRouteTracker.instance.popped();
  }
}

/// 底部导航骨架（规格 §3；2026-10-31 UI 精修 T2）：记录｜剪辑｜统计｜我的
/// 四枚"图标＋文字" tab，默认落在记录页；无凹槽；
/// 全局可拖动悬浮球替代原中央＋号。
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.pages,
    required this.onFabPressed,
  });

  final List<Widget> pages; // [记录页, 剪辑页, 统计页, 我的页]
  final VoidCallback? onFabPressed; // 悬浮球点击＝新增课

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with SingleTickerProviderStateMixin {
  int _tab = 0; // 默认：记录页

  static const _tabs = [
    (Icons.calendar_month_outlined, '记录'),
    (Icons.content_cut, '剪辑'),
    (Icons.pie_chart_outline, '统计'),
    (Icons.person_outlined, '我的'),
  ];

  // 选中图标 bump：1→1.14(40%)→1，340ms，轻过冲（原型 @keyframes bump）
  late final AnimationController _bump = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );
  static final Animatable<double> _bumpScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.14)
          .chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.14, end: 1.0)
          .chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 60,
    ),
  ]);

  @override
  void dispose() {
    _bump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ListenableBuilder(
        listenable: RootRouteTracker.instance,
        builder: (context, _) => Stack(
          children: [
            IndexedStack(index: _tab, children: widget.pages),
            // 悬浮球：仅根 tab 挂载（进二级页从 Stack 移除，Positioned 必须是
            // Stack 的直接子级，所以可见性控制在外层）
            if (RootRouteTracker.instance.isRoot)
              DraggableFab(onTap: () => widget.onFabPressed?.call()),
          ],
        ),
      ),
      bottomNavigationBar: SizedBox(
        height: FabLogic.bottomBarHeight,
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++)
              Expanded(child: Center(child: _tabBtn(context, i))),
          ],
        ),
      ),
    );
  }

  Widget _tabBtn(BuildContext context, int idx) {
    final selected = _tab == idx;
    final accent = Theme.of(context).colorScheme.primary;
    final (icon, label) = _tabs[idx];
    Widget iconWidget = Icon(icon,
        size: 20, color: selected ? accent : AppColors.faint);
    if (selected) {
      iconWidget = ScaleTransition(
        scale: _bumpScale.animate(_bump),
        child: iconWidget,
      );
    }
    return TextButton(
      onPressed: () {
        if (_tab == idx) return;
        setState(() => _tab = idx);
        _bump.forward(from: 0);
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          iconWidget,
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? AppColors.ink : AppColors.faint,
              )),
        ],
      ),
    );
  }
}
