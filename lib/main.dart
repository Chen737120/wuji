import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/app_repository.dart';
import 'app_services.dart';
import 'data/db.dart';
import 'data/taxonomy_repo.dart';
import 'reload_bus.dart';
import 'services/archive_fs.dart';
import 'services/archive_store.dart';
import 'services/photo_bridge.dart';
import 'services/saf_archive.dart';
import 'services/startup_warmup.dart';
import 'services/temp_cleanup.dart';
import 'services/thumb_service.dart';
import 'theme.dart';
import 'ui/edit_hub_page.dart';
import 'ui/home_shell.dart';
import 'ui/fancam/fancam_page.dart';
import 'ui/compare/compare_page.dart';
import 'ui/compare/compare_pick_page.dart';
import 'editing/media_source_picker.dart';
import 'ui/fancam/trim_page.dart';
import 'ui/record_form_page.dart';
import 'ui/records_page.dart';
import 'ui/stats_page.dart';
import 'ui/widgets/app_route.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 2026-10-09 需求 #4：后台会全量预热所有缩略图（默认 100MiB/1000 张
  // 放不下百来条记录的图，会 LRU 逐出导致再滚回去又重载），按当前量级
  // 调大到 384MiB，现代手机内存足够
  PaintingBinding.instance.imageCache
    ..maximumSize = 6000
    ..maximumSizeBytes = 384 << 20;
  cleanupStaleTemp(); // 陈旧临时文件清理（fire-and-forget，不阻塞启动）
  // 全 app 锁竖屏：横屏只由播放页全屏时运行时放开（PlayerPage dispose
  // 恢复 portraitUp，与这里闭环），避免竖屏设计的列表页转横屏后布局碎裂
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final db = AppDatabase();
  final theme = ThemeController();
  await theme.load();
  final sp = await SharedPreferences.getInstance();
  final treeUri = sp.getString('archiveTreeUri');
  ArchiveStore store;
  try {
    store = ArchiveStore(await _archiveFs(treeUri));
  } catch (_) {
    // 终审 I9：存档卷不可用时回退私有目录，App 照常打开
    final docs = await getApplicationDocumentsDirectory();
    store = ArchiveStore(LocalArchiveFs('${docs.path}/wuji-archive'));
  }
  // iOS：存档目录排除 iCloud 备份——视频 GB 级会撑爆用户 iCloud，
  // 备份需求由「导出 zip」覆盖；通道未就绪时 bridge 内部静默
  if (Platform.isIOS) {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final archive =
          Directory('${docs.path}${Platform.pathSeparator}wuji-archive');
      if (!archive.existsSync()) archive.createSync(recursive: true);
      await PhotoManagerBridge.excludeFromBackup(archive.path);
    } catch (_) {}
  }
  final repo = AppRepository(
    db,
    store,
    TaxonomyRepo(db),
    thumbMaker:
        Platform.isAndroid || Platform.isIOS ? deviceThumbMaker(store) : null,
  );
  await repo.reconcileOnStartup();
  runApp(AppRoot(repo: repo, store: store, theme: theme, hasSaf: treeUri != null));
}

/// 已授权 SAF → SAF 存档；否则暂用应用私有目录（首启引导后切换）。
Future<ArchiveFs> _archiveFs(String? treeUri) async {
  if (treeUri != null && treeUri.isNotEmpty) {
    return SafArchiveFs(treeUri: treeUri);
  }
  final docs = await getApplicationDocumentsDirectory();
  return LocalArchiveFs('${docs.path}${Platform.pathSeparator}wuji-archive');
}

class AppRoot extends StatefulWidget {
  const AppRoot({
    super.key,
    required this.repo,
    required this.store,
    required this.theme,
    required this.hasSaf,
  });

  final AppRepository repo;
  final ArchiveStore store;
  final ThemeController theme;
  final bool hasSaf;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  /// FAB 等根层回调推路由必须走这个 key：本 State 的 context 在
  /// MaterialApp/Navigator 之上，Navigator.of(context) 会直接抛异常。
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late AppRepository _repo;
  late ArchiveStore _store;
  late bool _hasSaf;
  bool _onboardingShown = false;

  // 2026-10-08 需求 #5：启动加载页——boot 期间（首屏数据+封面预热，
  // 上限 3 秒）显示品牌启动页，进首页时封面已成图，不再"黑块→图"闪现
  bool _booting = true;

