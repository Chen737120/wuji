import 'package:flutter/material.dart';
import '../../theme.dart';

/// 日期选择底部弹层：应用内中文月历（周一为首列），点缀色高亮，
/// 点某天直接返回。替代系统英文 Material 日期弹窗。
Future<DateTime?> showDateSheet(
  BuildContext context, {
  required DateTime initial,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => _DateSheet(
      initial: initial,
      firstDate: firstDate ?? DateTime(2000),
      lastDate: lastDate ?? DateTime(2100),
    ),
  );
}

class _DateSheet extends StatefulWidget {
  const _DateSheet({
    required this.initial,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initial;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_DateSheet> createState() => _DateSheetState();
}

class _DateSheetState extends State<_DateSheet> {
  late DateTime _month =
      DateTime(initial.year, initial.month); // 该月 1 号
  DateTime? _selected;

  DateTime get initial => widget.initial;

  void _shift(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  bool _inRange(DateTime d) =>
      !d.isBefore(DateTime(widget.firstDate.year, widget.firstDate.month,
              widget.firstDate.day)) &&
      !d.isAfter(DateTime(
          widget.lastDate.year, widget.lastDate.month, widget.lastDate.day));

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final today = DateTime.now();
    final today0 = DateTime(today.year, today.month, today.day);
    final firstOfMonth = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = (firstOfMonth.weekday + 6) % 7; // 周一首列
    final canPrev = DateTime(_month.year, _month.month)
        .isAfter(DateTime(widget.firstDate.year, widget.firstDate.month));
    final canNext = DateTime(_month.year, _month.month + 1, 0)
        .isBefore(DateTime(widget.lastDate.year, widget.lastDate.month,
            widget.lastDate.day));

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 22),
                  onPressed: canPrev ? () => _shift(-1) : null,
                ),
                GestureDetector(
                  onTap: () => setState(() {
                    _month = DateTime(today.year, today.month);
                  }),
                  child: Text('${_month.year}年${_month.month}月',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1)),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 22),
                  onPressed: canNext ? () => _shift(1) : null,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (final w in ['一', '二', '三', '四', '五', '六', '日'])
                  Expanded(
                    child: Center(
                        child: Text(w,
                            style: TextStyle(
                                fontSize: 10, color: AppColors.faint))),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.25,
              children: [
                for (var i = 0; i < leadingBlanks; i++) const SizedBox(),
                for (var day = 1; day <= daysInMonth; day++)
                  Builder(builder: (context) {
                    final d = DateTime(_month.year, _month.month, day);
                    final enabled = _inRange(d);
                    final isSelected = _selected != null &&
                        _selected!.year == d.year &&
                        _selected!.month == d.month &&
                        _selected!.day == day;
                    final isToday = today0 == d;
                    final isInitial = initial.year == d.year &&
                        initial.month == d.month &&
                        initial.day == day;
                    return GestureDetector(
                      onTap: enabled ? () => Navigator.pop(context, d) : null,
                      child: Center(
                        child: Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? accent : null,
                            border: (isToday || isInitial) && !isSelected
                                ? Border.all(
                                    color: accent.withValues(alpha: .6))
                                : null,
                          ),
                          child: Text('$day',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: !enabled
                                      ? AppColors.hairline
                                      : isSelected
                                          ? Colors.white
                                          : AppColors.ink,
                                  fontWeight: isSelected || isToday
                                      ? FontWeight.w700
                                      : FontWeight.w400)),
                        ),
                      ),
                    );
                  }),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton(
                  onPressed: _inRange(today0)
                      ? () => Navigator.pop(context, today0)
                      : null,
                  child: const Text('今天', style: TextStyle(fontSize: 13)),
                ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 8),
                  ),
                  onPressed: () => Navigator.pop(
                      context, _selected ?? (initial.isBefore(widget.firstDate) || initial.isAfter(widget.lastDate) ? null : initial)),
                  child: const Text('确定',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
