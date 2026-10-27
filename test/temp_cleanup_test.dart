import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/services/temp_cleanup.dart';

/// P2-7：缓存清理候选与保留时长。
void main() {
  test('isCleanupCandidate 覆盖新增的 share / wuji-mosaic', () {
    expect(isCleanupCandidate('share'), isTrue);
    expect(isCleanupCandidate('wuji-mosaic'), isTrue);
    // 既有项不回归
    expect(isCleanupCandidate('wuji-export'), isTrue);
    expect(isCleanupCandidate('wuji-import-extract'), isTrue);
    expect(isCleanupCandidate('wuji-form-thumb'), isTrue);
    expect(isCleanupCandidate('wuji-import-123.zip'), isTrue);
    expect(isCleanupCandidate('舞记备份-2026.zip'), isTrue);
    // 不相关目录不碰
    expect(isCleanupCandidate('other'), isFalse);
    expect(isCleanupCandidate('share2'), isFalse);
    expect(isCleanupCandidate('wuji-track'), isFalse);
  });

  test('share 保留 7 天，其余沿用 24 小时', () {
    expect(cleanupMaxAgeFor('share', const Duration(hours: 24)),
        const Duration(days: 7));
    expect(cleanupMaxAgeFor('wuji-export', const Duration(hours: 24)),
        const Duration(hours: 24));
  });
}
