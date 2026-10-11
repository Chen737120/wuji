import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import '../services/photo_bridge.dart';

part 'db.g.dart';

/// 课：一条 = 一节课（含节数×每节时长）。名称快照冗余，名单删除不影响历史。
class ClassRecords extends Table {
  TextColumn get id => text()(); // uuid v4
  TextColumn get date => text()(); // yyyy-MM-dd
  TextColumn get styleId => text().nullable()();
  TextColumn get teacherId => text().nullable()();
  TextColumn get studioId => text().nullable()();
  TextColumn get styleName => text().nullable()();
  TextColumn get teacherName => text().nullable()();
  TextColumn get studioName => text().nullable()();
  IntColumn get sessionCount => integer().withDefault(const Constant(1))();
  IntColumn get minutesEach => integer().withDefault(const Constant(90))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 附件（视频/图片），相对路径基于存档文件夹。
class MediaAssets extends Table {
  TextColumn get id => text()(); // uuid v4
  TextColumn get classId =>
      text().references(ClassRecords, #id, onDelete: KeyAction.cascade)();
  TextColumn get type => text()(); // video | image
  TextColumn get fileName => text()(); // media/YYYY-MM/<uuid>.<ext>
  TextColumn get thumbName => text().nullable()();
  IntColumn get durationSec => integer().nullable()();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  /// 导入时留存的源文件基名（幂等补回的依据；本机保存为 null）
  TextColumn get sourceName => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 名单：舞种/老师/舞室共用。停用（isActive=false）不在新增弹层出现，历史不受影响。
@DataClassName('TaxonomyItem')
class Taxonomy extends Table {
  TextColumn get id => text()(); // uuid v4
  TextColumn get kind => text()(); // style | teacher | studio
  TextColumn get name => text()();
  BoolColumn get isBuiltin => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [{kind, name}];
}

extension ClassRecordRowX on ClassRecord {
  int get totalMinutes => sessionCount * minutesEach;
  DateTime get dateAsDateTime => DateTime.parse(date);
}

@DriftDatabase(tables: [ClassRecords, MediaAssets, Taxonomy])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());
  AppDatabase.forTesting(super.db);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(mediaAssets, mediaAssets.sourceName);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<ClassRecord> getClassRecord(String id) =>
      (select(classRecords)..where((t) => t.id.equals(id))).getSingle();
}

AppDatabase appDatabaseForTest() =>
    AppDatabase.forTesting(NativeDatabase.memory());

QueryExecutor _open() => LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/wuji.db');
      // iOS：数据库（含 WAL 伴生文件）排除 iCloud 备份——记录属个人数据，
      // 异地备份由「导出 zip」覆盖；文件未建/通道未就绪时静默
      if (Platform.isIOS) {
        for (final p in [file.path, '${file.path}-wal', '${file.path}-shm']) {
          await PhotoManagerBridge.excludeFromBackup(p);
        }
      }
      return NativeDatabase.createInBackground(file);
    });
