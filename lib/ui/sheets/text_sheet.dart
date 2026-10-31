import 'package:flutter/material.dart';
import '../../data/db.dart' show TaxonomyItem;
import '../../data/taxonomy_repo.dart';
import '../../models/models.dart';
import '../../theme.dart';

/// 老师/舞室输入弹层（规格 §3.4）：输入框＋确定＋「最近输入」chips。
Future<TaxonomyItem?> showTextSheet(
  BuildContext context,
  TaxonomyRepo repo,
  TaxonomyKind kind, {
  String title = '输入',
  String hint = '',
}) {
  return showModalBottomSheet<TaxonomyItem>(
    context: context,
    backgroundColor: AppColors.bg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _TextSheet(repo: repo, kind: kind, title: title, hint: hint),
  );
}

class _TextSheet extends StatefulWidget {
  const _TextSheet({
    required this.repo,
    required this.kind,
    required this.title,
    required this.hint,
  });
  final TaxonomyRepo repo;
  final TaxonomyKind kind;
  final String title;
  final String hint;

  @override
  State<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<_TextSheet> {
  final _controller = TextEditingController();
  late Future<List<TaxonomyItem>> _recent;

  /// 连点守卫（F1，同 record_media_picker_page）：touchByName await 窗口内
  /// 二次点击忽略；成功 pop 不复位（sheet 随即销毁）。
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _recent = widget.repo.byKind(widget.kind);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(widget.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.faint),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      style: const TextStyle(
                          color: AppColors.secondary), // 输入文字用浅灰
                      decoration: InputDecoration(
                        hintText: widget.hint.isEmpty ? widget.title : widget.hint,
                        hintStyle: const TextStyle(
                            color: AppColors.faint), // 提示词浅灰
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.hairline),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.hairline),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 12),
                    ),
                    onPressed: () async {
                      final name = _controller.text.trim();
                      if (name.isEmpty || _picking) return;
                      _picking = true;
                      final item =
                          await widget.repo.touchByName(widget.kind, name);
                      if (context.mounted) Navigator.pop(context, item);
                    },
                    child: const Text('确定'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('最近输入',
                  style: TextStyle(fontSize: 11, color: AppColors.secondary)),
              const SizedBox(height: 6),
              FutureBuilder<List<TaxonomyItem>>(
                future: _recent,
                builder: (context, snap) {
                  // 最近输入上限：舞室 6 个、老师 10 个（其余仍在库里，
                  // 只是新增弹层不展示；管理页列表不受影响）。
                  final limit = widget.kind == TaxonomyKind.studio ? 6 : 10;
                  final items =
                      (snap.data ?? const <TaxonomyItem>[]).take(limit);
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final it in items)
                        ActionChip(
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: AppColors.hairline),
                          shape: const StadiumBorder(),
                          label: Text(it.name,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.ink)),
                          onPressed: () => Navigator.pop(context, it),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
