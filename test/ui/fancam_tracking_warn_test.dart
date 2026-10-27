import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/ui/fancam/fancam_page.dart';

/// P2-12：跟踪时长提示阈值（只警告不阻断，硬限制属产品决策）。
void main() {
  test('trackWarnThreshold = 90s', () {
    expect(trackWarnThreshold, const Duration(seconds: 90));
  });

  test('89s/90s 不提示，91s 提示', () {
    expect(shouldWarnLongTracking(const Duration(seconds: 89)), isFalse);
    expect(shouldWarnLongTracking(const Duration(seconds: 90)), isFalse);
    expect(shouldWarnLongTracking(const Duration(seconds: 91)), isTrue);
  });
}
