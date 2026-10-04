import 'package:flutter/material.dart';
import '../editing/fab_logic.dart';
import '../theme.dart';
import 'widgets/draggable_fab.dart';

/// 根路由深度广播：悬浮球只在三个根 tab 可见，进二级页隐藏（规格 §3）。
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
  @override
  void didPush(Route route, Route? previousRoute) {
    RootRouteTracker.instance.pushed();
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    RootRouteTracker.instance.popped();
  }
}

/// 底部导航骨架（规格 §3）：首页｜剪辑｜记录 三枚"图标＋文字" tab，
/// 无凹槽；全局可拖动悬浮球替代原中央＋号。
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.pages,
    required this.onFabPressed,
  });

  final List<Widget> pages; // [统计页, 剪辑页, 记录页]
  final VoidCallback? onFabPressed; // 悬浮球点击＝新增课

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _tabs = [
    (Icons.home_outlined, '首页'),
    (Icons.content_cut, '剪辑'),
    (Icons.calendar_month_outlined, '记录'),
  ];

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          IndexedStack(index: _tab, children: widget.pages),
          // 悬浮球：仅根 tab 可见（RootRouteObserver 汇报二级页深度）
          ListenableBuilder(
            listenable: RootRouteTracker.instance,
            builder: (context, _) {
              final visible = RootRouteTracker.instance.isRoot;
              return AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: visible ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !visible,
                  child: DraggableFab(
                    onTap: () => widget.onFabPressed?.call(),
                  ),
                ),
              );
            },
          ),
        ],
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
    return TextButton(
      onPressed: () => setState(() => _tab = idx),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 20,
              color: selected ? accent : AppColors.faint),
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
