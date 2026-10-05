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
    expect(cmd, startsWith('-y '));
    expect(cmd, contains('hstack=inputs=2'));
    expect(cmd, contains('scale=-2:720'));
    // 每侧各一个 crop
    expect('crop='.allMatches(cmd).length, 2);
    // 音源=老师（0:a）
    expect(cmd, contains('-map 0:a'));
    // 帧率上限
    expect(cmd, contains('fps=30'));
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
    expect(mine, contains('-map 1:a'));
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

  test('我的延后（offset>0）：老师开头 -ss 剪掉、我的不动', () {
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
    expect(cmd, contains('-ss 5.000 -i "/t.mp4"'), reason: cmd);
    expect(cmd, isNot(contains('-ss 5.000 -i "/m.mp4"')), reason: cmd);
    // 开头无补帧
    expect(cmd, isNot(contains('tpad=start')), reason: cmd);
    // 总长 = 未剪侧（我的）全长 60s；老师剩 55s，末尾冻结补 5s
    expect(cmd, contains('tpad=stop_duration=5.000'), reason: cmd);
    expect(cmd, contains('-t 60.000'), reason: cmd);
  });

  test('我的提前（offset<0）：我的开头 -ss 剪掉、老师不动', () {
    final cmd = buildCompareCommand(
      teacherPath: '/t.mp4',
      minePath: '/m.mp4',
      offset: const Duration(seconds: -5),
      teacherDur: const Duration(seconds: 60),
      myDur: const Duration(seconds: 60),
      left: left,
      right: right,
      leftSrc: const Size(1920, 1080),
      rightSrc: const Size(1080, 1920),
      audio: 'teacher',
      fpsCap: 30,
    );
    expect(cmd, contains('-ss 5.000 -i "/m.mp4"'), reason: cmd);
    expect(cmd, isNot(contains('-ss 5.000 -i "/t.mp4"')), reason: cmd);
    expect(cmd, isNot(contains('tpad=start')), reason: cmd);
    // 总长 = 未剪侧（老师）全长 60s；我剩 55s，末尾冻结补 5s
    expect(cmd, contains('tpad=stop_duration=5.000'), reason: cmd);
    expect(cmd, contains('-t 60.000'), reason: cmd);
  });

  test('偏移为 0：两侧都不剪，短侧末尾补齐到较长者', () {
    final cmd = buildCompareCommand(
      teacherPath: '/t.mp4',
      minePath: '/m.mp4',
      offset: Duration.zero,
      teacherDur: const Duration(seconds: 60),
      myDur: const Duration(seconds: 50),
      left: left,
      right: right,
      leftSrc: const Size(1920, 1080),
      rightSrc: const Size(1080, 1920),
      audio: 'teacher',
      fpsCap: 30,
    );
    expect(cmd, isNot(contains('-ss ')), reason: cmd);
    // 我 50s 比老师短 10s：末尾冻结补 10s（允许的末尾竞争延长）
    expect(cmd, contains('tpad=stop_duration=10.000'), reason: cmd);
    expect(cmd, contains('-t 60.000'), reason: cmd);
  });
}
