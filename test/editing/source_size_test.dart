import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/ui/compare/playback_plan.dart';

/// P1-8：对比导出取样域——显示域优先，probe 仅兜底。
void main() {
  test('rendered（video_player 显示域，rotation 已应用）优先', () {
    expect(
      resolveSourceSize(
        rendered: const Size(1080, 1920),
        probeW: 1920,
        probeH: 1080,
      ),
      const Size(1080, 1920),
    );
  });

  test('rendered 为 0/负（控制器未就绪）→ 用 probe 编码域', () {
    expect(
      resolveSourceSize(
        rendered: const Size(0, 1920),
        probeW: 1920,
        probeH: 1080,
      ),
      const Size(1920, 1080),
    );
    expect(
      resolveSourceSize(
        rendered: const Size(-1, 100),
        probeW: 720,
        probeH: 1280,
      ),
      const Size(720, 1280),
    );
  });

  test('probe 缺失或为 0 → fallback 竖屏 1080×1920', () {
    expect(resolveSourceSize(), const Size(1080, 1920));
    expect(
      resolveSourceSize(probeW: 0, probeH: 1080),
      const Size(1080, 1920),
    );
    expect(resolveSourceSize(probeW: 1920), const Size(1080, 1920));
  });
}
