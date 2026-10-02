import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/db.dart' show TaxonomyItem;
import '../data/taxonomy_repo.dart';
import '../models/models.dart';
import '../reload_bus.dart';
import '../theme.dart';

/// 名单管理页（规格 §3.6）：改名、删除（停用）自定义项；历史课快照不受影响。
class ManagePage extends StatefulWidget {
  const ManagePage({super.key, required this.kind, required this.title});

  final TaxonomyKind kind;
  final String title;

  @override
  State<ManagePage> createState() => _ManagePageState();
}

class _ManagePageState extends State<ManagePage> {
  late Future<List<TaxonomyItem>> _items;

  TaxonomyRepo get _repo => context.read<TaxonomyRepo>();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _items = _repo.byKind(widget.kind, includeInactive: true);
  }

  Future<void> _rename(TaxonomyItem item) async {
    final controller = TextEditingController(text: item.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('重命名', style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '新名称'),
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
    if (newName == null || newName.trim().isEmpty || newName.trim() == item.name) {
      return;
    }
    await _repo.rename(item.id, newName);
    ReloadBus.instance.bump();
    setState(_reload);
  }

  Future<void> _deactivate(TaxonomyItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('删除「${item.name}」？', style: const TextStyle(fontSize: 15)),
        content: const Text('删除后：新增课的选项里不再出现；\n已记录的历史课不受影响。',
            style: TextStyle(fontSize: 12, height: 1.7)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('删除',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error))),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.deactivate(item.id);
    ReloadBus.instance.bump();
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
            onPressed: () => Navigator.pop(context)),
        centerTitle: true,
        title: Text(widget.title,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
      body: FutureBuilder<List<TaxonomyItem>>(
        future: _items,
        builder: (context, snap) {
          final items = snap.data ?? const <TaxonomyItem>[];
          if (items.isEmpty) {
            return Center(
                child: Text('还没有条目', style: TextStyle(fontSize: 12, color: AppColors.faint)));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: TextStyle(
                            fontSize: 13,
                            color: item.isActive
                                ? AppColors.ink
                                : AppColors.faint,
                            decoration: item.isActive
                                ? null
                                : TextDecoration.lineThrough),
                      ),
                    ),
                    if (!item.isActive)
                      Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Text('已删除',
                            style: TextStyle(
                                fontSize: 10, color: AppColors.faint)),
                      ),
                    IconButton(
                      icon: Icon(Icons.edit_outlined,
                          size: 18, color: AppColors.secondary),
                      onPressed: () => _rename(item),
                    ),
                    if (item.isActive && !item.isBuiltin)
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            size: 18, color: AppColors.secondary),
                        onPressed: () => _deactivate(item),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
