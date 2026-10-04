import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:wuji/editing/ffmpeg_probe.dart';

/// 探测入口（不入正式构建）：flutter run -t lib/main_probe.dart
/// 输出 PROBE_RESULT 供构建脚本决定 min / min-gpl 变体（规格 §2）。
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final hw = await hasHardwareH264Encoder();
  debugPrint('PROBE_RESULT: h264_mediacodec=$hw');
  final session = await FFmpegKit.execute('-version');
  final version = (await session.getAllLogsAsString()) ?? '';
  debugPrint('PROBE_VERSION: ${version.split('\n').first}');
  runApp(const MaterialApp(
      home: Scaffold(body: Center(child: Text('PROBE DONE – 可以关闭')))));
}
