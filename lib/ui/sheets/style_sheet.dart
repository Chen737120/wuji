import 'package:flutter/material.dart';
import '../../data/db.dart' show TaxonomyItem;
import '../../data/taxonomy_repo.dart';
import '../../models/models.dart';
import '../../theme.dart';

/// 舞种选择底部弹层（规格 §3.4）：预设网格＋「自定义」虚线格。
Future<TaxonomyItem?> showStyleSheet(BuildContext context, TaxonomyRepo repo) {
  return showModalBottomSheet<TaxonomyItem>(
    context: context,
    backgroundColor: AppColors.bg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _StyleSheet(repo: repo),
  );
}

class _StyleSheet extends StatefulWidget {
  const _StyleSheet({required this.repo});
  final TaxonomyRepo repo;

  @override
  State<_StyleSheet> createState() => _StyleSheetState();
}

class _StyleSheetState extends State<_StyleSheet> {
  late Future<List<TaxonomyItem>> _styles;

  @override
  void initState() {
    super.initState();
    _styles = widget.repo.ensureBuiltins().then(
        (_) => widget.repo.byKind(TaxonomyKind.style));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('选择舞种',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.faint),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            FutureBuilder<List<TaxonomyItem>>(
              future: _styles,
              builder: (context, snap) {
                final styles = snap.data ?? const <TaxonomyItem>[];
                return Flexible(
                  child: GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    childAspectRatio: 2.2,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    children: [
                      for (final s in styles)
                        _tile(s.name, selected: false, onTap: () => Navigator.pop(context, s)),
                      _customTile(),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(String label,
      {required bool selected, required VoidCallback onTap}) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? accent : AppColors.hairline,
              width: selected ? 1.5 : 1),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: selected ? accent : AppColors.ink,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }

  Widget _customTile() {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: () async {
        final name = await _askCustomName(context);
        if (name == null || name.trim().isEmpty) return;
        final item = await widget.repo.touchByName(TaxonomyKind.style, name);
        if (mounted) Navigator.pop(context, item);
      },
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: .4), width: 1.2),
        ),
        child: Text('自定义',
            style: TextStyle(fontSize: 12, color: accent)),
      ),
    );
  }
}

Future<String?> _askCustomName(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('自定义舞种', style: TextStyle(fontSize: 16)),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '输入舞种名称'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定')),
      ],
    ),
  );
}