  @override
  void initState() {
    super.initState();
    _repo = widget.repo;
    _store = widget.store;
    _hasSaf = widget.hasSaf;
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    List<ClassRecord>? records;
    Map<String, List<MediaAsset>>? media;
    MediaPathResolver? resolver;
    try {
      final nav = _navigatorKey.currentState;
      if (nav != null && nav.mounted) {
        final navContext = nav.context;
        records = await _repo.allRecords();
        media = await _repo.mediaByClass();
        resolver =
            _store.fs is MediaPathResolver ? _store.fs as MediaPathResolver : null;
        if (!navContext.mounted) throw StateError('splash unmounted');
        // 超时不中断启动：剩余封面继续后台预热，页面用软占位色兜底
        await StartupWarmup.warmFirstScreen(
          navContext,
          records: records,
          mediaByClass: media,
          resolver: resolver,
        ).timeout(const Duration(seconds: 3));
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _booting = false);
    _maybeOnboard();
    // 2026-10-09 需求 #4：开屏结束后后台继续全量预热其余图片（不阻塞、
    // 逐张让出事件循环）——滑到过往记录/切历史月份时已是成图
    final navCtx = _navigatorKey.currentState?.context;
    if (records != null && media != null && navCtx != null && navCtx.mounted) {
      unawaited(StartupWarmup.warmAll(
        navCtx,
        records: records,
        mediaByClass: media,
        resolver: resolver,
      ));
    }
  }

  /// 存档位置切换（规格 §5.1）：重选文件夹 → 重建仓库 → 从新存档恢复。
  Future<void> _switchArchive() async {
    final uri = await pickAndEnsureWujiArchive();
    if (uri == null || !mounted) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('archiveTreeUri', uri);
    final newStore = ArchiveStore(SafArchiveFs(treeUri: uri));
    final newRepo = AppRepository(_repo.db, newStore, TaxonomyRepo(_repo.db),
        thumbMaker: deviceThumbMaker(newStore));
    await newRepo.reconcileOnStartup();
    setState(() {
      _store = newStore;
      _repo = newRepo;
      _hasSaf = true;
    });
    if (mounted) {
      final nav = _navigatorKey.currentState;
      if (nav != null) {
        ScaffoldMessenger.of(nav.context).showSnackBar(
            const SnackBar(content: Text('存档位置已更新')));
      }
    }
  }

  Future<void> _maybeOnboard() async {
    // SAF 存档引导只属于 Android（iOS 用应用内 Documents 存档，
    // 没有「选择文件夹」概念；卸载即删，靠导出 zip 做备份）
    if (!Platform.isAndroid) return;
    if (_hasSaf || _onboardingShown || !mounted) return;
    final sp = await SharedPreferences.getInstance();
    if (sp.getBool('archiveOnboardSkipped') == true) return;
    if (!mounted) return;
    _showOnboardDialog();
  }

  /// 根 State 的 context 在 MaterialApp 之上（Navigator/Theme/ScaffoldMessenger
  /// 的下游），弹窗必须取 Navigator 的 context，否则 Navigator.of 直接抛。
  void _showOnboardDialog() {
    final nav = _navigatorKey.currentState;
    if (nav == null) return;
    _onboardingShown = true;
    final accent = Theme.of(nav.context).colorScheme.primary;
    showDialog<bool>(
      context: nav.context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('选择存档文件夹',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text(
            '舞记会把课堂视频和记录保存在一个专门的文件夹里。\n\n推荐放在「下载」中的「舞记」文件夹：卸载应用后视频和感受也不会丢，重装后可一键恢复。',
            style: TextStyle(fontSize: 13, height: 1.7)),
        actions: [
          TextButton(
            onPressed: () async {
              final sp = await SharedPreferences.getInstance();
              await sp.setBool('archiveOnboardSkipped', true);
              if (ctx.mounted) Navigator.pop(ctx, false);
            },
            child: const Text('稍后再说'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              shape: const StadiumBorder(),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('使用“下载”中的舞记文件夹'),
          ),
        ],
      ),
    ).then((picked) async {
      if (picked != true) return;
      final uri = await pickAndEnsureWujiArchive();
      if (uri == null || !mounted) return;
      final sp2 = await SharedPreferences.getInstance();
      await sp2.setString('archiveTreeUri', uri);
      final newStore = ArchiveStore(SafArchiveFs(treeUri: uri));
      final newRepo = AppRepository(_repo.db, newStore,
          TaxonomyRepo(_repo.db),
          thumbMaker: deviceThumbMaker(newStore));
      await newRepo.reconcileOnStartup();
      setState(() {
        _store = newStore;
        _repo = newRepo;
        _hasSaf = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: widget.theme),
        Provider<ClassSaver>.value(value: _repo),
        Provider<AppRepository>.value(value: _repo),
        Provider<TaxonomyRepo>.value(value: TaxonomyRepo(_repo.db)),
        // 存档位置切换依赖 SAF（Android 专属）；iOS 走应用内存档，
        // my_page 在拿不到 ArchiveSwitcher 时有降级提示
        if (Platform.isAndroid)
          Provider<ArchiveSwitcher>.value(
              value: ArchiveSwitcher(_switchArchive)),
        Provider<MediaLocator>.value(value: _store),
        Provider<ArchiveStore>.value(value: _store),
        if (_store.fs is MediaPathResolver)
          Provider<MediaPathResolver>.value(
              value: _store.fs as MediaPathResolver),
      ],
      child: Consumer<ThemeController>(
        builder: (_, t, _) => MaterialApp(
          title: '舞记',
          navigatorKey: _navigatorKey,
          navigatorObservers: [RootRouteObserver()],
          locale: const Locale('zh'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh')],
          theme: AppTheme.light(t.accentPreset),
          home: _booting
              ? const _SplashPage()
              : HomeShell(
                  pages: [
                    const RecordsPage(), // 首页（默认 tab）
                    EditHubPage(
                      onFancam: () => _startFancam(),
                      onCompare: () => _startCompare(),
                    ),
                    const StatsPage(), // 统计
                  ],
                  onFabPressed: () {
                    _navigatorKey.currentState?.push(
                      MaterialPageRoute(
                          builder: (_) => RecordFormPage(
                              // 日历里选中的天直接作为新增默认日期
                              initialDate: CalendarSelection.selectedDay)),
                    ).then((_) => ReloadBus.instance.bump());
                    // 保存/取消都可能改变数据；回来后让两个页面自行刷新
                  },
                ),
        ),
      ),
    );
  }

  /// 舞蹈直拍：先选视频（相册/课堂记录）→ 修剪长度 → 进圈选框编辑器。
  Future<void> _startFancam() async {
    final nav = _navigatorKey.currentState;
    if (nav == null) return;
    final src = await showVideoSourceSheet(
      nav.context,
      albumPicker: pickSingleVideoFromAlbum,
      archivePicker: showRecordMediaPicker,
    );
    if (src == null || !mounted) return;
    final trim = await pushFancamTrim(nav.context, src);
    if (trim == null || !mounted) return;
    nav.push(AppRoute(
        builder: (_) => FancamPage(
            source: src, trimStart: trim.start, trimEnd: trim.end)));
  }

  /// 同屏对比：先进入双卡片选择页（图五原型），选定两段后进编辑。
  Future<void> _startCompare() async {
    final nav = _navigatorKey.currentState;
    if (nav == null) return;
    final picked = await nav.push<({PickedSource teacher, PickedSource mine})>(
        MaterialPageRoute(builder: (_) => const ComparePickPage()));
    if (picked == null || !mounted) return;
    nav.push(MaterialPageRoute(
        builder: (_) => ComparePage(
            teacher: picked.teacher, mine: picked.mine)));
  }
}

/// 启动加载页（2026-10-08 需求 #5，参考舞动时光）：品牌标识＋slogan，
/// 期间完成首屏数据读取与封面预解码，避免首页可见的逐格加载。
/// 2026-10-09 需求 #7：加载提示换成品牌 slogan「跟着节拍，动即是舞」，
/// 用站酷小薇体（OFL 开源）带一点设计感，风格简约。
class _SplashPage extends StatelessWidget {
  const _SplashPage();

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('舞记',
                style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 12,
                    color: AppColors.ink)),
            const SizedBox(height: 10),
            SizedBox(
              width: 84,
              height: 20,
              child: CustomPaint(painter: _WavePainter(accent)),
            ),
            const SizedBox(height: 30),
            const Text('跟着节拍，动即是舞',
                style: TextStyle(
                    fontFamily: 'ZCOOLXiaoWei',
                    fontSize: 17,
                    letterSpacing: 5,
                    color: AppColors.ink)),
          ],
        ),
      ),
    );
  }
}

/// 启动页的波浪笔触（与统计页 logo 同款笔意）。
class _WavePainter extends CustomPainter {
  _WavePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * 0.85)
      ..cubicTo(size.width * 0.25, size.height * 0.1, size.width * 0.4,
          size.height, size.width * 0.62, size.height * 0.4);
    path.cubicTo(size.width * 0.78, size.height * 0.15, size.width * 0.9,
        size.height * 0.35, size.width, size.height * 0.5);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.color != color;
}
