import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/export_service.dart';

class FakeRunner implements CommandRunner {
  FakeRunner({this.exitCode = 0});
  final int exitCode;
  int calls = 0;
  int cancels = 0;
  List<String> lastArgs = const [];
  @override
  Future<int> run(List<String> args,
      {void Function(double)? onProgress, int? expectedDurationMs}) async {
    calls++;
    lastArgs = args;
    onProgress?.call(0.5);
    return exitCode;
  }

  @override
  void cancel() => cancels++;
}

class FailRunner extends FakeRunner {
  FailRunner() : super(exitCode: 1);
}

/// 模拟「导出中用户点取消」：run 返回 FFmpegKit 取消退出码 255，
/// 且此刻 svc.cancel() 已被调（_cancelRequested 已置位）。
class CancelMidRunRunner extends FakeRunner {
  CancelMidRunRunner(this.onRun) : super(exitCode: 255);
  final void Function() onRun;
  @override
  Future<int> run(List<String> args,
      {void Function(double)? onProgress, int? expectedDurationMs}) {
    onRun();
    return super.run(args,
        onProgress: onProgress, expectedDurationMs: expectedDurationMs);
  }
}

class FakeMover implements FileMover {
  final moved = <String, String>{};
  final cleanedTemps = <String>[];
  @override
  Future<String> moveToGallery(String tempPath, String fileName) async {
    final target = 'Movies/wuji/$fileName';
    moved[tempPath] = target;
    return target;
  }

  @override
  Future<void> cleanTemp(String path) async {
    cleanedTemps.add(path);
  }
}

/// 输出探测 fake：按预定序列返回（缺省恒 true=有视频流）；记录探测的路径。
class FakeProbe {
  FakeProbe([List<bool>? results]) : _results = results ?? const [];
  final List<bool> _results;
  var calls = 0;
  final paths = <String>[];
  Future<bool> call(String path) async {
    final i = calls++;
    paths.add(path);
    return i < _results.length ? _results[i] : true;
  }
}

