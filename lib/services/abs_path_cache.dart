import 'archive_fs.dart';

/// 存档相对路径 → 临时绝对路径 的进程内缓存。
/// SAF 模式下解析=复制到缓存文件（开销不小），列表/日历/详情反复重建时
/// 必须命中缓存，否则反复复制。
class AbsPathCache {
  AbsPathCache._();

  static final _cache = <String, String>{};
  static final _inflight = <String, Future<String?>>{};

  static Future<String?> resolve(MediaPathResolver? resolver, String rel) {
    if (resolver == null) return Future.value(rel);
    final hit = _cache[rel];
    if (hit != null) return Future.value(hit);
    final running = _inflight[rel];
    if (running != null) return running;
    final f = resolver.toAbsolutePath(rel).then((p) {
      if (p != null) _cache[rel] = p;
      return p;
    });
    _inflight[rel] = f;
    return f.whenComplete(() => _inflight.remove(rel));
  }
}
