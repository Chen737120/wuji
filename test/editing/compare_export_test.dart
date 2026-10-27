import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/compare_export.dart';
import 'package:wuji/editing/side_transform.dart';

void main() {
  final left = SideTransform(ratio: '3:4');
  final right = SideTransform(ratio: '9:16', scale: 1.5);
  const ca = 1.0; // 测试用 1×1 容器

  test('命令包含 hstack、两侧 crop 与 1080 高缩放', () {
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
      containerAspect: ca,
    );
    expect(cmd, startsWith('-y '));
    expect(cmd, contains('hstack=inputs=2'));
    expect(cmd, contains('scale=-2:1080'));
    expect('crop='.allMatches(cmd).length, 2);
    expect(cmd, contains('-map 0:a'));
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
        fpsCap: 30,
        containerAspect: ca);
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
        fpsCap: 30,
        containerAspect: ca);
    expect(none, contains('-an'));
    expect(none, isNot(contains('-map 0:a')));
  });

  test('crop 参数与 toSourceRect 一致（遮罩预览 WYSIWYG）', () {
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
      containerAspect: ca,
    );
    final lr = left.toSourceRect(const Size(1920, 1080), ca);
    expect(
        cmd,
        contains(
            'crop=${lr.width.round()}:${lr.height.round()}:${lr.left.round()}:${lr.top.round()}'));
    final rr = right.toSourceRect(const Size(1080, 1920), ca);
    expect(
        cmd,
        contains(
            'crop=${rr.width.round()}:${rr.height.round()}:${rr.left.round()}:${rr.top.round()}'));
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
      containerAspect: ca,
    );
    expect(cmd, contains('-ss 5.000 -i "/t.mp4"'), reason: cmd);
    expect(cmd, isNot(contains('-ss 5.000 -i "/m.mp4"')), reason: cmd);
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
      containerAspect: ca,
    );
    expect(cmd, contains('-ss 5.000 -i "/m.mp4"'), reason: cmd);
    expect(cmd, isNot(contains('-ss 5.000 -i "/t.mp4"')), reason: cmd);
    expect(cmd, isNot(contains('tpad=start')), reason: cmd);
    expect(cmd, contains('tpad=stop_duration=5.000'), reason: cmd);
    expect(cmd, contains('-t 60.000'), reason: cmd);
  });

  test('偏移为 0：两侧都不剪开头，短侧末尾补齐到较长者', () {
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
      containerAspect: ca,
    );
    expect(cmd, isNot(contains('-ss ')), reason: cmd);
    expect(cmd, contains('tpad=stop_duration=10.000'), reason: cmd);
    expect(cmd, contains('-t 60.000'), reason: cmd);
  });

  test('leftSrc 传显示域时 crop 按显示域计算（P1-8：页面传什么就用什么）', () {
    // 竖拍老师：编码 1920×1080 + rotation=90 → 显示域 1080×1920
    const display = Size(1080, 1920);
    final cmd = buildCompareCommand(
      teacherPath: '/t.mp4',
      minePath: '/m.mp4',
      offset: Duration.zero,
      teacherDur: const Duration(seconds: 60),
      myDur: const Duration(seconds: 60),
      left: left,
      right: right,
      leftSrc: display,
      rightSrc: const Size(1080, 1920),
      audio: 'teacher',
      fpsCap: 30,
      containerAspect: ca,
    );
    final lr = left.toSourceRect(display, ca);
    expect(
        cmd,
        contains(
            'crop=${lr.width.round()}:${lr.height.round()}:${lr.left.round()}:${lr.top.round()}'));
    // 与误用编码域（1920×1080）的结果必须不同，证明域真的参与了计算
    final enc = left.toSourceRect(const Size(1920, 1080), ca);
    if (lr.width.round() != enc.width.round() ||
        lr.height.round() != enc.height.round()) {
      expect(
          cmd,
          isNot(contains(
              'crop=${enc.width.round()}:${enc.height.round()}')));
    }
  });
}
