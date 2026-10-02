import 'package:flutter/material.dart';
import '../theme.dart';

/// 底部三区骨架：首页 ｜ ＋ ｜ 记录（规格 §3.1）。
/// ＋是浮动大按钮不占 tab；fabDestination 保留给后续任务接线。
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.pages,
    required this.onFabPressed,
    this.fabDestination = 0,
  });

  final List<Widget> pages; // [统计页, 记录页]
  final int fabDestination;
  final VoidCallback? onFabPressed;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0; // 0 首页 1 记录页

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(index: _tab, children: widget.pages),
      floatingActionButton: FloatingActionButton(
        backgroundColor: accent,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 30, color: Colors.white),
        onPressed: () {
          widget.onFabPressed?.call();
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: AppColors.bg,
        elevation: 0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _tabBtn('首页', 0),
            const SizedBox(width: 56),
            _tabBtn('记录', 1),
          ],
        ),
      ),
    );
  }

  Widget _tabBtn(String label, int idx) => TextButton(
        onPressed: () => setState(() => _tab = idx),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: _tab == idx ? FontWeight.w700 : FontWeight.w400,
            color: _tab == idx ? AppColors.ink : AppColors.faint,
          ),
        ),
      );
}
