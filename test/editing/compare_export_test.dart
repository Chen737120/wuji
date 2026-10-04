import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/compare_export.dart';
import 'package:wuji/editing/side_transform.dart';

void main() {
  final left = SideTransform(ratio: '3:4');
  final right = SideTransform(ratio: '9:16', scale: 1.5, pan: const Offset(0.5, 0));

  test('命令包含 hstack、两侧 crop 与 720 高缩放', () {
    final cmd = buildCompareCommand(
      teacherPath: '/t.mp4',
      minePath: '/m.mp4',
      offset: const Duration(seconds: 5),
      teacherDur: const Duration(seconds: 60),
      myDur: const Duration(seconds: 60),
      left: left,
      right: right,
      leftSrc: const Size(1920, 1080),
      rightSrc: const Size(1080, 1920),
      audio: 'teacher',
      fpsCap: 30,
    );
    expect(cmd, contains('hstack=inputs=2'));
    expect(cmd, contains('scale=-2:720'));
    // 每侧各一个 crop
    expect('crop='.allMatches(cmd).length, 2);
    // 音源=老师（0:a）
    expect(cmd, contains('-map "[a]"'));
    // 帧率上限
    expect(cmd, contains('fps=30'));
    // 输出时长 = 重叠区间 = [5s, 60s) = 55s
    expect(cmd, contains('-t 55.000'));
  });

  test('音源可切：mine → -map 1:a；none → -an', () {
    final mine = buildCompareCommand(
        teacherPath: '/t.mp4',
        minePath: '/m.mp4',
        offset: Duration.zero,
        teacherDur: const Duration(seconds: 60),
        myDur: const Duration(seconds: 60),
        left: left,
        right: right,
        leftSrc: const Size(1920, 1080),
        rightSrc: const Size(1080, 1920),
        audio: 'mine',
        fpsCap: 30);
    expect(mine, contains('-map "[a]"'));
    final none = buildCompareCommand(
        teacherPath: '/t.mp4',
        minePath: '/m.mp4',
        offset: Duration.zero,
        teacherDur: const Duration(seconds: 60),
        myDur: const Duration(seconds: 60),
        left: left,
        right: right,
        leftSrc: const Size(1920, 1080),
        rightSrc: const Size(1080, 1920),
        audio: 'none',
        fpsCap: 30);
    expect(none, contains('-an'));
    expect(none, isNot(contains('-map 0:a')));
  });

  test('crop 参数与 toSourceRect 一致', () {
    final cmd = buildCompareCommand(
      teacherPath: '/t.mp4',
      minePath: '/m.mp4',
      offset: Duration.zero,
      teacherDur: const Duration(seconds: 60),
      myDur: const Duration(seconds: 60),
      left: left,
      right: right,
      leftSrc: const Size(1920, 1080),
      rightSrc: const Size(1080, 1920),
      audio: 'teacher',
      fpsCap: 30,
    );
    final lr = left.toSourceRect(const Size(1920, 1080), 720);
    expect(cmd, contains('crop=${lr.width.round()}:${lr.height.round()}:${lr.left.round()}:${lr.top.round()}'));
    final rr = right.toSourceRect(const Size(1080, 1920), 720);
    expect(cmd, contains('crop=${rr.width.round()}:${rr.height.round()}:${rr.left.round()}:${rr.top.round()}'));
  });

  test('-ss 偏移：我的侧从 0 起、老师侧加偏移（offset>0）', () {
    final cmd = buildCompareCommand(
      teacherPath: '/t.mp4',
      minePath: '/m.mp4',
      offset: const Duration(seconds: 5),
      teacherDur: const Duration(seconds: 60),
      myDur: const Duration(seconds: 60),
      left: left,
      right: right,
      leftSrc: const Size(1920, 1080),
      rightSrc: const Size(1080, 1920),
      audio: 'teacher',
      fpsCap: 30,
    );
    // 我的延后 5s（offset>0）：我的流前置 5s 静帧（tpad），老师不动
    expect(cmd, isNot(contains('-ss')), reason: cmd);
    expect(cmd, contains('tpad=start_duration=5.000'), reason: cmd);
    expect(cmd, contains('-t 55.000'), reason: cmd);
  });
}
