// 三素材跟踪 fixture 生成入口（dev 一次性工具的 test 壳；真身与说明见
// tool/gen_follow_fixture.dart——init 点选择依据、CSV 格式、身份核验方法都在那里）。
// 运行（PC，需便携 ffmpeg 与 testdata 素材，产物 CSV 在 testdata/ 已 git-ignore）：
//   WUJI_GEN_FIXTURE=1 flutter test test/editing/fancam_follow_fixture_gen_test.dart
// 为什么经 flutter test 而非 dart run：tool 脚本 import T1 fancam_tracker.dart，
// 其顶层 import ffmpeg_kit（flutter 插件，依赖 package:flutter/services），
// 纯 dart VM 编译不了；flutter test VM 可编译，且脚本只用 Process.run 不触碰平台通道。
// WUJI_GEN_FIXTURE 门闩：普通 flutter test 全量回归在此显示为 skip（不是 pass）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/gen_follow_fixture.dart' as gen;

void main() {
  final enabled = Platform.environment['WUJI_GEN_FIXTURE'] == '1';
  final hasInputs = File(gen.ffmpeg).existsSync() &&
      File('testdata/fancam-motion-demo/src.mp4').existsSync();
  final skipReason = !enabled
      ? '设 WUJI_GEN_FIXTURE=1 后运行本文件以生成 fixture'
          '（详见 tool/gen_follow_fixture.dart 头注释）'
      : (!hasInputs ? '缺便携 ffmpeg 或 testdata 素材（CI 无 testdata）' : null);

  test('生成三素材跟踪 CSV fixture（WUJI_GEN_FIXTURE=1 时执行）', () async {
    await gen.generateAll();
  },
      skip: skipReason,
      timeout: const Timeout(Duration(minutes: 15)));
}
