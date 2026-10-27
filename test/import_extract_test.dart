import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/ui/import_page.dart';

/// P1-4：备份包解压抽成顶层函数（Isolate.run 内执行），zip-slip 规则不变。
void main() {
  late Directory tmp;
  late String zipPath;
  late String outPath;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wuji_extract');
    zipPath = '${tmp.path}${Platform.pathSeparator}backup.zip';
    outPath = '${tmp.path}${Platform.pathSeparator}out';
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  void writeZip(List<(String, List<int>)> entries) {
    final archive = Archive();
    for (final (name, bytes) in entries) {
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }
    final data = ZipEncoder().encode(archive);
    File(zipPath).writeAsBytesSync(data!);
  }

  test('正常条目解出、zip-slip 条目全部跳过（不写盘）', () {
    writeZip([
      ('舞记数据.json', '{}'.codeUnits),
      ('2026-01-01_爵士_张三/a.mp4', [1, 2, 3]),
      ('../evil.txt', 'evil'.codeUnits),
      ('/abs.txt', 'abs'.codeUnits),
      ('c:d.txt', 'drive'.codeUnits),
    ]);

    final n = extractZipSafely(zipPath, outPath);

    // 5 条里只有 2 条是安全路径（任务书写的「返回 3」与列出的条目数不自洽，
    // 以实际解出条目为准）
    expect(n, 2);
    expect(File('$outPath${Platform.pathSeparator}舞记数据.json').existsSync(),
        isTrue);
    expect(
        File('$outPath${Platform.pathSeparator}2026-01-01_爵士_张三'
                '${Platform.pathSeparator}a.mp4')
            .existsSync(),
        isTrue);
    // 恶意条目不落盘；且不逃出 out 目录
    expect(File('${tmp.path}${Platform.pathSeparator}evil.txt').existsSync(),
        isFalse);
    expect(File('${tmp.path}${Platform.pathSeparator}abs.txt').existsSync(),
        isFalse);
    expect(File('$outPath${Platform.pathSeparator}c:d.txt').existsSync(),
        isFalse);
    final extracted = Directory(outPath)
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.substring(outPath.length + 1))
        .toList();
    expect(extracted, hasLength(2), reason: '实际解出: $extracted');
  });

  test('空 zip 返回 0，不抛', () {
    writeZip([]);
    expect(extractZipSafely(zipPath, outPath), 0);
  });

  test('反斜杠路径按 / 归一化后仍能解出', () {
    writeZip([(r'a\b.txt', [7])]);
    expect(extractZipSafely(zipPath, outPath), 1);
    final expected = '$outPath${Platform.pathSeparator}a'
        '${Platform.pathSeparator}b.txt';
    expect(File(expected).existsSync(), isTrue, reason: '应归一化为 a/b.txt');
  });
}
