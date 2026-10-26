// SAF 分块写（2026-10-26 真机 394MB 视频保存 OOM 回归）：
// SafArchiveFs.write 旧实现 fold 整个流进 BytesBuilder，等于把整文件读进
// 内存；改为 ≤8MB 分块 + 首块覆盖/后续 append 写 SAF。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/services/saf_archive.dart';

void main() {
  test('chunkedBytes：按 maxBytes 切块、顺序与字节内容不变', () async {
    final src = Stream<List<int>>.fromIterable([
      [1, 2, 3],
      [4, 5, 6],
      [7, 8, 9],
    ]);
    final out = await chunkedBytes(src, maxBytes: 4).toList();
    expect(out.map((c) => c.length).toList(), [4, 4, 1]);
    expect(out.expand((c) => c).toList(), [1, 2, 3, 4, 5, 6, 7, 8, 9]);
  });

  test('chunkedBytes：空流不产出块（调用方补空文件）', () async {
    expect(await chunkedBytes(const Stream.empty(), maxBytes: 4).toList(),
        isEmpty);
    expect(
        await chunkedBytes(Stream.value(const <int>[]), maxBytes: 4).toList(),
        isEmpty);
  });

  test('chunkedBytes：大块输入仍被切成 ≤maxBytes', () async {
    final big = Uint8List(10)..fillRange(0, 10, 7);
    final out = await chunkedBytes(Stream.value(big), maxBytes: 4).toList();
    expect(out.map((c) => c.length).toList(), [4, 4, 2]);
    expect(out.every((c) => c.length <= 4), isTrue);
  });
}
