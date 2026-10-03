import 'dart:io';
import 'package:flutter/material.dart';
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
import 'services/saf_archive.dart';
import 'services/thumb_service.dart';
import 'theme.dart';
import 'ui/home_shell.dart';
import 'ui/record_form_page.dart';
import 'ui/records_page.dart';
import 'ui/stats_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  final repo = AppRepository(
    db,
    store,
    TaxonomyRepo(db),
    thumbMaker: Platform.isAndroid ? deviceThumbMaker(store) : null,
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

  @override
  void initState() {
    super.initState();
    _repo = widget.repo;
    _store = widget.store;
    _hasSaf = widget.hasSaf;
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOnboard());
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
          locale: const Locale('zh'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh')],
          theme: AppTheme.light(t.accentPreset),
          home: HomeShell(
            pages: const [StatsPage(), RecordsPage()],
            onFabPressed: () {
              _navigatorKey.currentState?.push(
                MaterialPageRoute(builder: (_) => const RecordFormPage()),
              ).then((_) => ReloadBus.instance.bump());
              // 保存/取消都可能改变数据；回来后让两个页面自行刷新
            },
          ),
        ),
      ),
    );
  }
}
