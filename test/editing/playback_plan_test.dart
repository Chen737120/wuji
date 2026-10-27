// test/editing/playback_plan_test.dart
//
// 同屏对比重播不同步修复（缺陷会话 2026-10-26）的纯函数契约。
// 语义：返回 null = 原地续播（不需要 seek）；返回起点 = 两路各自 seek 一次。
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/ui/compare/playback_plan.dart';

const _dur10 = Duration(seconds: 10);
const _two = Duration(seconds: 2);

/// 老师已播到结尾（_atEnd 的 80ms 阈值口径）。
const _atEnd10 = Duration(milliseconds: 9920);

void main() {
  group('首次播放（offset 方向决定谁先播）', () {
    test('offset>0：老师从 offset 起、我的从 0', () {
      expect(
        planPlayStart(
            teacherPos: Duration.zero,
            teacherDur: _dur10,
            minePos: Duration.zero,
            offset: _two),
        (teacher: _two, mine: Duration.zero),
      );
    });

    test('offset<0：我的从 |offset| 起、老师从 0', () {
      expect(
        planPlayStart(
            teacherPos: Duration.zero,
            teacherDur: _dur10,
            minePos: Duration.zero,
            offset: -_two),
        (teacher: Duration.zero, mine: _two),
      );
    });

    test('offset=0：无需 seek（原地播即同步）', () {
      expect(
        planPlayStart(
            teacherPos: Duration.zero,
            teacherDur: _dur10,
            minePos: Duration.zero,
            offset: Duration.zero),
        isNull,
      );
    });
  });

  group('中途续播（两路已在正确错位关系上）', () {
    test('offset>0 且老师已过 offset → null（不打断）', () {
      expect(
        planPlayStart(
            teacherPos: const Duration(seconds: 5),
            teacherDur: _dur10,
            minePos: const Duration(seconds: 3),
            offset: _two),
        isNull,
      );
    });

    test('offset<0 且我的已过 |offset| → null', () {
      expect(
        planPlayStart(
            teacherPos: const Duration(seconds: 3),
            teacherDur: _dur10,
            minePos: const Duration(seconds: 5),
            offset: -_two),
        isNull,
      );
    });

    test('offset>0 但老师还在 offset 之前 → 拉到起点', () {
      expect(
        planPlayStart(
            teacherPos: const Duration(seconds: 1),
            teacherDur: _dur10,
            minePos: Duration.zero,
            offset: _two),
        (teacher: _two, mine: Duration.zero),
      );
    });

    test('offset<0 但我的还在 |offset| 之前 → 拉到起点', () {
      expect(
        planPlayStart(
            teacherPos: Duration.zero,
            teacherDur: _dur10,
            minePos: const Duration(seconds: 1),
            offset: -_two),
        (teacher: Duration.zero, mine: _two),
      );
    });
  });

  group('重播（老师已到结尾）', () {
    test('offset>0：老师 seek 到 offset、我的归零（用户报告的主场景）', () {
      expect(
        planPlayStart(
            teacherPos: _atEnd10,
            teacherDur: _dur10,
            minePos: const Duration(seconds: 8),
            offset: _two),
        (teacher: _two, mine: Duration.zero),
      );
    });

    test('offset<0：老师归零、我的 seek 到 |offset|', () {
      expect(
        planPlayStart(
            teacherPos: _atEnd10,
            teacherDur: _dur10,
            minePos: const Duration(seconds: 9),
            offset: -_two),
        (teacher: Duration.zero, mine: _two),
      );
    });

    test('offset=0：两路都显式归零（我的视频 ENDED 不会自动回零）', () {
      expect(
        planPlayStart(
            teacherPos: _atEnd10,
            teacherDur: _dur10,
            minePos: _atEnd10,
            offset: Duration.zero),
        (teacher: Duration.zero, mine: Duration.zero),
      );
    });

    test('阈值内（dur-80ms 恰好）即视为播完', () {
      expect(
        planPlayStart(
            teacherPos: const Duration(milliseconds: 9920),
            teacherDur: _dur10,
            minePos: Duration.zero,
            offset: _two),
        (teacher: _two, mine: Duration.zero),
      );
    });

    test('阈值外（dur-100ms）不算播完 → 原地续播，不归零', () {
      // 两路维持错位关系（我的 = 老师 − offset = 7.9s），属中途续播
      expect(
        planPlayStart(
            teacherPos: const Duration(milliseconds: 9900),
            teacherDur: _dur10,
            minePos: const Duration(milliseconds: 7900),
            offset: _two),
        isNull,
      );
    });
  });

  group('边界', () {
    test('老师时长未知（未初始化，dur=0）不触发重播分支', () {
      // 若误判为重播会返回 (teacher:0,mine:0)；正确是 null（无 offset 需求）
      expect(
        planPlayStart(
            teacherPos: Duration.zero,
            teacherDur: Duration.zero,
            minePos: Duration.zero,
            offset: Duration.zero),
        isNull,
      );
    });

    test('offset 超过老师时长：老师目标被钳到时长（不留非法 seek 目标）', () {
      expect(
        planPlayStart(
            teacherPos: _atEnd10,
            teacherDur: _dur10,
            minePos: _atEnd10,
            offset: const Duration(seconds: 15)),
        (teacher: _dur10, mine: Duration.zero),
      );
    });
  });

  group('isAtEnd（P1-9：续播不拉起已播完的视频）', () {
    test('未初始化（duration=0）不算结尾', () {
      expect(isAtEnd(Duration.zero, Duration.zero), isFalse);
      expect(isAtEnd(const Duration(seconds: 3), Duration.zero), isFalse);
    });

    test('距结尾 50ms 内算结尾（阈值 80ms）', () {
      expect(isAtEnd(const Duration(milliseconds: 9950), _dur10), isTrue);
      expect(isAtEnd(_atEnd10, _dur10), isTrue);
    });

    test('距结尾 100ms 不算结尾', () {
      expect(isAtEnd(const Duration(milliseconds: 9900), _dur10), isFalse);
    });

    test('position 超过 duration 仍算结尾', () {
      expect(isAtEnd(const Duration(seconds: 11), _dur10), isTrue);
    });
  });
}
