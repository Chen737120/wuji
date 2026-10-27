import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/ui/compare/compare_pick_page.dart';

/// P2-23：快速换源的初始化代际判断（旧代回写必须丢弃）。
void main() {
  test('staleGeneration：代际不同即过期', () {
    expect(staleGeneration(1, 1), isFalse);
    expect(staleGeneration(1, 2), isTrue);
    expect(staleGeneration(0, 1), isTrue);
  });
}
