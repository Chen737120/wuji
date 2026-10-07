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
    final svc = ExportService(
      runner: runner,
      mover: mover,
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

  test('progress bubbles from runner', () async {
    final runner = FakeRunner();
    final svc = ExportService(
      runner: runner,
      mover: FakeMover(),
      tempDirProvider: () async => Directory.systemTemp,
      clock: () => DateTime(2026, 10, 4),
    );
    final seen = <double>[];
    await svc.run(ExportJob(command: 'x', base: '直拍', ext: 'mp4'),
        onProgress: seen.add);
    expect(seen, contains(0.5));
  });
}