void main() {
  test('tokenizeFfmpeg: 双引号丢弃、单引号保留、空格分隔', () {
    final args = tokenizeFfmpeg(
        '-y -i "/a b/视 频.mp4" -vf "crop=1:2:x=\'if(lt(t,1),0,1)\'" out.mp4');
    expect(args, [
      '-y',
      '-i',
      '/a b/视 频.mp4',
      '-vf',
      'crop=1:2:x=\'if(lt(t,1),0,1)\'',
      'out.mp4',
    ]);
  });

  test('run: success moves output to Movies/wuji and reports path', () async {
    final runner = FakeRunner();
    final mover = FakeMover();
    final probe = FakeProbe();
    final svc = ExportService(
      runner: runner,
      mover: mover,
      probeHasVideo: probe.call,
      tempDirProvider: () async => Directory.systemTemp,
      clock: () => DateTime(2026, 10, 4, 21, 30),
    );
    final p = await svc.run(ExportJob(
        command: '-i a.mp4 -i "b 2.mp4" -filter_complex hstack',
        base: '对比',
        ext: 'mp4'));
    expect(p, contains('Movies/wuji/'));
    expect(p, contains('对比_20261004_213000.mp4'));
    expect(mover.moved, hasLength(1));
    expect(mover.cleanedTemps, isEmpty); // 成功不留临时
    // 输出路径是最后一个参数（数组执行，免 shell 拼接注入）
    expect(runner.lastArgs.last, mover.moved.keys.single);
    expect(runner.lastArgs, contains('-filter_complex'));
    expect(runner.lastArgs, contains('b 2.mp4')); // 空格路径是完整参数
    expect(probe.calls, 1); // 搬运前探测过一次输出
    expect(probe.paths.single, runner.lastArgs.last); // probe 在 mover 之前
  });

  test('run: mediacodec 失败回退 mpeg4 且不重复输出路径', () async {
    final runner = FailRunner();
    final mover = FakeMover();
    final svc = ExportService(
      runner: runner,
      mover: mover,
      tempDirProvider: () async => Directory.systemTemp,
      clock: () => DateTime(2026, 10, 4),
    );
    await expectLater(
      svc.run(ExportJob(
          command: '-i a.mp4 -c:v h264_mediacodec -c:a aac',
          base: '直拍',
          ext: 'mp4')),
      throwsA(anything),
    );
    // 回退轮：h264_mediacodec 被换成 mpeg4，输出路径只出现一次（最后参数）
    final out = runner.lastArgs.last;
    expect(out.endsWith('.mp4'), isTrue);
    expect(runner.lastArgs.where((a) => a == out), hasLength(1));
    expect(runner.lastArgs.contains('mpeg4'), isTrue);
    expect(runner.lastArgs.contains('h264_mediacodec'), isFalse);
  });

  test('run: failure cleans temp and throws', () async {
    final mover = FakeMover();
    final svc = ExportService(
      runner: FakeRunner(exitCode: 1),
      mover: mover,
      tempDirProvider: () async => Directory.systemTemp,
      clock: () => DateTime(2026, 10, 4),
    );
    await expectLater(
      svc.run(ExportJob(command: 'x', base: '直拍', ext: 'mp4')),
      throwsA(anything),
    );
    expect(mover.cleanedTemps, hasLength(1)); // 半成品清理
    expect(mover.moved, isEmpty);
  });

  test('cancel: marks job cancelled and cleans temp', () async {
    final runner = FakeRunner();
    final mover = FakeMover();
    final svc = ExportService(
      runner: runner,
      mover: mover,
      tempDirProvider: () async => Directory.systemTemp,
      clock: () => DateTime(2026, 10, 4),
    );
    // 模拟用户在 run 期间点取消：runner 返回前 svc.cancel() 已被调
    svc.cancel();
    await expectLater(
      svc.run(ExportJob(command: 'x', base: '直拍', ext: 'mp4')),
      throwsA(isA<ExportCancelled>()),
    );
    expect(runner.cancels, 1); // 透传给 runner 取消 FFmpeg 会话
    expect(mover.cleanedTemps, hasLength(1));
  });

  test('run: 导出中取消不当硬编失败——不进 mpeg4 软编回退，直接 ExportCancelled', () async {
    late final ExportService svc;
    final runner = CancelMidRunRunner(() => svc.cancel());
    final mover = FakeMover();
    svc = ExportService(
      runner: runner,
      mover: mover,
      tempDirProvider: () async => Directory.systemTemp,
      clock: () => DateTime(2026, 10, 4),
    );
    await expectLater(
      svc.run(ExportJob(
          // 含 mediacodec：无守卫时 rc=255 会被当硬编失败再跑一轮软编
          command: '-i a.mp4 -c:v h264_mediacodec',
          base: '打码',
          ext: 'mp4')),
      throwsA(isA<ExportCancelled>()),
    );
    expect(runner.calls, 1); // 只跑一轮：取消不触发软编回退
    expect(runner.lastArgs.contains('mpeg4'), isFalse);
    expect(mover.cleanedTemps, hasLength(1)); // 半成品清理
    expect(mover.moved, isEmpty);
  });

  test('progress bubbles from runner', () async {
    final runner = FakeRunner();
    final svc = ExportService(
      runner: runner,
      mover: FakeMover(),
      probeHasVideo: FakeProbe().call,
      tempDirProvider: () async => Directory.systemTemp,
      clock: () => DateTime(2026, 10, 4),
    );
    final seen = <double>[];
    await svc.run(ExportJob(command: 'x', base: '直拍', ext: 'mp4'),
        onProgress: seen.add);
    expect(seen, contains(0.5));
  });

  // ---- 缺陷 2：rc=0 但成片无视频流（AVD mediacodec 静默零包）----
  test('run: rc=0 无视频流→回退 mpeg4 一轮后探测通过则成功', () async {
    final runner = FakeRunner(); // 两轮都 rc=0
    final mover = FakeMover();
    final probe = FakeProbe([false, true]); // 第一轮无视频流，回退后有
    final svc = ExportService(
      runner: runner,
      mover: mover,
      probeHasVideo: probe.call,
      tempDirProvider: () async => Directory.systemTemp,
      clock: () => DateTime(2026, 10, 4),
    );
    final p = await svc.run(ExportJob(
        command: '-i a.mp4 -c:v h264_mediacodec -c:a aac',
        base: '打码',
        ext: 'mp4'));
    expect(runner.calls, 2); // 硬编 + mpeg4 回退
    expect(runner.lastArgs.contains('mpeg4'), isTrue);
    expect(runner.lastArgs.contains('h264_mediacodec'), isFalse);
    expect(mover.moved, hasLength(1)); // 回退轮成功照常入相册
    expect(mover.cleanedTemps, isEmpty);
    expect(probe.calls, 2);
  });

  test('run: 回退 mpeg4 后仍无视频流→ExportFailed 且清半成品', () async {
    final runner = FakeRunner(); // 两轮都 rc=0
    final mover = FakeMover();
    final probe = FakeProbe([false, false]); // 两轮均无视频流
    final svc = ExportService(
      runner: runner,
      mover: mover,
      probeHasVideo: probe.call,
      tempDirProvider: () async => Directory.systemTemp,
      clock: () => DateTime(2026, 10, 4),
    );
    await expectLater(
      svc.run(ExportJob(
          command: '-i a.mp4 -c:v h264_mediacodec -c:a aac',
          base: '打码',
          ext: 'mp4')),
      throwsA(isA<ExportFailed>().having((e) => e.toString(), 'message',
          contains('无视频流'))),
    );
    expect(runner.calls, 2); // 重试了一轮才失败
    expect(mover.moved, isEmpty);
    expect(mover.cleanedTemps, hasLength(1)); // 半成品清理
  });

  test('run: 非硬编命令 rc=0 无视频流→不重试直接失败', () async {
    final runner = FakeRunner();
    final mover = FakeMover();
    final probe = FakeProbe([false]);
    final svc = ExportService(
      runner: runner,
      mover: mover,
      probeHasVideo: probe.call,
      tempDirProvider: () async => Directory.systemTemp,
      clock: () => DateTime(2026, 10, 4),
    );
    await expectLater(
      svc.run(ExportJob(command: '-i a.mp4 -c:v mpeg4', base: '打码', ext: 'mp4')),
      throwsA(isA<ExportFailed>()),
    );
    expect(runner.calls, 1); // 无硬编可回退，只跑一轮
    expect(mover.cleanedTemps, hasLength(1));
  });

  test('run: 导出中取消→不探测不回退，直接 ExportCancelled', () async {
    late final ExportService svc;
    final runner = CancelMidRunRunner(() => svc.cancel());
    final mover = FakeMover();
    final probe = FakeProbe();
    svc = ExportService(
      runner: runner,
      mover: mover,
      probeHasVideo: probe.call,
      tempDirProvider: () async => Directory.systemTemp,
      clock: () => DateTime(2026, 10, 4),
    );
    await expectLater(
      svc.run(ExportJob(
          command: '-i a.mp4 -c:v h264_mediacodec',
          base: '打码',
          ext: 'mp4')),
      throwsA(isA<ExportCancelled>()),
    );
    expect(probe.calls, 0); // 取消路径不探测输出
  });
}
