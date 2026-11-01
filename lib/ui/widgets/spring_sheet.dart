import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import '../../theme.dart';

/// 弹层弹簧容器（任务书 T6 / spec §2.1）：自建 PopupRoute——
/// - 内容 translateY 由 kSpringDefault 弹簧驱动（createSimulation 原生通路）；
/// - 顶部 36×5 把手为拖拽热区，VelocityTracker 速度判定：
///   释放速度 >700px/s 或位移 >45% 内容高 → 关，否则 kSpringGesture
///   带释放初速度回弹；上拖过头 rubber-band(0.55) 阻尼；
/// - scrim rgba(0,0,0,.38) 随转场淡入淡出；
/// - 键盘适配：内容 padding 随 MediaQuery.viewInsets.bottom 上移。
///
/// 圆角 20 与弹层底色（bg）由容器统一接管，接入方不再传 shape/backgroundColor；
/// 各 sheet 内容 builder 原样不动。
Future<T?> showSpringSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return Navigator.of(context, rootNavigator: true)
      .push(SpringSheetRoute<T>(builder: builder));
}

/// 弹层标题行的关闭钮（用户 2026-10-31 反馈：标题紧贴顶边）。
/// 36×36 自绘而非 IconButton——M3 IconButton 的 48 触控盒会把标题行撑高，
/// 顶部留白随之变大；此处三处弹层共用。
class SheetCloseButton extends StatelessWidget {
  const SheetCloseButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onPressed,
      radius: 20,
      child: const SizedBox(
        width: 36,
        height: 36,
        child: Icon(Icons.close, color: AppColors.faint),
      ),
    );
  }
}

class SpringSheetRoute<T> extends PopupRoute<T> {
  SpringSheetRoute({required this.builder});

  final WidgetBuilder builder;

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: .38);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => '关闭弹层';

  // simulation 模式下被框架忽略，仅作兜底声明
  @override
  Duration get transitionDuration => const Duration(milliseconds: 500);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 400);

  /// 不做继承依赖注册的 MediaQuery 读取（只用于一次性判定）
  MediaQueryData? get _mq {
    final ctx = navigator?.context;
    return ctx?.getInheritedWidgetOfExactType<MediaQuery>()?.data;
  }

  bool get _reduceMotion => _mq?.disableAnimations ?? false;

  @override
  TickerFuture didPush() {
    if (_reduceMotion) {
      // createSimulation 返回 null 时框架走 controller.forward()，
      // 时长为 0 → 弹层与遮罩瞬现
      controller!.duration = Duration.zero;
      controller!.reverseDuration = Duration.zero;
    }
    return super.didPush();
  }

  @override
  Simulation? createSimulation({required bool forward}) {
    if (_reduceMotion) return null;
    if (forward) return SpringSimulation(kSpringDefault, 0, 1, 0);
    return SpringSimulation(kSpringDefault, controller!.value, 0, 0);
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    return _SheetScaffold<T>(route: this);
  }

  // 内容上滑进场/下滑出场（跟随弹簧 animation）；scrim 由 ModalBarrier
  // 用同一条 animation 淡入淡出
  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero)
          .animate(animation),
      child: child,
    );
  }
}

class _SheetScaffold<T> extends StatefulWidget {
  const _SheetScaffold({required this.route});

  final SpringSheetRoute<T> route;

  @override
  State<_SheetScaffold<T>> createState() => _SheetScaffoldState<T>();
}

class _SheetScaffoldState<T> extends State<_SheetScaffold<T>>
    with SingleTickerProviderStateMixin {
  double _dragDy = 0;
  final GlobalKey _sheetKey = GlobalKey();
  late final AnimationController _settle =
      AnimationController.unbounded(vsync: this);

  @override
  void initState() {
    super.initState();
    _settle.addListener(() {
      if (mounted) setState(() => _dragDy = math.max(0, _settle.value));
    });
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _settle.stop();
    setState(() {
      _dragDy += d.primaryDelta ?? 0;
      if (_dragDy < 0) _dragDy *= 0.55; // 上拖过头 rubber-band 阻尼
    });
  }

  double _sheetHeight() {
    final box = _sheetKey.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.height : 400;
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dy;
    if (v > 700 || _dragDy > _sheetHeight() * 0.45) {
      Navigator.of(context).pop();
      return;
    }
    // 回弹：kSpringGesture 带释放初速度（listener 内 clamp 到 ≥0，
    // 欠阻尼过冲不露出 sheet 底缝）
    _settle.animateWith(
        SpringSimulation(kSpringGesture, _dragDy, 0, v.toDouble()));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 键盘适配：内容整体随 viewInsets 上移（text_sheet 输入场景）
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Transform.translate(
          offset: Offset(0, _dragDy),
          // Material 承接圆角/底色/裁切（sheet 内 IconButton/滚选器需要
          // Material 祖先；等价原 showModalBottomSheet 的 backgroundColor+
          // shape 由容器统一接管）
          child: Material(
            key: _sheetKey,
            color: AppColors.bg,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 把手拖拽热区（原型 .sheet-dragzone/.sheet-grab）；
                // 用户 2026-10-31 反馈：顶部留白收紧（把手区 6+5+2＝13px）
                GestureDetector(
                  key: const ValueKey('spring-sheet-handle'),
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: _onDragUpdate,
                  onVerticalDragEnd: _onDragEnd,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    width: double.infinity,
                    child: Column(
                      children: [
                        Container(
                          width: 36,
                          height: 5,
                          margin: const EdgeInsets.only(bottom: 3),
                          decoration: BoxDecoration(
                            color: const Color(0x383C3C43),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                widget.route.builder(context),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
