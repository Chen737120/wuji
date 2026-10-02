import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/data/db.dart';
import 'package:wuji/services/export_naming.dart';

ClassRecord rec(String date, {String? style, String? teacher, String? studio,
    String? note, int sessions = 1, int minutes = 90, String id = 'r'}) {
  return ClassRecord(
    id: id,
    date: date,
    styleName: style,
    teacherName: teacher,
    studioName: studio,
    sessionCount: sessions,
    minutesEach: minutes,
    note: note,
    createdAt: DateTime.parse(date),
    updatedAt: DateTime.parse(date),
  );
}

void main() {
  test('folderBaseName joins non-empty segments', () {
    expect(
        folderBaseName(rec('2026-09-30',
            style: '爵士', teacher: '小鹿', studio: '光影舞室')),
        '2026-09-30_爵士_小鹿_光影舞室');
    expect(folderBaseName(rec('2026-09-19', style: 'Hiphop')),
        '2026-09-19_Hiphop');
    expect(folderBaseName(rec('2026-09-19')), '2026-09-19');
  });

  test('sanitizeSegment replaces illegal chars', () {
    expect(sanitizeSegment(r'a/b\c:d*e?f"g<h>i|j'), 'a-b-c-d-e-f-g-h-i-j');
  });

  test('assignFolderNames appends sequence for duplicates', () {
    final a = rec('2026-09-30', style: '爵士', id: 'a');
    final b = rec('2026-09-30', style: '爵士', id: 'b');
    final c = rec('2026-09-24', style: '韩舞', id: 'c');
    final names = assignFolderNames([a, b, c]);
    expect(names['a'], '2026-09-30_爵士');
    expect(names['b'], '2026-09-30_爵士_2');
    expect(names['c'], '2026-09-24_韩舞');
  });

  test('feelingsTxt with note', () {
    final txt = feelingsTxt(rec('2026-09-30',
        style: '爵士',
        teacher: '小鹿',
        sessions: 2,
        minutes: 90,
        note: '发现一个宝藏老师 ✨\n正文第二行'));
    expect(txt.startsWith('发现一个宝藏老师 ✨\n'), isTrue);
    expect(txt.contains('日期：2026-09-30'), isTrue);
    expect(txt.contains('时长：2节 × 90分钟（共180分钟）'), isTrue);
    expect(txt.contains('舞种：爵士'), isTrue);
    expect(txt.contains('老师：小鹿'), isTrue);
    expect(txt.contains('舞室：'), isFalse); // 未填整行省略
    expect(txt.contains('正文第二行'), isTrue);
  });

  test('feelingsTxt without note marks it explicitly', () {
    final txt = feelingsTxt(rec('2026-09-19', style: 'Hiphop'));
    expect(txt.startsWith('本课未写感受'), isTrue);
    expect(txt.contains('（本课未写感受）'), isTrue);
    expect(txt.contains('舞种：Hiphop'), isTrue);
  });

  test('buildWorkbook returns xlsx with header + one row per record', () {
    final records = [
      rec('2026-09-30', style: '爵士', teacher: '小鹿', id: 'a', sessions: 2),
      rec('2026-09-24', style: '韩舞', id: 'b'),
    ];
    final names = assignFolderNames(records);
    final bytes = buildWorkbook(records,
        {'a': 3, 'b': 0}, names);
    expect(bytes, isNotEmpty);
    final wb = decodeWorkbook(bytes);
    expect(wb.header, contains('文件夹名'));
    expect(wb.rows, hasLength(2));
    expect(wb.rows[0]['日期'], '2026-09-30');
    expect(wb.rows[0]['节数'], '2');
    expect(wb.rows[0]['附件数'], '3');
  });
}
