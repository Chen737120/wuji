import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'db.dart';
import '../models/models.dart';

/// 名单仓库：19 个预设舞种、自定义项、最近输入排序、停用不删行。
class TaxonomyRepo {
  TaxonomyRepo(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  static const _uuid = Uuid();
  String uuid() => _uuid.v4();

  /// 规格 §3.4 的 19 个预设舞种，顺序即网格顺序。
  static const builtinStyles = [
    '爵士', 'Hip Hop', 'K-Pop', 'Urban', '中国舞', '国风', '现代舞', 'Heels',
    'Popping', 'Locking', '百老汇', 'Breaking', 'House', 'Swag', 'Afro',
    'Waacking', 'Soul', '拉丁舞', '芭蕾',
  ];

  Future<void> ensureBuiltins() async {
    for (var i = 0; i < builtinStyles.length; i++) {
      final existing = await (_db.select(_db.taxonomy)
            ..where((t) =>
                t.kind.equals('style') & t.name.equals(builtinStyles[i])))
          .getSingleOrNull();
      if (existing == null) {
        await _db.into(_db.taxonomy).insert(TaxonomyCompanion.insert(
              id: uuid(),
              kind: 'style',
              name: builtinStyles[i],
              isBuiltin: const Value(true),
              sortOrder: Value(i),
            ));
      }
    }
  }

  /// style 按 sortOrder（预设）＋新自定义追加；teacher/studio 按最近使用在前。
  Future<List<TaxonomyItem>> byKind(TaxonomyKind kind,
      {bool includeInactive = false}) async {
    final query = _db.select(_db.taxonomy)
      ..where((t) => t.kind.equals(kind.dbValue));
    if (!includeInactive) query.where((t) => t.isActive.equals(true));
    final rows = await query.get();
    rows.sort((a, b) {
      if (kind == TaxonomyKind.style) {
        final bySort = a.sortOrder.compareTo(b.sortOrder);
        if (bySort != 0) return bySort;
      }
      final aUsed = a.lastUsedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bUsed = b.lastUsedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bUsed.compareTo(aUsed);
    });
    return rows;
  }

  /// 查/建并刷新 lastUsedAt；返回条目（新建的 isActive=true）。
  Future<TaxonomyItem> touchByName(TaxonomyKind kind, String name) async {
    final trimmed = name.trim();
    final now = _clock();
    // UNIQUE(kind,name) 覆盖停用行：先查任意状态的同名行，命中即复活
    //（P1-1：只查 active 会在停用过的名称上撞唯一约束，历史课保存必失败）
    final anyRow = await (_db.select(_db.taxonomy)
          ..where((t) =>
              t.kind.equals(kind.dbValue) & t.name.equals(trimmed)))
        .getSingleOrNull();
    if (anyRow != null) {
      await (_db.update(_db.taxonomy)..where((t) => t.id.equals(anyRow.id)))
          .write(TaxonomyCompanion(
              lastUsedAt: Value(now), isActive: const Value(true)));
      return anyRow.copyWith(lastUsedAt: Value(now), isActive: true);
    }
    final id = uuid();
    final maxSort = kind == TaxonomyKind.style
        ? (await (_db.select(_db.taxonomy)
                ..where((t) => t.kind.equals('style')))
              .get())
            .map((e) => e.sortOrder)
            .fold<int>(-1, (a, b) => a > b ? a : b)
        : 0;
    await _db.into(_db.taxonomy).insert(TaxonomyCompanion.insert(
          id: id,
          kind: kind.dbValue,
          name: trimmed,
          lastUsedAt: Value(now),
          sortOrder: Value(maxSort + 1),
        ));
    return TaxonomyItem(
      id: id,
      kind: kind.dbValue,
      name: trimmed,
      isBuiltin: false,
      sortOrder: maxSort + 1,
      lastUsedAt: now,
      isActive: true,
    );
  }

  Future<void> rename(String id, String newName) async {
    await (_db.update(_db.taxonomy)..where((t) => t.id.equals(id)))
        .write(TaxonomyCompanion(name: Value(newName.trim())));
  }

  /// 停用：新增弹层不再出现；历史课快照不受影响。
  Future<void> deactivate(String id) async {
    await (_db.update(_db.taxonomy)..where((t) => t.id.equals(id)))
        .write(const TaxonomyCompanion(isActive: Value(false)));
  }
}
