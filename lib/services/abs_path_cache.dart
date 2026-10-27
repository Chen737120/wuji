import 'dart:io';

import 'archive_fs.dart';

/// 存档相对路径 → 临时绝对路径 的进程内缓存。
/// SAF 模式下解析=复制到缓存文件（开销不小），列表/日历/详情反复重建时
/// 必须命中缓存，否则反复复制。
class AbsPathCache {
  AbsPathCache._();

  static final _cache = <String, String>{};
  static final _inflight = <String, Future<String?>>{};

  static Future<String?> resolve(MediaPathResolver? resolver, String rel,
      {bool paced = false}) {
    // 无法解析 ≠ 相对路径可用（P1-13：相对路径交给播放器必然 Source error）
    if (resolver == null) return Future.value(null);
    final hit = _cache[rel];
    if (hit != null) {
      if (File(hit).existsSync()) return Future.value(hit);
      _cache.remove(rel); // 系统清缓存/拷贝被清理：重解析
    }
    final running = _inflight[rel];
    if (running != null) return running;
    final f = resolver.toAbsolutePath(rel, paced: paced).then((p) {
      if (p != null) _cache[rel] = p;
      return p;
    });
    _inflight[rel] = f;
    return f.whenComplete(() => _inflight.remove(rel));
  }

  /// 仅测试用：清空进程内缓存。
  static void clearCache() => _cache.clear();
}
