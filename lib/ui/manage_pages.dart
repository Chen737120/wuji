import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/db.dart' show TaxonomyItem;
import '../data/taxonomy_repo.dart';
import '../models/models.dart';
import '../reload_bus.dart';
import '../theme.dart';

/// 重命名校验（P2-20）：空名或与本 kind 其他项（含停用）重名时返回提示文案；
/// null = 可提交。停用行同样占用 UNIQUE(kind,name)，必须一并比对。
String? validateRename(
    String? input, List<TaxonomyItem> existing, String selfId) {
  final name = input?.trim() ?? '';
  if (name.isEmpty) return '名称不能为空';
  for (final t in existing) {
    if (t.id != selfId && t.name == name) return '已存在同名，换一个';
  }
  return null;
}

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
    // 用户反馈：删除后就不需要再看到（停用项不再列出；历史课快照不受影响）
    _items = _repo.byKind(widget.kind, includeInactive: false);
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
    // 同名（含停用行）会撞 UNIQUE(kind,name)：UI 先拦截给可读提示（P2-20）
    final all = await _repo.byKind(widget.kind, includeInactive: true);
    if (!mounted) return;
    final err = validateRename(newName, all, item.id);
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    await _repo.rename(item.id, newName);
    if (!mounted) return;
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
    if (!mounted) return; // await 后再用 context/State（P2-30）
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
