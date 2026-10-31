// F1（2026-10-31 任务书）回归测试：选片页连点双 pop 竞态。
// 根因：_pick 的 AbsPathCache.resolve（SAF 拷贝，数百 ms~秒级）await 窗口内
// 无防重入守卫，窗口内连点两个视频 → 两次 pop → Bad state: No element ＋
// 上层 push 撞 _debugLocked。守卫后：连点只 pop 一次。
// 测试要点：resolver 用假时钟 delay 200ms 拉长 resolve 窗口——真实设备上
// SAF 拷贝就是数百 ms；若解析即时完成（microtask），第一次 pop 会在第二次
// tap 落点前启动（pop 中的路由脱离 hit test），测试就测不到竞态了。
// 说明：style_sheet/text_sheet 的同款守卫以状态位落地（任务书不强制
// 单独 widget 测试），本页测试覆盖该守卫模式的语义（含失败复位路径）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wuji/data/app_repository.dart';
import 'package:wuji/data/db.dart';
import 'package:wuji/editing/media_source_picker.dart';
import 'package:wuji/services/abs_path_cache.dart';
import 'package:wuji/services/archive_fs.dart' show MediaPathResolver;
import 'package:wuji/ui/record_media_picker_page.dart';

/// 解析到已存在的临时文件，带 200ms 假时钟延迟（驱动 _pick 成功分支；
/// 任务书指定先例 test/record_form_test.dart 的 _FakeResolver 模式）。
class _SlowResolver implements MediaPathResolver {
  _SlowResolver(this.path);
  final String path;
  @override
  Future<String?> toAbsolutePath(String rel, {bool paced = false}) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return path;
  }
}

/// 首次延迟返回 null（模拟文件丢失），之后返回真实路径——覆盖失败复位。
class _FlakyResolver implements MediaPathResolver {
  _FlakyResolver(this.okPath);
  final String okPath;
  int calls = 0;
  @override
  Future<String?> toAbsolutePath(String rel, {bool paced = false}) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return calls == 1 ? null : okPath;
  }
}

/// 无 IO 的假仓库：选片页只读 allRecords/mediaByClass。
/// db 用内存库仅为满足 ClassSaver 接口，测试不触库（FakeAsync 区无重 IO）。
class _FakeSaver implements ClassSaver {
  _FakeSaver(this.records, this.media);
  final List<ClassRecord> records;
  final List<MediaAsset> media;

  @override
  final db = appDatabaseForTest();

  void dispose() => db.close();

  @override
  Future<List<ClassRecord>> allRecords() async => records;

  @override
  Future<Map<String, List<MediaAsset>>> mediaByClass() async =>
      {for (final r in records) r.id: media};

  @override
  Future<void> saveDraft(ClassDraft d) async {}

  @override
  Future<List<MediaAsset>> mediaOf(String classId) async => media;

  @override
  Future<void> deleteRecord(String id) async {}

  @override
  Future<bool> needsSpaceWarningFor(List<MediaInput> inputs) async => false;
}

class _PopObserver extends NavigatorObserver {
  int didPopCount = 0;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    didPopCount++;
  }
}

void main() {
  // 同步建临时文件：FakeAsync 区内真实异步文件 IO 会非确定性挂死
  // （record_form_test 台账 T8 裁定），setUp 里只用同步 IO。
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wuji-picker-test');
    File('${tmp.path}/v.mp4').writeAsStringSync('x');
  });
  tearDown(() {
    tmp.deleteSync(recursive: true);
    AbsPathCache.clearCache();
  });

  ClassRecord record() => ClassRecord(
        id: 'r1',
        date: '2026-10-01',
        styleName: '爵士',
        teacherName: '小鹿',
        sessionCount: 1,
        minutesEach: 60,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  MediaAsset asset(String id) => MediaAsset(
        id: id,
        classId: 'r1',
        type: 'video',
        fileName: 'media/2026-10/$id.mp4',
        sizeBytes: 1,
        createdAt: DateTime.now(),
      );

  Future<Widget> host({
    required ClassSaver saver,
    required MediaPathResolver resolver,
    required NavigatorObserver observer,
    required ValueChanged<PickedSource?> onPicked,
  }) async =>
      MultiProvider(providers: [
        Provider<ClassSaver>.value(value: saver),
        Provider<MediaPathResolver>.value(value: resolver),
      ], child: MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              onPicked(await Navigator.push<PickedSource>(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const RecordMediaPickerPage())));
            },
            child: const Text('open'),
          ),
        ),
      ));

  testWidgets('F1：resolve 窗口内连点两个视频 → 只 pop 一次、无异常、结果回传',
      (tester) async {
    final saver = _FakeSaver([record()], [asset('m1'), asset('m2')]);
    addTearDown(saver.dispose);
    final observer = _PopObserver();
    PickedSource? picked;
    await tester.pumpWidget(await host(
      saver: saver,
      resolver: _SlowResolver('${tmp.path}/v.mp4'),
      observer: observer,
      onPicked: (p) => picked = p,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(); // 进页＋_load 完成，列表条目可见
    expect(find.byType(ListTile), findsNWidgets(2));

    // 连点两个条目：两次 tap 之间不 pump——第一次 _pick 还挂在 200ms
    // resolve 延迟上（模拟真机 SAF 拷贝窗口），第二次点击应被守卫拦下
    await tester.tap(find.byType(ListTile).at(0));
    await tester.tap(find.byType(ListTile).at(1));
    await tester.pumpAndSettle(); // 推进假时钟：resolve 完成 → pop＋转场收尾

    expect(tester.takeException(), isNull, reason: '连点不得抛未捕获异常');
    expect(observer.didPopCount, 1, reason: '连点任意多项只允许一次 pop');
    expect(picked, isNotNull, reason: '上层（直拍/mosaic 入口）正常拿到所选视频');
    expect(picked!.path, '${tmp.path}/v.mp4');
  });

  testWidgets('F1：解析失败复位守卫——SnackBar 后改点别的视频仍可成功',
      (tester) async {
    final saver = _FakeSaver([record()], [asset('m1'), asset('m2')]);
    addTearDown(saver.dispose);
    final observer = _PopObserver();
    PickedSource? picked;
    await tester.pumpWidget(await host(
      saver: saver,
      resolver: _FlakyResolver('${tmp.path}/v.mp4'),
      observer: observer,
      onPicked: (p) => picked = p,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // 第一次点击：解析失败 → SnackBar，不 pop、守卫复位
    await tester.tap(find.byType(ListTile).at(0));
    await tester.pumpAndSettle();
    expect(find.text('视频文件已丢失，可从备份导入恢复'), findsOneWidget);
    expect(observer.didPopCount, 0);
    // 第二次点击：复位后守卫放行 → 成功 pop
    await tester.tap(find.byType(ListTile).at(1));
    await tester.pumpAndSettle();
    expect(observer.didPopCount, 1);
    expect(picked, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
