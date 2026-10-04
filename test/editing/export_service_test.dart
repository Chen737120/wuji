import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/export_service.dart';

class FakeRunner implements CommandRunner {
  FakeRunner({this.exitCode = 0});
  final int exitCode;
  int calls = 0;
  int cancels = 0;
  String? lastCommand;
  @override
  Future<int> run(String command,
      {void Function(double)? onProgress, int? expectedDurationMs}) async {
    calls++;
    lastCommand = command;
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
        command: '-i a.mp4 -i b.mp4 -filter_complex hstack',
        base: '对比',
        ext: 'mp4'));
    expect(p, contains('Movies/wuji/'));
    expect(p, contains('对比_20261004_213000.mp4'));
    expect(mover.moved, hasLength(1));
    expect(mover.cleanedTemps, isEmpty); // 成功不留临时
    // 命令尾部带上临时输出路径（输出文件是最后一个参数）
    final tempPath = mover.moved.keys.single;
    expect(runner.lastCommand, endsWith('"$tempPath"'));
  });

  test('run: failure cleans temp and throws', () async {
    final mover = FakeMover();
    final svc = ExportService(
      runner: FailRunner(),
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
