import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../editing/fab_logic.dart';
import '../../theme.dart';

/// 可拖动悬浮球（规格 §3）：48dp 翠芽圆＋白＋。
/// 初始右下、松手贴边吸附、位置持久化 key `fabOffset`；点击=新增课。
class DraggableFab extends StatefulWidget {
  const DraggableFab({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<DraggableFab> createState() => _DraggableFabState();
}

class _DraggableFabState extends State<DraggableFab> {
  static const _key = 'fabOffset';
  Offset _offset = Offset.zero;
  bool _loaded = false;
  bool _dragging = false;

  Size get _screen => MediaQuery.sizeOf(context);

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    var restored = FabLogic.initialOffset(
        MediaQuery.sizeOf(context), const Size(48, 48));
    if (raw != null) {
      final parts = raw.split(',');
      if (parts.length == 2) {
        final dx = double.tryParse(parts[0]);
        final dy = double.tryParse(parts[1]);
        if (dx != null && dy != null) {
          restored = Offset(dx, dy);
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _offset = FabLogic.clampIntoScreen(
          restored, MediaQuery.sizeOf(context), const Size(48, 48));
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
    return _loaded
        ? Positioned(
            left: _offset.dx,
            top: _offset.dy,
            child: GestureDetector(
              onPanStart: (_) => setState(() => _dragging = true),
              onPanUpdate: (d) {
                setState(() {
                  _offset = FabLogic.clampIntoScreen(
                      _offset + d.delta, _screen, const Size(48, 48));
                });
              },
              onPanEnd: (d) {
                setState(() {
                  _offset = FabLogic.snapEdge(_offset, _screen, const Size(48, 48));
                  _dragging = false;
                });
                _persist();
              },
              onTap: () {
                // 拖动结束的落点也可能触发 onTap：用累计位移判定交给
                // GestureDetector 自身的 onTap（pan 与 tap 互斥，见测试）。
                widget.onTap();
              },
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
                  size: _dragging ? 20 : 28,
                ),
              ),
            ),
          )
        : const SizedBox.shrink();
  }
}
