import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/app_repository.dart' show ClassSaver;
import '../theme.dart';
import 'export_preview_page.dart';
import 'import_page.dart';

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
class MyPage extends StatelessWidget {
  const MyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final saver = context.read<ClassSaver>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: FutureBuilder<_Usage>(
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
                      : '${usage.records} 节课 · ${usage.media} 个附件 · ${usage.bytesText}',
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
                      onTap: () => _todo(context, '存档位置')),
                ]),
                _section('管理', [
                  _navRow(context, '舞种管理', onTap: () => _todo(context, '舞种管理')),
                  _navRow(context, '老师管理', onTap: () => _todo(context, '老师管理')),
                  _navRow(context, '舞室管理', onTap: () => _todo(context, '舞室管理')),
                ]),
                _section('外观', [
                  const _AccentPicker(),
                ]),
                _section('其他', [
                  _navRow(context, '关于舞记',
                      sub: null, onTap: () => _todo(context, '关于')),
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

  void _todo(BuildContext context, String what) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('「$what」在后续步骤接入')));
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
