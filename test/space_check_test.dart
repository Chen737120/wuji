import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/data/app_repository.dart' show MediaInput;
import 'package:wuji/services/save_flow.dart';

void main() {
  test('needsSpaceWarning compares free vs incoming', () {
    expect(needsSpaceWarning(100, 200), isTrue);
    expect(needsSpaceWarning(200, 100), isFalse);
    expect(needsSpaceWarning(200, 200), isFalse);
    expect(needsSpaceWarning(null, 999), isFalse); // SAF 不可查询 → 不警告
    expect(needsSpaceWarning(100, 0), isFalse); // 没有新附件
  });

  test('incomingBytesOf sums sizes', () {
    final total = incomingBytesOf([
      const MediaInput(sourcePath: 'a', ext: 'mp4', isVideo: true, sizeBytes: 100),
      const MediaInput(sourcePath: 'b', ext: 'jpg', isVideo: false, sizeBytes: 23),
    ]);
    expect(total, 123);
  });
}
