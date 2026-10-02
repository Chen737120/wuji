import 'package:flutter/material.dart';
import '../../theme.dart';

/// 课程时长弹层（规格 §3.4）：上课节数（1–10）× 每节时长（50–180，步进 5）。
Future<(int, int)?> showDurationSheet(BuildContext context,
    {required int sessions, required int minutesEach}) {
  return showModalBottomSheet<(int, int)>(
    context: context,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _DurationSheet(sessions: sessions, minutesEach: minutesEach),
  );
}

class _DurationSheet extends StatefulWidget {
  const _DurationSheet({required this.sessions, required this.minutesEach});
  final int sessions;
  final int minutesEach;

  @override
  State<_DurationSheet> createState() => _DurationSheetState();
}

class _DurationSheetState extends State<_DurationSheet> {
  late int _sessions = widget.sessions;
  late int _minutes = widget.minutesEach;

  List<int> get _minuteOptions =>
      [for (var m = 50; m <= 180; m += 5) m];

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('课程时长',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.faint),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _column(
                    label: '上课节数',
                    options: [for (var i = 1; i <= 10; i++) i],
                    current: _sessions,
                    format: (v) => '$v 节',
                    onSelect: (v) => setState(() => _sessions = v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 30),
                  child: Text('×', style: TextStyle(color: AppColors.secondary)),
                ),
                Expanded(
                  child: _column(
                    label: '每节时长',
                    options: _minuteOptions,
                    current: _minutes,
                    format: (v) => '$v 分钟',
                    onSelect: (v) => setState(() => _minutes = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('例：连上 2 节 × 90 分钟 ＝ 这天记 180 分钟、2 节',
                style: TextStyle(fontSize: 10, color: AppColors.secondary)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => Navigator.pop(context, (_sessions, _minutes)),
                child: const Text('确认时长',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _column({
    required String label,
    required List<int> options,
    required int current,
    required String Function(int) format,
    required ValueChanged<int> onSelect,
  }) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Text(label,
            style: TextStyle(fontSize: 11, color: AppColors.secondary)),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 180),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.hairline),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, i) {
              final v = options[i];
              final selected = v == current;
              return InkWell(
                onTap: () => onSelect(v),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(format(v),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w400,
                            color: selected ? Colors.white : AppColors.secondary)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
