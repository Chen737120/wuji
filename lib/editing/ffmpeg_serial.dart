import 'dart:async';

/// FFmpegKit 调用全局串行闸（冒烟缺陷 3 的产品层缓解）。
///
/// 背景实证：打码编辑器内偶发 SIGABRT（Scudo 堆损坏），崩溃栈固定在
/// FFmpegKit 命令解析期 `init_complex_filtergraph→avfilter_inout_free`，
/// 2/2 会话命中、随机时刻；同款 filtergraph 命令串行重放 15 次不复现
/// （build/smoke/DEBUG-REPORT.md）。native abort 无法在 Dart 层捕获
/// （进程直接死），唯一产品层缓解是消除并发窗口：独立打码「导出」命令
/// 可跑几十秒，期间编辑器 seek/调整仍会触发快照重拍，两条命令在
/// native 侧同时 parse/release 滤镜图。本闸让设备端全部 FFmpegKit
/// 会话全局串行——同一时刻只有一条命令在跑，解析窗口不再重叠。
class FfmpegGate {
  Future<void> _tail = Future<void>.value();

  /// 串行执行 [task]：任一时刻最多一个在跑，后到者排队；
  /// 返回值与异常原样透传，前序任务失败不阻塞后续任务。
  Future<T> run<T>(Future<T> Function() task) {
    final prev = _tail;
    final completer = Completer<void>();
    _tail = completer.future;
    return prev.then((_) => task()).whenComplete(completer.complete);
  }
}

/// 全局单例：设备端所有 FFmpegKit 命令（导出/快照）共用一把闸。
final ffmpegGate = FfmpegGate();
