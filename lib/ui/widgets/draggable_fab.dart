import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../editing/fab_logic.dart';
import '../../theme.dart';

/// 可拖动悬浮球（规格 §3）：48dp 翠芽圆＋白＋。
/// 初始右下、松手贴边吸附、位置持久化 key `fabOffset`；点击=新增课。
/// 仅三个根 tab 可见：HomeShell 的 Stack 监听 [RootRouteTracker] 控制挂载。
class DraggableFab extends StatefulWidget {
  const DraggableFab({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<DraggableFab> createState() => _DraggableFabState();
}

class _DraggableFabState extends State<DraggableFab> {
  static const _key = 'fabOffset';
  static const _ballSize = Size(64, 64);

  Offset _offset = Offset.zero;
  bool _loaded = false;
  bool _dragging = false;

  bool _restoreRequested = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_restoreRequested) {
      _restoreRequested = true;
      _restore();
    }
  }

  Future<void> _restore() async {
    final screenAtStart = MediaQuery.sizeOf(context);
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    var restored = FabLogic.initialOffset(screenAtStart, _ballSize);
    if (raw != null) {
      final parts = raw.split(',');
      if (parts.length == 2) {
        final dx = double.tryParse(parts[0]);
        final dy = double.tryParse(parts[1]);
        if (dx != null && dy != null) restored = Offset(dx, dy);
      }
    }
    if (!mounted) return;
    setState(() {
      _offset = FabLogic.clampIntoScreen(
          restored, screenAtStart, _ballSize);
      _loaded = true;
    });
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, '${_offset.dx},${_offset.dy}');
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    if (!_loaded) return const SizedBox.shrink();
    return Positioned(
      left: _offset.dx,
      top: _offset.dy,
      child: GestureDetector(
        onPanStart: (_) => setState(() => _dragging = true),
        onPanUpdate: (d) {
          setState(() {
            _offset = FabLogic.clampIntoScreen(
                _offset + d.delta, MediaQuery.sizeOf(context), _ballSize);
          });
        },
        onPanEnd: (d) {
          setState(() {
            _offset = FabLogic.snapEdge(
                _offset, MediaQuery.sizeOf(context), _ballSize);
            _dragging = false;
          });
          _persist();
        },
        onTap: widget.onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: accent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: .18),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            _dragging ? Icons.open_with : Icons.add,
            color: Colors.white,
            size: _dragging ? 26 : 38,
          ),
        ),
      ),
    );
  }
}
