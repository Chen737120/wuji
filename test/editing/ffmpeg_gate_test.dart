// FfmpegGate 串行闸单测（冒烟缺陷 3 缓解）：FFmpegKit 会话全局串行——
// 并发调用不重叠、异常不堵队列、值与错误原样透传。
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/ffmpeg_serial.dart';

void main() {
  test('并发 run 串行执行：任务时间线不重叠', () async {
    final gate = FfmpegGate();
    final timeline = <String>[];
    Future<void> task(String name, Duration hold) async {
      timeline.add('enter:$name');
      await Future<void>.delayed(hold);
      timeline.add('exit:$name');
    }

    await Future.wait([
      gate.run(() => task('a', const Duration(milliseconds: 30))),
      gate.run(() => task('b', const Duration(milliseconds: 10))),
      gate.run(() => task('c', Duration.zero)),
    ]);
    expect(timeline, ['enter:a', 'exit:a', 'enter:b', 'exit:b', 'enter:c', 'exit:c'],
        reason: 'b/c 须等 a 完全退出才进入');
  });

  test('前序任务抛异常不堵队列，错误原样透传', () async {
    final gate = FfmpegGate();
    await expectLater(
        gate.run<int>(() async => throw StateError('boom')), throwsStateError);
    var ran = false;
    final v = await gate.run(() async {
      ran = true;
      return 7;
    });
    expect(ran, isTrue, reason: '失败任务不得卡死后续排队者');
    expect(v, 7);
  });

  test('全局 ffmpegGate 单例可复用（多次调用全部完成）', () async {
    final rs = await Future.wait([for (var i = 0; i < 5; i++) ffmpegGate.run(() async => i)]);
    expect(rs, [0, 1, 2, 3, 4]);
  });
}
