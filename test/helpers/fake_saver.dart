import 'package:wuji/data/app_repository.dart';
import 'package:wuji/data/db.dart';

/// 无 IO 的 ClassSaver 假实现（widget 测试用，见台账 T8 裁定）。
class FakeSaver implements ClassSaver {
  FakeSaver({this.records = const [], this.media = const []});

  @override
  AppDatabase get db => throw UnimplementedError('fake saver has no db');

  List<ClassRecord> records;
  List<MediaAsset> media;

  @override
  Future<void> saveDraft(ClassDraft d) =>
      throw UnimplementedError('not needed in these tests');

  @override
  Future<void> deleteRecord(String id) async {}

  @override
  Future<bool> needsSpaceWarningFor(inputs) async => false;

  @override
  Future<List<ClassRecord>> allRecords() async => records;

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
}
