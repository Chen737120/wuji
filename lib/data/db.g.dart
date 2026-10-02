// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'db.dart';

// ignore_for_file: type=lint
class $ClassRecordsTable extends ClassRecords
    with TableInfo<$ClassRecordsTable, ClassRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClassRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _styleIdMeta = const VerificationMeta(
    'styleId',
  );
  @override
  late final GeneratedColumn<String> styleId = GeneratedColumn<String>(
    'style_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _teacherIdMeta = const VerificationMeta(
    'teacherId',
  );
  @override
  late final GeneratedColumn<String> teacherId = GeneratedColumn<String>(
    'teacher_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _studioIdMeta = const VerificationMeta(
    'studioId',
  );
  @override
  late final GeneratedColumn<String> studioId = GeneratedColumn<String>(
    'studio_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _styleNameMeta = const VerificationMeta(
    'styleName',
  );
  @override
  late final GeneratedColumn<String> styleName = GeneratedColumn<String>(
    'style_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _teacherNameMeta = const VerificationMeta(
    'teacherName',
  );
  @override
  late final GeneratedColumn<String> teacherName = GeneratedColumn<String>(
    'teacher_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _studioNameMeta = const VerificationMeta(
    'studioName',
  );
  @override
  late final GeneratedColumn<String> studioName = GeneratedColumn<String>(
    'studio_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sessionCountMeta = const VerificationMeta(
    'sessionCount',
  );
  @override
  late final GeneratedColumn<int> sessionCount = GeneratedColumn<int>(
    'session_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _minutesEachMeta = const VerificationMeta(
    'minutesEach',
  );
  @override
  late final GeneratedColumn<int> minutesEach = GeneratedColumn<int>(
    'minutes_each',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(90),
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    date,
    styleId,
    teacherId,
    studioId,
    styleName,
    teacherName,
    studioName,
    sessionCount,
    minutesEach,
    note,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'class_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<ClassRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('style_id')) {
      context.handle(
        _styleIdMeta,
        styleId.isAcceptableOrUnknown(data['style_id']!, _styleIdMeta),
      );
    }
    if (data.containsKey('teacher_id')) {
      context.handle(
        _teacherIdMeta,
        teacherId.isAcceptableOrUnknown(data['teacher_id']!, _teacherIdMeta),
      );
    }
    if (data.containsKey('studio_id')) {
      context.handle(
        _studioIdMeta,
        studioId.isAcceptableOrUnknown(data['studio_id']!, _studioIdMeta),
      );
    }
    if (data.containsKey('style_name')) {
      context.handle(
        _styleNameMeta,
        styleName.isAcceptableOrUnknown(data['style_name']!, _styleNameMeta),
      );
    }
    if (data.containsKey('teacher_name')) {
      context.handle(
        _teacherNameMeta,
        teacherName.isAcceptableOrUnknown(
          data['teacher_name']!,
          _teacherNameMeta,
        ),
      );
    }
    if (data.containsKey('studio_name')) {
      context.handle(
        _studioNameMeta,
        studioName.isAcceptableOrUnknown(data['studio_name']!, _studioNameMeta),
      );
    }
    if (data.containsKey('session_count')) {
      context.handle(
        _sessionCountMeta,
        sessionCount.isAcceptableOrUnknown(
          data['session_count']!,
          _sessionCountMeta,
        ),
      );
    }
    if (data.containsKey('minutes_each')) {
      context.handle(
        _minutesEachMeta,
        minutesEach.isAcceptableOrUnknown(
          data['minutes_each']!,
          _minutesEachMeta,
        ),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ClassRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClassRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      styleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}style_id'],
      ),
      teacherId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}teacher_id'],
      ),
      studioId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}studio_id'],
      ),
      styleName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}style_name'],
      ),
      teacherName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}teacher_name'],
      ),
      studioName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}studio_name'],
      ),
      sessionCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_count'],
      )!,
      minutesEach: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}minutes_each'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ClassRecordsTable createAlias(String alias) {
    return $ClassRecordsTable(attachedDatabase, alias);
  }
}

