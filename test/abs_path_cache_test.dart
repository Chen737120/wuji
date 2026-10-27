import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/services/abs_path_cache.dart';
import 'package:wuji/services/archive_fs.dart';

/// 假解析器：按调用顺序返回预设路径（末项复用），并计数。
class _FakeResolver implements MediaPathResolver {
  _FakeResolver(this.paths);

  final List<String?> paths;
  int calls = 0;

  @override
  Future<String?> toAbsolutePath(String rel, {bool paced = false}) async {
    final i = calls < paths.length ? calls : paths.length - 1;
    calls++;
    return paths[i];
  }
}

void main() {
  late Directory tmp;
  late File fileA;
  late File fileB;

  setUp(() async {
    AbsPathCache.clearCache();
    tmp = await Directory.systemTemp.createTemp('wuji_abs_cache');
    fileA = File('${tmp.path}${Platform.pathSeparator}a.mp4')
      ..writeAsBytesSync([1, 2, 3]);
    fileB = File('${tmp.path}${Platform.pathSeparator}b.mp4')
      ..writeAsBytesSync([4, 5, 6]);
  });

  tearDown(() async {
    AbsPathCache.clearCache();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('命中缓存时 resolver 只调用一次', () async {
    final r = _FakeResolver([fileA.path]);
    expect(await AbsPathCache.resolve(r, 'media/a.mp4'), fileA.path);
    expect(await AbsPathCache.resolve(r, 'media/a.mp4'), fileA.path);
    expect(r.calls, 1);
  });

  test('缓存文件被删除后自动重解析', () async {
    final r = _FakeResolver([fileA.path, fileB.path]);
    expect(await AbsPathCache.resolve(r, 'media/a.mp4'), fileA.path);
    fileA.deleteSync();
    expect(await AbsPathCache.resolve(r, 'media/a.mp4'), fileB.path);
    expect(r.calls, 2);
  });

  test('resolver 为 null 返回 null，不回退相对路径', () async {
    expect(await AbsPathCache.resolve(null, 'media/a.mp4'), isNull);
  });

  test('解析失败不写缓存，下次可再试', () async {
    final r = _FakeResolver([null, fileA.path]);
    expect(await AbsPathCache.resolve(r, 'media/a.mp4'), isNull);
    expect(await AbsPathCache.resolve(r, 'media/a.mp4'), fileA.path);
    expect(r.calls, 2);
  });
}
