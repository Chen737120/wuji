import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/app_repository.dart' show ClassSaver;
import '../reload_bus.dart';
import '../theme.dart';
import 'export_preview_page.dart';
import 'import_page.dart';
import 'manage_pages.dart';
import '../app_services.dart';
import '../models/models.dart';

/// 字节人性化：B / KB / MB / GB（带「约」前缀，非最小单位）。
String humanBytes(num bytes) {
  if (bytes < 1024) return '${bytes.round()} B';
  final kb = bytes / 1024;
  if (kb < 1024) return '约 ${kb.round()} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '约 ${mb.round()} MB';
  return '约 ${(mb / 1024).toStringAsFixed(1)} GB';
}

/// 「我的」页（规格 §3.6）：用量、导出/导入、存档位置、管理、外观、关于。
class MyPage extends StatefulWidget {
  const MyPage({super.key});

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  int _rev = 0; // ReloadBus 变更后重建用量 FutureBuilder

  @override
  void initState() {
    super.initState();
    ReloadBus.instance.addListener(_bump);
  }

  @override
  void dispose() {
    ReloadBus.instance.removeListener(_bump);
    super.dispose();
  }

  void _bump() {
    if (mounted) setState(() => _rev++);
  }

  @override
  Widget build(BuildContext context) {
    final saver = context.read<ClassSaver>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: FutureBuilder<_Usage>(
          key: ValueKey(_rev),
          future: _usage(saver),
          builder: (context, snap) {
            final usage = snap.data;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                const Text('我的',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 3)),
                const SizedBox(height: 8),
                Text(
                  usage == null
                      ? '统计中…'
                      : '${usage.records} 节课 · ${usage.media} 个附件 · ${usage.bytesText}（视频占大头）',
                  style: TextStyle(fontSize: 11, color: AppColors.secondary),
                ),
                const SizedBox(height: 6),
                _section('导出', [
                  _navRow(context, '导出全部记录',
                      sub: '一键打包 zip：视频按「日期_舞种_老师」建文件夹\n＋ 每课感受 txt ＋ Excel 总表',
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const ExportPreviewPage()))),
                  _navRow(context, '按时间段导出',
                      sub: '选起止日期，先预览再导出，格式相同',
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const ExportPreviewPage()))),
                ]),
                _section('备份', [
                  _navRow(context, '导入备份',
                      sub: '选择导出包或存档文件夹，恢复/补回课程',
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const ImportPage()))),
                  _navRow(context, '存档位置',
                      sub: '查看或更换存档文件夹（卸载不清空）',
                      onTap: () async {
                        ArchiveSwitcher? switcher;
                        try {
                          switcher = context.read<ArchiveSwitcher>();
                        } catch (_) {}
                        if (switcher == null) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('当前版本暂不支持切换，请重装后选择存档文件夹')));
                          return;
                        }
                        await switcher.run();
                      }),
                ]),
                _section('管理', [
                  _navRow(context, '老师管理', onTap: () => _openManage(context, TaxonomyKind.teacher, '老师管理')),
                  _navRow(context, '舞室管理', onTap: () => _openManage(context, TaxonomyKind.studio, '舞室管理')),
                ]),
                _section('外观', [
                  const _AccentPicker(),
                ]),
                _section('其他', [
                  _navRow(context, '关于舞记',
                      sub: null, onTap: () => showDialog(context: context, builder: (ctx) => AlertDialog(
                        backgroundColor: Colors.white,
                        title: const Text('舞记', style: TextStyle(fontSize: 16)),
                        content: const Text(
                            'v1.5.22\n\n'
                            '一个纯个人的舞蹈课记录本：数据全部保存在你的手机上，'
                            '没有账号，没有云端。\n\n'
                            '· 记录：课堂视频/图片 + 感受 + 日期舞种老师舞室，'
                            '日历封面总览每一天\n'
                            '· 统计：节数/时长/天数、跳舞趋势、舞种与老师舞室分布、'
                            '跳舞热力图\n'
                            '· 剪辑：舞蹈直拍（圈选区域+关键帧跟框）、同屏对比'
                            '（时间/画面微调）\n'
                            '· 导出：整包/按时间段 zip（视频+感受+总表），'
                            '成片存相册 Movies/wuji/\n'
                            '· 备份：换手机一键恢复\n\n'
                            '卸载 App 存档不丢；导出的 zip 就是异地备份。\n\n'
                            'create by：AI × 一棵卷心菜',
                            style: TextStyle(fontSize: 13, height: 1.7)),
                        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('好的'))],
                      ))),
                ]),
                const SizedBox(height: 10),
                Center(
                  child: Text('数据只存在这台手机上 · 导出即备份',
                      style: TextStyle(fontSize: 9, color: AppColors.faint)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<_Usage> _usage(ClassSaver saver) async {
    final records = await saver.allRecords();
    var mediaCount = 0;
    var bytes = 0;
    for (final r in records) {
      final m = await saver.mediaOf(r.id);
      mediaCount += m.length;
      bytes += m.fold<int>(0, (a, x) => a + x.sizeBytes);
    }
    return _Usage(records.length, mediaCount, humanBytes(bytes));
  }

  void _openManage(BuildContext context, TaxonomyKind kind, String title) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => ManagePage(kind: kind, title: title)));
  }

  Widget _section(String title, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 10, letterSpacing: 2, color: AppColors.secondary)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 14), color: const Color(0xFFF4F4F0)),
                  rows[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navRow(BuildContext context, String title,
      {String? sub, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  if (sub != null) ...[
                    const SizedBox(height: 3),
                    Text(sub,
                        style: TextStyle(fontSize: 10, color: AppColors.faint, height: 1.6)),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFC9C9C5)),
          ],
        ),
      ),
    );
  }
}

class _Usage {
  const _Usage(this.records, this.media, this.bytesText);
  final int records;
  final int media;
  final String bytesText;
}

/// 点缀色四档圆点（翠芽/抹茶/薄荷/松绿），点选即全局生效。
class _AccentPicker extends StatelessWidget {
  const _AccentPicker();

  static const _presets = AccentPreset.values;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          for (final p in _presets)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () => theme.setPreset(p),
                child: Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: p.color,
                        border: theme.accentPreset == p
                            ? Border.all(color: AppColors.ink, width: 2)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(p.label,
                        style: TextStyle(
                            fontSize: 10,
                            color: theme.accentPreset == p
                                ? AppColors.ink
                                : AppColors.faint,
                            fontWeight: theme.accentPreset == p
                                ? FontWeight.w700
                                : FontWeight.w400)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
