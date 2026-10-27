import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/crop_box.dart';
import 'package:wuji/editing/keyframes.dart';
import 'package:wuji/ui/fancam/fancam_preview_page.dart';

void main() {
  group('shouldDiscardTemp（P2-34）', () {
    test('无成片路径不删', () {
      expect(shouldDiscardTemp(path: null, saved: false), isFalse);
      expect(shouldDiscardTemp(path: null, saved: true), isFalse);
    });

    test('已保存到相册不删', () {
      expect(shouldDiscardTemp(path: '/cache/a.mp4', saved: true), isFalse);
    });

    test('生成后未保存 → 删除临时成片', () {
      expect(shouldDiscardTemp(path: '/cache/a.mp4', saved: false), isTrue);
    });
  });

  group('导出中守卫（P2-10）', () {
    test('canPopDuringExport：导出中禁止返回', () {
      expect(canPopDuringExport(true), isFalse);
      expect(canPopDuringExport(false), isTrue);
    });

    test('shouldDeleteCmds：导出中不删（ffmpeg 可能仍在读）', () {
      expect(shouldDeleteCmds(true), isFalse);
      expect(shouldDeleteCmds(false), isTrue);
    });
  });

  testWidgets('主按钮文案为「生成成片」，不再误称保存到相册', (tester) async {
    final track = KeyframeTrack(duration: const Duration(seconds: 10))
      ..reset(const CropBox(cx: 0.5, cy: 0.5, w: 0.5, h: 0.5));
    await tester.pumpWidget(MaterialApp(
      home: FancamPreviewPage(
        sourcePath: '/tmp/nonexistent.mp4',
        track: track,
        srcW: 1280,
        srcH: 720,
        ratio: '16:9',
        keyframeCount: 1,
      ),
    ));
    await tester.pump();

    expect(find.text('生成成片'), findsOneWidget);
    // 「保存到相册」只应出现在成片预览页（需真实导出，真机 V3 走查）
    expect(find.text('保存到相册'), findsNothing);
  });
}
