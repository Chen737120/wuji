import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../editing/fab_logic.dart';
import '../../theme.dart';
import 'pressable_scale.dart';

/// 可拖动悬浮球（规格 §3；2026-10-31 T11 动量释放重写）：
/// 48dp 翠芽圆＋白＋；点击=新增课；位置持久化 key `fabOffset`（机制不动）。
/// 释放时按动量投影（decelRate 0.998）决定贴左/右，X/Y 独立弹簧
/// （kSpringGesture 带释放初速度）吸附；拖出边界 rubber-band(0.55) 阻尼；
/// 目标位置在释放瞬间即持久化（动画只是视觉过渡，进二级页卸载不丢位置）。
/// 仅根 tab 可见：HomeShell 的 Stack 监听 [RootRouteTracker] 控制挂载。
class DraggableFab extends StatefulWidget {
  const DraggableFab({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<DraggableFab> createState() => _DraggableFabState();
}

class _DraggableFabState extends State<DraggableFab> with TickerProviderStateMixin {
  static const _key = 'fabOffset';
  // 77px 的 80%（用户 2026-10-05 第二次反馈：再缩小到当前大小的 80%）
  static const _ballSize = Size(62, 62);

  Offset _offset = Offset.zero;
  bool _loaded = false;
  bool _dragging = false;

  // X/Y 独立弹簧（kSpringGesture 带初速度吸附）
  late final AnimationController _springX =
      AnimationController.unbounded(vsync: this);
  late final AnimationController _springY =
      AnimationController.unbounded(vsync: this);

  bool _restoreRequested = false;

  @override
  void initState() {
    super.initState();
    _springX.addListener(() {
      if (mounted) setState(() => _offset = Offset(_springX.value, _offset.dy));
    });
    _springY.addListener(() {
      if (mounted) setState(() => _offset = Offset(_offset.dx, _springY.value));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_restoreRequested) {
      _restoreRequested = true;
      _restore();
    }
  }

  @override
  void dispose() {
    _springX.dispose();
    _springY.dispose();
    super.dispose();
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

  Future<void> _persist([Offset? at]) async {
    final o = at ?? _offset;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, '${o.dx},${o.dy}');
  }

  void _stopSprings() {
    _springX.stop();
    _springY.stop();
  }

  void _onPanStart(DragStartDetails d) {
    _stopSprings();
    setState(() {
      _dragging = true;
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() {
      // 拖出边界 rubber-band(0.55) 弹性阻尼（T11）
      _offset = FabLogic.clampRubberBand(
          _offset + d.delta, MediaQuery.sizeOf(context), _ballSize);
    });
  }

  void _onPanEnd(DragEndDetails d) {
    setState(() => _dragging = false);
    _settle(d.velocity.pixelsPerSecond);
  }

  /// 动量投影 → 贴左/右目标 → X/Y 独立弹簧带初速度吸附（T11）
  void _settle(Offset velocity) {
    final screen = MediaQuery.sizeOf(context);
    final target = FabLogic.releaseTarget(_offset, velocity, screen, _ballSize);
    // 位置持久化机制不动：释放瞬间即写目标位置（动画只是视觉过渡，
    // 进二级页卸载中断弹簧也不丢位置）
    _persist(target);
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _offset = target); // 直达终态
      return;
    }
    _springX.animateWith(
        SpringSimulation(kSpringGesture, _offset.dx, target.dx, velocity.dx));
    _springY.animateWith(
        SpringSimulation(kSpringGesture, _offset.dy, target.dy, velocity.dy));
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    if (!_loaded) return const SizedBox.shrink();
    return Positioned(
      left: _offset.dx,
      top: _offset.dy,
      // T11：按压反馈与拖拽/点击手势并存（Listener 不消费事件）
      child: PressableScale(
        child: GestureDetector(
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          onPanCancel: () => setState(() {
            _dragging = false;
          }),
          onTap: widget.onTap,
          child: Container(
            width: _ballSize.width,
            height: _ballSize.height,
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
              size: _dragging ? 28 : 36,
            ),
          ),
        ),
      ),
    );
  }
}
