import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wuji/data/app_repository.dart';
import 'package:wuji/data/db.dart';
import 'package:wuji/editing/media_source_picker.dart';
import 'package:wuji/services/archive_fs.dart' show MediaPathResolver;

/// 假解析器：把存档相对路径映射成本用例约定的绝对路径（P1-13 后
/// 无 resolver 时 resolve 返回 null，选中路径必须由 resolver 给出）。
class _FakeResolver implements MediaPathResolver {
  @override
  Future<String?> toAbsolutePath(String rel, {bool paced = false}) async =>
      '/abs/${rel.split('/').last}';
}

ClassRecord rec(String id, String date) => ClassRecord(
    id: id, date: date, sessionCount: 1, minutesEach: 90,
    createdAt: DateTime.parse(date), updatedAt: DateTime.parse(date));

MediaAsset video(String id, String classId, String fileName) => MediaAsset(
    id: id, classId: classId, type: 'video', fileName: fileName, sizeBytes: 100,
    createdAt: DateTime(2026, 9, 30));

class FakePickerRepo implements ClassSaver {
  FakePickerRepo(this.records, this.media);
  final List<ClassRecord> records;
  final List<MediaAsset> media;

  @override
  AppDatabase get db => throw UnimplementedError();
  @override
  Future<List<ClassRecord>> allRecords() async => records;
  @override
  Future<void> deleteRecord(String id) async {}
  @override
  Future<List<MediaAsset>> mediaOf(String classId) async =>
      media.where((m) => m.classId == classId).toList();
  @override
  Future<Map<String, List<MediaAsset>>> mediaByClass() async {
    final byClass = <String, List<MediaAsset>>{};
    for (final m in media) {
      byClass.putIfAbsent(m.classId, () => []).add(m);
    }
    return byClass;
  }

  @override
  Future<void> saveDraft(ClassDraft d) async {}

  @override
  Future<bool> needsSpaceWarningFor(inputs) async => false;
}

void main() {
  test('groupVideosByClass：只含视频、按日期倒序分组、无视频课不出现', () {
    final records = [
      rec('a', '2026-09-30'),
      rec('b', '2026-09-24'),
      rec('c', '2026-08-21'),
    ];
    final media = [
      video('m1', 'a', 'media/2026-09/v1.mp4'),
      MediaAsset(
          id: 'm2',
          classId: 'a',
          type: 'image',
          fileName: 'media/2026-09/i1.jpg',
          sizeBytes: 50,
          createdAt: DateTime(2026, 9, 30)),
      video('m3', 'b', 'media/2026-09/v2.mp4'),
      MediaAsset(
          id: 'm4',
          classId: 'c',
          type: 'image',
          fileName: 'media/2026-08/i2.jpg',
          sizeBytes: 50,
          createdAt: DateTime(2026, 8, 21)),
    ];
    final groups = groupVideosByClass(records, media);
    expect(groups.map((g) => g.classId).toList(), ['a', 'b']);
    expect(groups[0].videos, hasLength(1));
    expect(groups[0].videos.first.id, 'm1');
    expect(groups[0].date, '2026-09-30');
  });

  testWidgets('弹层两入口：相册 / 舞记课堂', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: Builder(
                    builder: (context) => TextButton(
                        onPressed: () => showVideoSourceSheet(
                            context,
                            albumPicker: (_, _) async =>
                                PickedSource(path: '/tmp/x.mp4', name: 'x'),
                            archivePicker: (_) async => null),
                        child: const Text('open')))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('从相册选'), findsOneWidget);
    expect(find.text('从舞记课堂选'), findsOneWidget);
    await tester.tap(find.text('从舞记课堂选'));
    await tester.pumpAndSettle();
    // archivePicker 返回 null → 弹层不产生结果，页面回到表单
    expect(find.text('从相册选'), findsNothing); // 弹层已收
  });

  testWidgets('课堂选择页：按课分组渲染视频条目，点击返回 PickedSource', (tester) async {
    final repo = FakePickerRepo([rec('a', '2026-09-30')], [
      video('m1', 'a', 'media/2026-09/v1.mp4'),
    ]);
    PickedSource? picked;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ClassSaver>.value(value: repo),
          Provider<MediaPathResolver>.value(value: _FakeResolver()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    picked = await showRecordMediaPicker(context);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('2026年9月30日'), findsOneWidget); // 分组头
    expect(find.byType(ListTile), findsOneWidget);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.classId, 'a');
    expect(picked!.fromArchive, isTrue);
    expect(picked!.path, '/abs/v1.mp4'); // 绝对路径由 resolver 提供
  });
}