class ClassRecord extends DataClass implements Insertable<ClassRecord> {
  final String id;
  final String date;
  final String? styleId;
  final String? teacherId;
  final String? studioId;
  final String? styleName;
  final String? teacherName;
  final String? studioName;
  final int sessionCount;
  final int minutesEach;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ClassRecord({
    required this.id,
    required this.date,
    this.styleId,
    this.teacherId,
    this.studioId,
    this.styleName,
    this.teacherName,
    this.studioName,
    required this.sessionCount,
    required this.minutesEach,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['date'] = Variable<String>(date);
    if (!nullToAbsent || styleId != null) {
      map['style_id'] = Variable<String>(styleId);
    }
    if (!nullToAbsent || teacherId != null) {
      map['teacher_id'] = Variable<String>(teacherId);
    }
    if (!nullToAbsent || studioId != null) {
      map['studio_id'] = Variable<String>(studioId);
    }
    if (!nullToAbsent || styleName != null) {
      map['style_name'] = Variable<String>(styleName);
    }
    if (!nullToAbsent || teacherName != null) {
      map['teacher_name'] = Variable<String>(teacherName);
    }
    if (!nullToAbsent || studioName != null) {
      map['studio_name'] = Variable<String>(studioName);
    }
    map['session_count'] = Variable<int>(sessionCount);
    map['minutes_each'] = Variable<int>(minutesEach);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ClassRecordsCompanion toCompanion(bool nullToAbsent) {
    return ClassRecordsCompanion(
      id: Value(id),
      date: Value(date),
      styleId: styleId == null && nullToAbsent
          ? const Value.absent()
          : Value(styleId),
      teacherId: teacherId == null && nullToAbsent
          ? const Value.absent()
          : Value(teacherId),
      studioId: studioId == null && nullToAbsent
          ? const Value.absent()
          : Value(studioId),
      styleName: styleName == null && nullToAbsent
          ? const Value.absent()
          : Value(styleName),
      teacherName: teacherName == null && nullToAbsent
          ? const Value.absent()
          : Value(teacherName),
      studioName: studioName == null && nullToAbsent
          ? const Value.absent()
          : Value(studioName),
      sessionCount: Value(sessionCount),
      minutesEach: Value(minutesEach),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ClassRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClassRecord(
      id: serializer.fromJson<String>(json['id']),
      date: serializer.fromJson<String>(json['date']),
      styleId: serializer.fromJson<String?>(json['styleId']),
      teacherId: serializer.fromJson<String?>(json['teacherId']),
      studioId: serializer.fromJson<String?>(json['studioId']),
      styleName: serializer.fromJson<String?>(json['styleName']),
      teacherName: serializer.fromJson<String?>(json['teacherName']),
      studioName: serializer.fromJson<String?>(json['studioName']),
      sessionCount: serializer.fromJson<int>(json['sessionCount']),
      minutesEach: serializer.fromJson<int>(json['minutesEach']),
      note: serializer.fromJson<String?>(json['note']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'date': serializer.toJson<String>(date),
      'styleId': serializer.toJson<String?>(styleId),
      'teacherId': serializer.toJson<String?>(teacherId),
      'studioId': serializer.toJson<String?>(studioId),
      'styleName': serializer.toJson<String?>(styleName),
      'teacherName': serializer.toJson<String?>(teacherName),
      'studioName': serializer.toJson<String?>(studioName),
      'sessionCount': serializer.toJson<int>(sessionCount),
      'minutesEach': serializer.toJson<int>(minutesEach),
      'note': serializer.toJson<String?>(note),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ClassRecord copyWith({
    String? id,
    String? date,
    Value<String?> styleId = const Value.absent(),
    Value<String?> teacherId = const Value.absent(),
    Value<String?> studioId = const Value.absent(),
    Value<String?> styleName = const Value.absent(),
    Value<String?> teacherName = const Value.absent(),
    Value<String?> studioName = const Value.absent(),
    int? sessionCount,
    int? minutesEach,
    Value<String?> note = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ClassRecord(
    id: id ?? this.id,
    date: date ?? this.date,
    styleId: styleId.present ? styleId.value : this.styleId,
    teacherId: teacherId.present ? teacherId.value : this.teacherId,
    studioId: studioId.present ? studioId.value : this.studioId,
    styleName: styleName.present ? styleName.value : this.styleName,
    teacherName: teacherName.present ? teacherName.value : this.teacherName,
    studioName: studioName.present ? studioName.value : this.studioName,
    sessionCount: sessionCount ?? this.sessionCount,
    minutesEach: minutesEach ?? this.minutesEach,
    note: note.present ? note.value : this.note,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ClassRecord copyWithCompanion(ClassRecordsCompanion data) {
    return ClassRecord(
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      styleId: data.styleId.present ? data.styleId.value : this.styleId,
      teacherId: data.teacherId.present ? data.teacherId.value : this.teacherId,
      studioId: data.studioId.present ? data.studioId.value : this.studioId,
      styleName: data.styleName.present ? data.styleName.value : this.styleName,
      teacherName: data.teacherName.present
          ? data.teacherName.value
          : this.teacherName,
      studioName: data.studioName.present
          ? data.studioName.value
          : this.studioName,
      sessionCount: data.sessionCount.present
          ? data.sessionCount.value
          : this.sessionCount,
      minutesEach: data.minutesEach.present
          ? data.minutesEach.value
          : this.minutesEach,
      note: data.note.present ? data.note.value : this.note,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClassRecord(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('styleId: $styleId, ')
          ..write('teacherId: $teacherId, ')
          ..write('studioId: $studioId, ')
          ..write('styleName: $styleName, ')
          ..write('teacherName: $teacherName, ')
          ..write('studioName: $studioName, ')
          ..write('sessionCount: $sessionCount, ')
          ..write('minutesEach: $minutesEach, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    date,
    styleId,
    teacherId,
    studioId,
    styleName,
    teacherName,
    studioName,
    sessionCount,
    minutesEach,
    note,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClassRecord &&
          other.id == this.id &&
          other.date == this.date &&
          other.styleId == this.styleId &&
          other.teacherId == this.teacherId &&
          other.studioId == this.studioId &&
          other.styleName == this.styleName &&
          other.teacherName == this.teacherName &&
          other.studioName == this.studioName &&
          other.sessionCount == this.sessionCount &&
          other.minutesEach == this.minutesEach &&
          other.note == this.note &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ClassRecordsCompanion extends UpdateCompanion<ClassRecord> {
  final Value<String> id;
  final Value<String> date;
  final Value<String?> styleId;
  final Value<String?> teacherId;
  final Value<String?> studioId;
  final Value<String?> styleName;
  final Value<String?> teacherName;
  final Value<String?> studioName;
  final Value<int> sessionCount;
  final Value<int> minutesEach;
  final Value<String?> note;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ClassRecordsCompanion({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.styleId = const Value.absent(),
    this.teacherId = const Value.absent(),
    this.studioId = const Value.absent(),
    this.styleName = const Value.absent(),
    this.teacherName = const Value.absent(),
    this.studioName = const Value.absent(),
    this.sessionCount = const Value.absent(),
    this.minutesEach = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClassRecordsCompanion.insert({
    required String id,
    required String date,
    this.styleId = const Value.absent(),
    this.teacherId = const Value.absent(),
    this.studioId = const Value.absent(),
    this.styleName = const Value.absent(),
    this.teacherName = const Value.absent(),
    this.studioName = const Value.absent(),
    this.sessionCount = const Value.absent(),
    this.minutesEach = const Value.absent(),
    this.note = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       date = Value(date),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ClassRecord> custom({
    Expression<String>? id,
    Expression<String>? date,
    Expression<String>? styleId,
    Expression<String>? teacherId,
    Expression<String>? studioId,
    Expression<String>? styleName,
    Expression<String>? teacherName,
    Expression<String>? studioName,
    Expression<int>? sessionCount,
    Expression<int>? minutesEach,
    Expression<String>? note,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (styleId != null) 'style_id': styleId,
      if (teacherId != null) 'teacher_id': teacherId,
      if (studioId != null) 'studio_id': studioId,
      if (styleName != null) 'style_name': styleName,
      if (teacherName != null) 'teacher_name': teacherName,
      if (studioName != null) 'studio_name': studioName,
      if (sessionCount != null) 'session_count': sessionCount,
      if (minutesEach != null) 'minutes_each': minutesEach,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClassRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? date,
    Value<String?>? styleId,
    Value<String?>? teacherId,
    Value<String?>? studioId,
    Value<String?>? styleName,
    Value<String?>? teacherName,
    Value<String?>? studioName,
    Value<int>? sessionCount,
    Value<int>? minutesEach,
    Value<String?>? note,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ClassRecordsCompanion(
      id: id ?? this.id,
      date: date ?? this.date,
      styleId: styleId ?? this.styleId,
      teacherId: teacherId ?? this.teacherId,
      studioId: studioId ?? this.studioId,
      styleName: styleName ?? this.styleName,
      teacherName: teacherName ?? this.teacherName,
      studioName: studioName ?? this.studioName,
      sessionCount: sessionCount ?? this.sessionCount,
      minutesEach: minutesEach ?? this.minutesEach,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (styleId.present) {
      map['style_id'] = Variable<String>(styleId.value);
    }
    if (teacherId.present) {
      map['teacher_id'] = Variable<String>(teacherId.value);
    }
    if (studioId.present) {
      map['studio_id'] = Variable<String>(studioId.value);
    }
    if (styleName.present) {
      map['style_name'] = Variable<String>(styleName.value);
    }
    if (teacherName.present) {
      map['teacher_name'] = Variable<String>(teacherName.value);
    }
    if (studioName.present) {
      map['studio_name'] = Variable<String>(studioName.value);
    }
    if (sessionCount.present) {
      map['session_count'] = Variable<int>(sessionCount.value);
    }
    if (minutesEach.present) {
      map['minutes_each'] = Variable<int>(minutesEach.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClassRecordsCompanion(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('styleId: $styleId, ')
          ..write('teacherId: $teacherId, ')
          ..write('studioId: $studioId, ')
          ..write('styleName: $styleName, ')
          ..write('teacherName: $teacherName, ')
          ..write('studioName: $studioName, ')
          ..write('sessionCount: $sessionCount, ')
          ..write('minutesEach: $minutesEach, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MediaAssetsTable extends MediaAssets
    with TableInfo<$MediaAssetsTable, MediaAsset> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaAssetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _classIdMeta = const VerificationMeta(
    'classId',
  );
  @override
  late final GeneratedColumn<String> classId = GeneratedColumn<String>(
    'class_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES class_records (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thumbNameMeta = const VerificationMeta(
    'thumbName',
  );
  @override
  late final GeneratedColumn<String> thumbName = GeneratedColumn<String>(
    'thumb_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationSecMeta = const VerificationMeta(
    'durationSec',
  );
  @override
  late final GeneratedColumn<int> durationSec = GeneratedColumn<int>(
    'duration_sec',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    classId,
    type,
    fileName,
    thumbName,
    durationSec,
    sizeBytes,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_assets';
  @override
  VerificationContext validateIntegrity(
    Insertable<MediaAsset> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('class_id')) {
      context.handle(
        _classIdMeta,
        classId.isAcceptableOrUnknown(data['class_id']!, _classIdMeta),
      );
    } else if (isInserting) {
      context.missing(_classIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('thumb_name')) {
      context.handle(
        _thumbNameMeta,
        thumbName.isAcceptableOrUnknown(data['thumb_name']!, _thumbNameMeta),
      );
    }
    if (data.containsKey('duration_sec')) {
      context.handle(
        _durationSecMeta,
        durationSec.isAcceptableOrUnknown(
          data['duration_sec']!,
          _durationSecMeta,
        ),
      );
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MediaAsset map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaAsset(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      classId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}class_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      thumbName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumb_name'],
      ),
      durationSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_sec'],
      ),
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $MediaAssetsTable createAlias(String alias) {
    return $MediaAssetsTable(attachedDatabase, alias);
  }
}

class MediaAsset extends DataClass implements Insertable<MediaAsset> {
  final String id;
  final String classId;
  final String type;
  final String fileName;
  final String? thumbName;
  final int? durationSec;
  final int sizeBytes;
  final DateTime createdAt;
  const MediaAsset({
    required this.id,
    required this.classId,
    required this.type,
    required this.fileName,
    this.thumbName,
    this.durationSec,
    required this.sizeBytes,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['class_id'] = Variable<String>(classId);
    map['type'] = Variable<String>(type);
    map['file_name'] = Variable<String>(fileName);
    if (!nullToAbsent || thumbName != null) {
      map['thumb_name'] = Variable<String>(thumbName);
    }
    if (!nullToAbsent || durationSec != null) {
      map['duration_sec'] = Variable<int>(durationSec);
    }
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  MediaAssetsCompanion toCompanion(bool nullToAbsent) {
    return MediaAssetsCompanion(
      id: Value(id),
      classId: Value(classId),
      type: Value(type),
      fileName: Value(fileName),
      thumbName: thumbName == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbName),
      durationSec: durationSec == null && nullToAbsent
          ? const Value.absent()
          : Value(durationSec),
      sizeBytes: Value(sizeBytes),
      createdAt: Value(createdAt),
    );
  }

  factory MediaAsset.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaAsset(
      id: serializer.fromJson<String>(json['id']),
      classId: serializer.fromJson<String>(json['classId']),
      type: serializer.fromJson<String>(json['type']),
      fileName: serializer.fromJson<String>(json['fileName']),
      thumbName: serializer.fromJson<String?>(json['thumbName']),
      durationSec: serializer.fromJson<int?>(json['durationSec']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'classId': serializer.toJson<String>(classId),
      'type': serializer.toJson<String>(type),
      'fileName': serializer.toJson<String>(fileName),
      'thumbName': serializer.toJson<String?>(thumbName),
      'durationSec': serializer.toJson<int?>(durationSec),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  MediaAsset copyWith({
    String? id,
    String? classId,
    String? type,
    String? fileName,
    Value<String?> thumbName = const Value.absent(),
    Value<int?> durationSec = const Value.absent(),
    int? sizeBytes,
    DateTime? createdAt,
  }) => MediaAsset(
    id: id ?? this.id,
    classId: classId ?? this.classId,
    type: type ?? this.type,
    fileName: fileName ?? this.fileName,
    thumbName: thumbName.present ? thumbName.value : this.thumbName,
    durationSec: durationSec.present ? durationSec.value : this.durationSec,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    createdAt: createdAt ?? this.createdAt,
  );
  MediaAsset copyWithCompanion(MediaAssetsCompanion data) {
    return MediaAsset(
      id: data.id.present ? data.id.value : this.id,
      classId: data.classId.present ? data.classId.value : this.classId,
      type: data.type.present ? data.type.value : this.type,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      thumbName: data.thumbName.present ? data.thumbName.value : this.thumbName,
      durationSec: data.durationSec.present
          ? data.durationSec.value
          : this.durationSec,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaAsset(')
          ..write('id: $id, ')
          ..write('classId: $classId, ')
          ..write('type: $type, ')
          ..write('fileName: $fileName, ')
          ..write('thumbName: $thumbName, ')
          ..write('durationSec: $durationSec, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    classId,
    type,
    fileName,
    thumbName,
    durationSec,
    sizeBytes,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaAsset &&
          other.id == this.id &&
          other.classId == this.classId &&
          other.type == this.type &&
          other.fileName == this.fileName &&
          other.thumbName == this.thumbName &&
          other.durationSec == this.durationSec &&
          other.sizeBytes == this.sizeBytes &&
          other.createdAt == this.createdAt);
}

class MediaAssetsCompanion extends UpdateCompanion<MediaAsset> {
  final Value<String> id;
  final Value<String> classId;
  final Value<String> type;
  final Value<String> fileName;
  final Value<String?> thumbName;
  final Value<int?> durationSec;
  final Value<int> sizeBytes;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const MediaAssetsCompanion({
    this.id = const Value.absent(),
    this.classId = const Value.absent(),
    this.type = const Value.absent(),
    this.fileName = const Value.absent(),
    this.thumbName = const Value.absent(),
    this.durationSec = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaAssetsCompanion.insert({
    required String id,
    required String classId,
    required String type,
    required String fileName,
    this.thumbName = const Value.absent(),
    this.durationSec = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       classId = Value(classId),
       type = Value(type),
       fileName = Value(fileName),
       createdAt = Value(createdAt);
  static Insertable<MediaAsset> custom({
    Expression<String>? id,
    Expression<String>? classId,
    Expression<String>? type,
    Expression<String>? fileName,
    Expression<String>? thumbName,
    Expression<int>? durationSec,
    Expression<int>? sizeBytes,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (classId != null) 'class_id': classId,
      if (type != null) 'type': type,
      if (fileName != null) 'file_name': fileName,
      if (thumbName != null) 'thumb_name': thumbName,
      if (durationSec != null) 'duration_sec': durationSec,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaAssetsCompanion copyWith({
    Value<String>? id,
    Value<String>? classId,
    Value<String>? type,
    Value<String>? fileName,
    Value<String?>? thumbName,
    Value<int?>? durationSec,
    Value<int>? sizeBytes,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return MediaAssetsCompanion(
      id: id ?? this.id,
      classId: classId ?? this.classId,
      type: type ?? this.type,
      fileName: fileName ?? this.fileName,
      thumbName: thumbName ?? this.thumbName,
      durationSec: durationSec ?? this.durationSec,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (classId.present) {
      map['class_id'] = Variable<String>(classId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (thumbName.present) {
      map['thumb_name'] = Variable<String>(thumbName.value);
    }
    if (durationSec.present) {
      map['duration_sec'] = Variable<int>(durationSec.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaAssetsCompanion(')
          ..write('id: $id, ')
          ..write('classId: $classId, ')
          ..write('type: $type, ')
          ..write('fileName: $fileName, ')
          ..write('thumbName: $thumbName, ')
          ..write('durationSec: $durationSec, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TaxonomyTable extends Taxonomy
    with TableInfo<$TaxonomyTable, TaxonomyItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaxonomyTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isBuiltinMeta = const VerificationMeta(
    'isBuiltin',
  );
  @override
  late final GeneratedColumn<bool> isBuiltin = GeneratedColumn<bool>(
    'is_builtin',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_builtin" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastUsedAtMeta = const VerificationMeta(
    'lastUsedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastUsedAt = GeneratedColumn<DateTime>(
    'last_used_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    name,
    isBuiltin,
    sortOrder,
    lastUsedAt,
    isActive,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'taxonomy';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaxonomyItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('is_builtin')) {
      context.handle(
        _isBuiltinMeta,
        isBuiltin.isAcceptableOrUnknown(data['is_builtin']!, _isBuiltinMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('last_used_at')) {
      context.handle(
        _lastUsedAtMeta,
        lastUsedAt.isAcceptableOrUnknown(
          data['last_used_at']!,
          _lastUsedAtMeta,
        ),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {kind, name},
  ];
  @override
  TaxonomyItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaxonomyItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      isBuiltin: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_builtin'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      lastUsedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_used_at'],
      ),
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $TaxonomyTable createAlias(String alias) {
    return $TaxonomyTable(attachedDatabase, alias);
  }
}

class TaxonomyItem extends DataClass implements Insertable<TaxonomyItem> {
  final String id;
  final String kind;
  final String name;
  final bool isBuiltin;
  final int sortOrder;
  final DateTime? lastUsedAt;
  final bool isActive;
  const TaxonomyItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.isBuiltin,
    required this.sortOrder,
    this.lastUsedAt,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    map['name'] = Variable<String>(name);
    map['is_builtin'] = Variable<bool>(isBuiltin);
    map['sort_order'] = Variable<int>(sortOrder);
    if (!nullToAbsent || lastUsedAt != null) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt);
    }
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  TaxonomyCompanion toCompanion(bool nullToAbsent) {
    return TaxonomyCompanion(
      id: Value(id),
      kind: Value(kind),
      name: Value(name),
      isBuiltin: Value(isBuiltin),
      sortOrder: Value(sortOrder),
      lastUsedAt: lastUsedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastUsedAt),
      isActive: Value(isActive),
    );
  }

  factory TaxonomyItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaxonomyItem(
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      name: serializer.fromJson<String>(json['name']),
      isBuiltin: serializer.fromJson<bool>(json['isBuiltin']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      lastUsedAt: serializer.fromJson<DateTime?>(json['lastUsedAt']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'name': serializer.toJson<String>(name),
      'isBuiltin': serializer.toJson<bool>(isBuiltin),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'lastUsedAt': serializer.toJson<DateTime?>(lastUsedAt),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  TaxonomyItem copyWith({
    String? id,
    String? kind,
    String? name,
    bool? isBuiltin,
    int? sortOrder,
    Value<DateTime?> lastUsedAt = const Value.absent(),
    bool? isActive,
  }) => TaxonomyItem(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    isBuiltin: isBuiltin ?? this.isBuiltin,
    sortOrder: sortOrder ?? this.sortOrder,
    lastUsedAt: lastUsedAt.present ? lastUsedAt.value : this.lastUsedAt,
    isActive: isActive ?? this.isActive,
  );
  TaxonomyItem copyWithCompanion(TaxonomyCompanion data) {
    return TaxonomyItem(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      name: data.name.present ? data.name.value : this.name,
      isBuiltin: data.isBuiltin.present ? data.isBuiltin.value : this.isBuiltin,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      lastUsedAt: data.lastUsedAt.present
          ? data.lastUsedAt.value
          : this.lastUsedAt,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaxonomyItem(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('isBuiltin: $isBuiltin, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, kind, name, isBuiltin, sortOrder, lastUsedAt, isActive);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaxonomyItem &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.name == this.name &&
          other.isBuiltin == this.isBuiltin &&
          other.sortOrder == this.sortOrder &&
          other.lastUsedAt == this.lastUsedAt &&
          other.isActive == this.isActive);
}

class TaxonomyCompanion extends UpdateCompanion<TaxonomyItem> {
  final Value<String> id;
  final Value<String> kind;
  final Value<String> name;
  final Value<bool> isBuiltin;
  final Value<int> sortOrder;
  final Value<DateTime?> lastUsedAt;
  final Value<bool> isActive;
  final Value<int> rowid;
  const TaxonomyCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.name = const Value.absent(),
    this.isBuiltin = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaxonomyCompanion.insert({
    required String id,
    required String kind,
    required String name,
    this.isBuiltin = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       name = Value(name);
  static Insertable<TaxonomyItem> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? name,
    Expression<bool>? isBuiltin,
    Expression<int>? sortOrder,
    Expression<DateTime>? lastUsedAt,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (name != null) 'name': name,
      if (isBuiltin != null) 'is_builtin': isBuiltin,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaxonomyCompanion copyWith({
    Value<String>? id,
    Value<String>? kind,
    Value<String>? name,
    Value<bool>? isBuiltin,
    Value<int>? sortOrder,
    Value<DateTime?>? lastUsedAt,
    Value<bool>? isActive,
    Value<int>? rowid,
  }) {
    return TaxonomyCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      sortOrder: sortOrder ?? this.sortOrder,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      isActive: isActive ?? this.isActive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isBuiltin.present) {
      map['is_builtin'] = Variable<bool>(isBuiltin.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (lastUsedAt.present) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaxonomyCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('isBuiltin: $isBuiltin, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ClassRecordsTable classRecords = $ClassRecordsTable(this);
  late final $MediaAssetsTable mediaAssets = $MediaAssetsTable(this);
  late final $TaxonomyTable taxonomy = $TaxonomyTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    classRecords,
    mediaAssets,
    taxonomy,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'class_records',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('media_assets', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$ClassRecordsTableCreateCompanionBuilder =
    ClassRecordsCompanion Function({
      required String id,
      required String date,
      Value<String?> styleId,
      Value<String?> teacherId,
      Value<String?> studioId,
      Value<String?> styleName,
      Value<String?> teacherName,
      Value<String?> studioName,
      Value<int> sessionCount,
      Value<int> minutesEach,
      Value<String?> note,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ClassRecordsTableUpdateCompanionBuilder =
    ClassRecordsCompanion Function({
      Value<String> id,
      Value<String> date,
      Value<String?> styleId,
      Value<String?> teacherId,
      Value<String?> studioId,
      Value<String?> styleName,
      Value<String?> teacherName,
      Value<String?> studioName,
      Value<int> sessionCount,
      Value<int> minutesEach,
      Value<String?> note,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ClassRecordsTableReferences
    extends BaseReferences<_$AppDatabase, $ClassRecordsTable, ClassRecord> {
  $$ClassRecordsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MediaAssetsTable, List<MediaAsset>>
  _mediaAssetsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.mediaAssets,
    aliasName: 'class_records__id__media_assets__class_id',
  );

  $$MediaAssetsTableProcessedTableManager get mediaAssetsRefs {
    final manager = $$MediaAssetsTableTableManager(
      $_db,
      $_db.mediaAssets,
    ).filter((f) => f.classId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_mediaAssetsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ClassRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $ClassRecordsTable> {
  $$ClassRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get styleId => $composableBuilder(
    column: $table.styleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get teacherId => $composableBuilder(
    column: $table.teacherId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get studioId => $composableBuilder(
    column: $table.studioId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get styleName => $composableBuilder(
    column: $table.styleName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get teacherName => $composableBuilder(
    column: $table.teacherName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get studioName => $composableBuilder(
    column: $table.studioName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sessionCount => $composableBuilder(
    column: $table.sessionCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minutesEach => $composableBuilder(
    column: $table.minutesEach,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> mediaAssetsRefs(
    Expression<bool> Function($$MediaAssetsTableFilterComposer f) f,
  ) {
    final $$MediaAssetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mediaAssets,
      getReferencedColumn: (t) => t.classId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaAssetsTableFilterComposer(
            $db: $db,
            $table: $db.mediaAssets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ClassRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $ClassRecordsTable> {
  $$ClassRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get styleId => $composableBuilder(
    column: $table.styleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get teacherId => $composableBuilder(
    column: $table.teacherId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get studioId => $composableBuilder(
    column: $table.studioId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get styleName => $composableBuilder(
    column: $table.styleName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get teacherName => $composableBuilder(
    column: $table.teacherName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get studioName => $composableBuilder(
    column: $table.studioName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sessionCount => $composableBuilder(
    column: $table.sessionCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minutesEach => $composableBuilder(
    column: $table.minutesEach,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ClassRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClassRecordsTable> {
  $$ClassRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get styleId =>
      $composableBuilder(column: $table.styleId, builder: (column) => column);

  GeneratedColumn<String> get teacherId =>
      $composableBuilder(column: $table.teacherId, builder: (column) => column);

  GeneratedColumn<String> get studioId =>
      $composableBuilder(column: $table.studioId, builder: (column) => column);

  GeneratedColumn<String> get styleName =>
      $composableBuilder(column: $table.styleName, builder: (column) => column);

  GeneratedColumn<String> get teacherName => $composableBuilder(
    column: $table.teacherName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get studioName => $composableBuilder(
    column: $table.studioName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sessionCount => $composableBuilder(
    column: $table.sessionCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get minutesEach => $composableBuilder(
    column: $table.minutesEach,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> mediaAssetsRefs<T extends Object>(
    Expression<T> Function($$MediaAssetsTableAnnotationComposer a) f,
  ) {
    final $$MediaAssetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mediaAssets,
      getReferencedColumn: (t) => t.classId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaAssetsTableAnnotationComposer(
            $db: $db,
            $table: $db.mediaAssets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ClassRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ClassRecordsTable,
          ClassRecord,
          $$ClassRecordsTableFilterComposer,
          $$ClassRecordsTableOrderingComposer,
          $$ClassRecordsTableAnnotationComposer,
          $$ClassRecordsTableCreateCompanionBuilder,
          $$ClassRecordsTableUpdateCompanionBuilder,
          (ClassRecord, $$ClassRecordsTableReferences),
          ClassRecord,
          PrefetchHooks Function({bool mediaAssetsRefs})
        > {
  $$ClassRecordsTableTableManager(_$AppDatabase db, $ClassRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClassRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClassRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClassRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<String?> styleId = const Value.absent(),
                Value<String?> teacherId = const Value.absent(),
                Value<String?> studioId = const Value.absent(),
                Value<String?> styleName = const Value.absent(),
                Value<String?> teacherName = const Value.absent(),
                Value<String?> studioName = const Value.absent(),
                Value<int> sessionCount = const Value.absent(),
                Value<int> minutesEach = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ClassRecordsCompanion(
                id: id,
                date: date,
                styleId: styleId,
                teacherId: teacherId,
                studioId: studioId,
                styleName: styleName,
                teacherName: teacherName,
                studioName: studioName,
                sessionCount: sessionCount,
                minutesEach: minutesEach,
                note: note,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String date,
                Value<String?> styleId = const Value.absent(),
                Value<String?> teacherId = const Value.absent(),
                Value<String?> studioId = const Value.absent(),
                Value<String?> styleName = const Value.absent(),
                Value<String?> teacherName = const Value.absent(),
                Value<String?> studioName = const Value.absent(),
                Value<int> sessionCount = const Value.absent(),
                Value<int> minutesEach = const Value.absent(),
                Value<String?> note = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ClassRecordsCompanion.insert(
                id: id,
                date: date,
                styleId: styleId,
                teacherId: teacherId,
                studioId: studioId,
                styleName: styleName,
                teacherName: teacherName,
                studioName: studioName,
                sessionCount: sessionCount,
                minutesEach: minutesEach,
                note: note,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ClassRecordsTable, ClassRecord>(table),
                  $$ClassRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({mediaAssetsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (mediaAssetsRefs) db.mediaAssets],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (mediaAssetsRefs)
                    await $_getPrefetchedData<
                      ClassRecord,
                      $ClassRecordsTable,
                      MediaAsset
                    >(
                      currentTable: table,
                      referencedTable: $$ClassRecordsTableReferences
                          ._mediaAssetsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ClassRecordsTableReferences(
                            db,
                            table,
                            p0,
                          ).mediaAssetsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.classId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ClassRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ClassRecordsTable,
      ClassRecord,
      $$ClassRecordsTableFilterComposer,
      $$ClassRecordsTableOrderingComposer,
      $$ClassRecordsTableAnnotationComposer,
      $$ClassRecordsTableCreateCompanionBuilder,
      $$ClassRecordsTableUpdateCompanionBuilder,
      (ClassRecord, $$ClassRecordsTableReferences),
      ClassRecord,
      PrefetchHooks Function({bool mediaAssetsRefs})
    >;
typedef $$MediaAssetsTableCreateCompanionBuilder =
    MediaAssetsCompanion Function({
      required String id,
      required String classId,
      required String type,
      required String fileName,
      Value<String?> thumbName,
      Value<int?> durationSec,
      Value<int> sizeBytes,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$MediaAssetsTableUpdateCompanionBuilder =
    MediaAssetsCompanion Function({
      Value<String> id,
      Value<String> classId,
      Value<String> type,
      Value<String> fileName,
      Value<String?> thumbName,
      Value<int?> durationSec,
      Value<int> sizeBytes,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$MediaAssetsTableReferences
    extends BaseReferences<_$AppDatabase, $MediaAssetsTable, MediaAsset> {
  $$MediaAssetsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ClassRecordsTable _classIdTable(_$AppDatabase db) =>
      db.classRecords.createAlias('media_assets__class_id__class_records__id');

  $$ClassRecordsTableProcessedTableManager get classId {
    final $_column = $_itemColumn<String>('class_id')!;

    final manager = $$ClassRecordsTableTableManager(
      $_db,
      $_db.classRecords,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_classIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MediaAssetsTableFilterComposer
    extends Composer<_$AppDatabase, $MediaAssetsTable> {
  $$MediaAssetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbName => $composableBuilder(
    column: $table.thumbName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ClassRecordsTableFilterComposer get classId {
    final $$ClassRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.classId,
      referencedTable: $db.classRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClassRecordsTableFilterComposer(
            $db: $db,
            $table: $db.classRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MediaAssetsTableOrderingComposer
    extends Composer<_$AppDatabase, $MediaAssetsTable> {
  $$MediaAssetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbName => $composableBuilder(
    column: $table.thumbName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ClassRecordsTableOrderingComposer get classId {
    final $$ClassRecordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.classId,
      referencedTable: $db.classRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClassRecordsTableOrderingComposer(
            $db: $db,
            $table: $db.classRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MediaAssetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MediaAssetsTable> {
  $$MediaAssetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get thumbName =>
      $composableBuilder(column: $table.thumbName, builder: (column) => column);

  GeneratedColumn<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ClassRecordsTableAnnotationComposer get classId {
    final $$ClassRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.classId,
      referencedTable: $db.classRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClassRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.classRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MediaAssetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MediaAssetsTable,
          MediaAsset,
          $$MediaAssetsTableFilterComposer,
          $$MediaAssetsTableOrderingComposer,
          $$MediaAssetsTableAnnotationComposer,
          $$MediaAssetsTableCreateCompanionBuilder,
          $$MediaAssetsTableUpdateCompanionBuilder,
          (MediaAsset, $$MediaAssetsTableReferences),
          MediaAsset,
          PrefetchHooks Function({bool classId})
        > {
  $$MediaAssetsTableTableManager(_$AppDatabase db, $MediaAssetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaAssetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaAssetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaAssetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> classId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<String?> thumbName = const Value.absent(),
                Value<int?> durationSec = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MediaAssetsCompanion(
                id: id,
                classId: classId,
                type: type,
                fileName: fileName,
                thumbName: thumbName,
                durationSec: durationSec,
                sizeBytes: sizeBytes,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String classId,
                required String type,
                required String fileName,
                Value<String?> thumbName = const Value.absent(),
                Value<int?> durationSec = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => MediaAssetsCompanion.insert(
                id: id,
                classId: classId,
                type: type,
                fileName: fileName,
                thumbName: thumbName,
                durationSec: durationSec,
                sizeBytes: sizeBytes,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MediaAssetsTable, MediaAsset>(table),
                  $$MediaAssetsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({classId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (classId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.classId,
                        referencedTable: $$MediaAssetsTableReferences
                            ._classIdTable(db),
                        referencedColumn: $$MediaAssetsTableReferences
                            ._classIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MediaAssetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MediaAssetsTable,
      MediaAsset,
      $$MediaAssetsTableFilterComposer,
      $$MediaAssetsTableOrderingComposer,
      $$MediaAssetsTableAnnotationComposer,
      $$MediaAssetsTableCreateCompanionBuilder,
      $$MediaAssetsTableUpdateCompanionBuilder,
      (MediaAsset, $$MediaAssetsTableReferences),
      MediaAsset,
      PrefetchHooks Function({bool classId})
    >;
typedef $$TaxonomyTableCreateCompanionBuilder = TaxonomyCompanion Function({
  required String id,
  required String kind,
  required String name,
  Value<bool> isBuiltin,
  Value<int> sortOrder,
  Value<DateTime?> lastUsedAt,
  Value<bool> isActive,
  Value<int> rowid,
});
typedef $$TaxonomyTableUpdateCompanionBuilder = TaxonomyCompanion Function({
  Value<String> id,
  Value<String> kind,
  Value<String> name,
  Value<bool> isBuiltin,
  Value<int> sortOrder,
  Value<DateTime?> lastUsedAt,
  Value<bool> isActive,
  Value<int> rowid,
});

class $$TaxonomyTableFilterComposer
    extends Composer<_$AppDatabase, $TaxonomyTable> {
  $$TaxonomyTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isBuiltin => $composableBuilder(
    column: $table.isBuiltin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TaxonomyTableOrderingComposer
    extends Composer<_$AppDatabase, $TaxonomyTable> {
  $$TaxonomyTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isBuiltin => $composableBuilder(
    column: $table.isBuiltin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TaxonomyTableAnnotationComposer
    extends Composer<_$AppDatabase, $TaxonomyTable> {
  $$TaxonomyTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isBuiltin =>
      $composableBuilder(column: $table.isBuiltin, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);
}

class $$TaxonomyTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TaxonomyTable,
          TaxonomyItem,
          $$TaxonomyTableFilterComposer,
          $$TaxonomyTableOrderingComposer,
          $$TaxonomyTableAnnotationComposer,
          $$TaxonomyTableCreateCompanionBuilder,
          $$TaxonomyTableUpdateCompanionBuilder,
          (
            TaxonomyItem,
            BaseReferences<_$AppDatabase, $TaxonomyTable, TaxonomyItem>,
          ),
          TaxonomyItem,
          PrefetchHooks Function()
        > {
  $$TaxonomyTableTableManager(_$AppDatabase db, $TaxonomyTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaxonomyTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaxonomyTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaxonomyTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> isBuiltin = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime?> lastUsedAt = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaxonomyCompanion(
                id: id,
                kind: kind,
                name: name,
                isBuiltin: isBuiltin,
                sortOrder: sortOrder,
                lastUsedAt: lastUsedAt,
                isActive: isActive,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String kind,
                required String name,
                Value<bool> isBuiltin = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime?> lastUsedAt = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaxonomyCompanion.insert(
                id: id,
                kind: kind,
                name: name,
                isBuiltin: isBuiltin,
                sortOrder: sortOrder,
                lastUsedAt: lastUsedAt,
                isActive: isActive,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TaxonomyTable, TaxonomyItem>(table),
                  BaseReferences<_$AppDatabase, $TaxonomyTable, TaxonomyItem>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TaxonomyTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TaxonomyTable,
      TaxonomyItem,
      $$TaxonomyTableFilterComposer,
      $$TaxonomyTableOrderingComposer,
      $$TaxonomyTableAnnotationComposer,
      $$TaxonomyTableCreateCompanionBuilder,
      $$TaxonomyTableUpdateCompanionBuilder,
      (
        TaxonomyItem,
        BaseReferences<_$AppDatabase, $TaxonomyTable, TaxonomyItem>,
      ),
      TaxonomyItem,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ClassRecordsTableTableManager get classRecords =>
      $$ClassRecordsTableTableManager(_db, _db.classRecords);
  $$MediaAssetsTableTableManager get mediaAssets =>
      $$MediaAssetsTableTableManager(_db, _db.mediaAssets);
  $$TaxonomyTableTableManager get taxonomy =>
      $$TaxonomyTableTableManager(_db, _db.taxonomy);
}
