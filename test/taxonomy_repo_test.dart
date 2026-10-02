import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/data/db.dart';
import 'package:wuji/data/taxonomy_repo.dart';
import 'package:wuji/models/models.dart';

void main() {
  late AppDatabase db;
  late TaxonomyRepo repo;
  setUp(() {
    db = appDatabaseForTest();
    repo = TaxonomyRepo(db);
  });
  tearDown(() => db.close());

  test('ensureBuiltins inserts exactly 19 styles, idempotent', () async {
    await repo.ensureBuiltins();
    await repo.ensureBuiltins();
    final styles = await repo.byKind(TaxonomyKind.style);
    expect(styles.length, 19);
    expect(styles.first.name, '爵士');
    expect(styles.map((e) => e.name),
        containsAll(['Hip Hop', 'K-Pop', 'Heels', '百老汇', '芭蕾']));
    // 顺序与规格 §3.4 一致（前 5 个抽查）
    expect(styles.take(5).map((e) => e.name).toList(),
        ['爵士', 'Hip Hop', 'K-Pop', 'Urban', '中国舞']);
  });

  test('touchByName creates then orders by lastUsedAt desc', () async {
    final base = DateTime(2026, 9, 30, 12);
    var tick = 0;
    final clockRepo = TaxonomyRepo(db, clock: () => base.add(Duration(minutes: tick++)));
    final a = await clockRepo.touchByName(TaxonomyKind.teacher, '小鹿');
    final b = await clockRepo.touchByName(TaxonomyKind.teacher, '阿哲');
    expect((await clockRepo.byKind(TaxonomyKind.teacher)).first.name, '阿哲');
    final again = await clockRepo.touchByName(TaxonomyKind.teacher, '小鹿');
    expect(again.id, a.id);
    final after = await clockRepo.byKind(TaxonomyKind.teacher);
    expect(after.first.name, '小鹿');
    expect(after.map((e) => e.name), contains('阿哲'));
    expect(b.id, isNot(a.id));
  });

  test('deactivate hides from default list, keeps in includeInactive', () async {
    final s = await repo.touchByName(TaxonomyKind.style, '自定义舞');
    await repo.deactivate(s.id);
    expect(
        (await repo.byKind(TaxonomyKind.style)).any((e) => e.id == s.id),
        isFalse);
    expect(
        (await repo.byKind(TaxonomyKind.style, includeInactive: true))
            .any((e) => e.id == s.id),
        isTrue);
  });

  test('rename keeps id and rows', () async {
    final s = await repo.touchByName(TaxonomyKind.studio, '光影舞室');
    await repo.rename(s.id, '光影舞室2');
    final list = await repo.byKind(TaxonomyKind.studio);
    expect(list.single.name, '光影舞室2');
    expect(list.single.id, s.id);
  });
}
