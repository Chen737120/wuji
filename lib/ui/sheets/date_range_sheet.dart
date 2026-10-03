import 'package:flutter/material.dart';
import '../../theme.dart';

/// 起止日期选择底部弹层：同一张中文月历上点第一天=开始、再点一天=结束
/// （晚于开始的点击自动与开始互换），区间内日期浅色高亮。
/// 返回 (开始, 结束)（均含）；取消返回 null。
Future<(DateTime, DateTime)?> showDateRangeSheet(
  BuildContext context, {
  DateTime? initialStart,
  DateTime? initialEnd,
}) {
  return showModalBottomSheet<(DateTime, DateTime)>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => _DateRangeSheet(
      initialStart: initialStart,
      initialEnd: initialEnd,
    ),
  );
}

class _DateRangeSheet extends StatefulWidget {
  const _DateRangeSheet({this.initialStart, this.initialEnd});

  final DateTime? initialStart;
  final DateTime? initialEnd;

  @override
  State<_DateRangeSheet> createState() => _DateRangeSheetState();
}

class _DateRangeSheetState extends State<_DateRangeSheet> {
  late DateTime _month;
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart == null
        ? null
        : DateTime(widget.initialStart!.year, widget.initialStart!.month,
            widget.initialStart!.day);
    _end = widget.initialEnd == null
        ? null
        : DateTime(widget.initialEnd!.year, widget.initialEnd!.month,
            widget.initialEnd!.day);
    final anchor = _start ?? DateTime.now();
    _month = DateTime(anchor.year, anchor.month);
  }

  void _shift(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  void _pickDay(DateTime d) {
    setState(() {
      if (_start == null || (_start != null && _end != null)) {
        // 未选/已选满：本次点击开启新区间
        _start = d;
        _end = null;
      } else if (d.isBefore(_start!)) {
        _end = _start;
        _start = d;
      } else {
        _end = d;
      }
    });
  }

  bool _inSelectedRange(DateTime d) {
    if (_start == null || _end == null) return false;
    return !d.isBefore(_start!) && !d.isAfter(_end!);
  }

  String _label(DateTime? d) =>
      d == null ? '请选择' : '${d.month}月${d.day}日';

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final today = DateTime.now();
    final today0 = DateTime(today.year, today.month, today.day);
    final firstOfMonth = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = (firstOfMonth.weekday + 6) % 7;
    final canConfirm = _start != null && _end != null;

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
                  onPressed: () => _shift(-1),
                ),
                Text('${_month.year}年${_month.month}月',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 22),
                  onPressed: () => _shift(1),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('开始 ${_label(_start)}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _start == null ? AppColors.faint : accent)),
                const Spacer(),
                Text('结束 ${_label(_end)}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _end == null ? AppColors.faint : accent)),
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
                    final isStart = _start == d;
                    final isEnd = _end == d;
                    final inRange = _inSelectedRange(d);
                    final isToday = today0 == d;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _pickDay(d),
                      child: Center(
                        child: Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (isStart || isEnd)
                                ? accent
                                : inRange
                                    ? accent.withValues(alpha: .15)
                                    : null,
                            border: isToday && !isStart && !isEnd
                                ? Border.all(
                                    color: accent.withValues(alpha: .6))
                                : null,
                          ),
                          child: Text('$day',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: (isStart || isEnd)
                                      ? Colors.white
                                      : AppColors.ink,
                                  fontWeight: isStart || isEnd || isToday
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
                  onPressed: () => setState(() {
                    _start = today0;
                    _end = today0;
                  }),
                  child: const Text('只要今天', style: TextStyle(fontSize: 13)),
                ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 8),
                  ),
                  onPressed: canConfirm
                      ? () => Navigator.pop(context, (_start!, _end!))
                      : null,
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
