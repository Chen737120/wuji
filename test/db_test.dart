import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/data/db.dart';
import 'helpers/sqlite_windows.dart';

void main() {
  late AppDatabase db;
  setUpAll(configSqliteForWindowsTest);
  setUp(() => db = appDatabaseForTest());
  tearDown(() => db.close());

  ClassRecordsCompanion recRow(String id, {String? style, String? teacher}) =>
      ClassRecordsCompanion.insert(
        id: id,
        date: '2026-09-30',
        styleName: Value(style),
        teacherName: Value(teacher),
        createdAt: DateTime(2026, 9, 30, 12),
        updatedAt: DateTime(2026, 9, 30, 12),
      );

  test('record roundtrip keeps snapshot names', () async {
    await db
        .into(db.classRecords)
        .insert(recRow('r1', style: '爵士', teacher: '小鹿'));
    final row = await db.getClassRecord('r1');
    expect(row.sessionCount, 1);
    expect(row.minutesEach, 90);
    expect(row.totalMinutes, 90);
    expect(row.styleName, '爵士');
    expect(row.teacherName, '小鹿');
  });

  test('totalMinutes multiplies sessions × minutesEach', () async {
    await db.into(db.classRecords).insert(ClassRecordsCompanion.insert(
          id: 'r2',
          date: '2026-09-30',
          sessionCount: const Value(2),
          minutesEach: const Value(90),
          createdAt: DateTime(2026, 9, 30, 12),
          updatedAt: DateTime(2026, 9, 30, 12),
        ));
    final row = await db.getClassRecord('r2');
    expect(row.totalMinutes, 180);
  });

  test('deleting record cascades media rows', () async {
    await db.into(db.classRecords).insert(recRow('r3'));
    await db.into(db.mediaAssets).insert(MediaAssetsCompanion.insert(
          id: 'm1',
          classId: 'r3',
          type: 'video',
          fileName: 'media/2026-09/a.mp4',
          createdAt: DateTime(2026, 9, 30, 12),
        ));
    expect(await db.select(db.mediaAssets).get(), hasLength(1));
    await (db.delete(db.classRecords)..where((t) => t.id.equals('r3'))).go();
    expect(await db.select(db.mediaAssets).get(), isEmpty);
  });

  test('taxonomy unique per kind+name', () async {
    await db.into(db.taxonomy).insert(TaxonomyCompanion.insert(
          id: 't1',
          kind: 'style',
          name: '爵士',
        ));
    expect(
        () => db.into(db.taxonomy).insert(TaxonomyCompanion.insert(
              id: 't2',
              kind: 'style',
              name: '爵士',
            )),
        throwsA(anything));
  });
}
