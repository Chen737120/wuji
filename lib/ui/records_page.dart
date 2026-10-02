import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/app_repository.dart' show ClassSaver;
import '../data/db.dart' show ClassRecord, ClassRecordRowX, MediaAsset;
import '../reload_bus.dart';
import '../theme.dart';
import 'detail_page.dart';

/// 卡片标题：感受第一行；未写则「M/D 舞种课」（无舞种「M/D 舞蹈课」）。
String recordTitle(ClassRecord r) {
  final note = r.note?.trim();
  if (note != null && note.isNotEmpty) {
    final firstLine = note.split('\n').first.trim();
    if (firstLine.isNotEmpty) return firstLine;
  }
  final d = r.dateAsDateTime;
  final style = (r.styleName == null || r.styleName!.isEmpty)
      ? '舞蹈'
      : r.styleName!;
  return '${d.month}/${d.day} $style课';
}

/// 按月分组（key：yyyy年M月），月份倒序、组内按日期倒序。
List<MapEntry<String, List<ClassRecord>>> groupByMonth(
    List<ClassRecord> records) {
  final sorted = [...records]..sort((a, b) => b.date.compareTo(a.date));
  final map = <String, List<ClassRecord>>{};
  for (final r in sorted) {
    final d = r.dateAsDateTime;
    map.putIfAbsent('${d.year}年${d.month}月', () => []).add(r);
  }
  return map.entries.toList();
}

/// 记录页（规格 §3.3）：日历（默认展开、记住状态）＋按月分组时间流。
class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key});

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  List<ClassRecord> _records = [];
  Map<String, List<MediaAsset>> _mediaByClass = {};
  bool _expanded = true;
  bool _loaded = false;
  DateTime? _selectedDay;
  late DateTime _calendarMonth;

  ClassSaver get _saver => context.read<ClassSaver>();

  @override
  void initState() {
    super.initState();
    _calendarMonth = DateTime.now();
    _restoreExpanded();
    _load();
    ReloadBus.instance.addListener(_load);
  }

  @override
  void dispose() {
    ReloadBus.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _restoreExpanded() async {
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _expanded = sp.getBool('calendarExpanded') ?? true);
  }

  Future<void> _toggleExpanded() async {
    setState(() => _expanded = !_expanded);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('calendarExpanded', _expanded);
  }

  Future<void> _load() async {
    final records = await _saver.allRecords();
    final media = <String, List<MediaAsset>>{};
    for (final r in records) {
      media[r.id] = await _saver.mediaOf(r.id);
    }
    if (!mounted) return;
    setState(() {
      _records = records;
      _mediaByClass = media;
      _loaded = true;
      if (records.isNotEmpty) {
        final latest = DateTime.parse(records.first.date); // 已按日期倒序
        _calendarMonth = DateTime(latest.year, latest.month);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('记录',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 3)),
                  GestureDetector(
                    onTap: _toggleExpanded,
                    child: Text(_expanded ? '收起日历 ⌃' : '展开日历 ⌄',
                        style: TextStyle(fontSize: 11, color: AppColors.faint)),
                  ),
                ],
              ),
            ),
            if (_expanded)
              _Calendar(
                month: _calendarMonth,
                markedDays: _markedDays(),
                selectedDay: _selectedDay,
                onPrev: () => setState(() {
                  _calendarMonth =
                      DateTime(_calendarMonth.year, _calendarMonth.month - 1);
                }),
                onNext: () => setState(() {
                  _calendarMonth =
                      DateTime(_calendarMonth.year, _calendarMonth.month + 1);
                }),
                onDayTap: (d) => setState(() {
                  _selectedDay = _selectedDay == d ? null : d;
                }),
              ),
            if (_selectedDay != null) _filterBar(),
            Expanded(child: _stream()),
          ],
        ),
      ),
    );
  }

  Set<int> _markedDays() {
    final days = <int>{};
    for (final r in _records) {
      final d = r.dateAsDateTime;
      if (d.year == _calendarMonth.year && d.month == _calendarMonth.month) {
        days.add(d.day);
      }
    }
    return days;
  }

  Widget _filterBar() {
    final day = _selectedDay!;
    final sessions = _records
        .where((r) =>
            r.dateAsDateTime.year == day.year &&
            r.dateAsDateTime.month == day.month &&
            r.dateAsDateTime.day == day.day)
        .fold<int>(0, (a, r) => a + r.sessionCount);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          Text('${day.month}月${day.day}日 · $sessions 节课',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => setState(() => _selectedDay = null),
            child: const Icon(Icons.close, size: 16, color: AppColors.faint),
          ),
        ],
      ),
    );
  }

  Widget _stream() {
    if (!_loaded) {
      return const Center(
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)));
    }
    final filtered = _selectedDay == null
        ? _records
        : _records
            .where((r) =>
                r.dateAsDateTime.year == _selectedDay!.year &&
                r.dateAsDateTime.month == _selectedDay!.month &&
                r.dateAsDateTime.day == _selectedDay!.day)
            .toList();
    if (filtered.isEmpty) {
      return Center(
          child: Text('这一天还没有课堂记录',
              style: TextStyle(fontSize: 12, color: AppColors.faint)));
    }
    final children = <Widget>[];
    for (final g in groupByMonth(filtered)) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Text(g.key,
            style: TextStyle(fontSize: 12, color: AppColors.secondary)),
      ));
      for (final r in g.value) {
        children.add(RecordCard(
          record: r,
          media: _mediaByClass[r.id] ?? const [],
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => DetailPage(classId: r.id))),
        ));
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
      children: children,
    );
  }
}

class _Calendar extends StatelessWidget {
  const _Calendar({
    required this.month,
    required this.markedDays,
    required this.selectedDay,
    required this.onPrev,
    required this.onNext,
    required this.onDayTap,
  });

  final DateTime month;
  final Set<int> markedDays;
  final DateTime? selectedDay;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // 周一首列：Mon=1..Sun=7
    final leadingBlanks = (first.weekday + 6) % 7;
    final accent = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                  icon: const Icon(Icons.chevron_left, size: 18),
                  onPressed: onPrev),
              Text('${month.year}年${month.month}月',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              IconButton(
                  icon: const Icon(Icons.chevron_right, size: 18),
                  onPressed: onNext),
            ],
          ),
          Row(
            children: [
              for (final w in ['一', '二', '三', '四', '五', '六', '日'])
                Expanded(
                  child: Center(
                      child: Text(w,
                          style:
                              TextStyle(fontSize: 10, color: AppColors.faint))),
                ),
            ],
          ),
          const SizedBox(height: 2),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.5,
            children: [
              for (var i = 0; i < leadingBlanks; i++) const SizedBox(),
              for (var day = 1; day <= daysInMonth; day++)
                Builder(builder: (context) {
                  final d = DateTime(month.year, month.month, day);
                  final isToday = today.year == d.year &&
                      today.month == d.month &&
                      today.day == d.day;
                  final isSelected = selectedDay == d;
                  final hasClass = markedDays.contains(day);
                  return GestureDetector(
                    onTap: () => onDayTap(d),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? accent
                                : (isToday ? accent.withValues(alpha: .15) : null),
                          ),
                          child: Text('$day',
                              style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      isSelected ? Colors.white : AppColors.ink,
                                  fontWeight: isToday || isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w400)),
                        ),
                        SizedBox(
                          height: 4,
                          child: hasClass
                              ? CircleAvatar(radius: 2, backgroundColor: accent)
                              : null,
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ],
      ),
    );
  }
}

class RecordCard extends StatelessWidget {
  const RecordCard({
    super.key,
    required this.record,
    required this.media,
    required this.onTap,
  });

  final ClassRecord record;
  final List<MediaAsset> media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tags = [
      if (record.styleName?.isNotEmpty ?? false) record.styleName!,
      '${record.sessionCount}节×${record.minutesEach}分',
      if (record.teacherName?.isNotEmpty ?? false) record.teacherName!,
      if (record.studioName?.isNotEmpty ?? false) record.studioName!,
    ].join(' · ');
    final cover = media.isNotEmpty ? media.first : null;
    final d = record.dateAsDateTime;
    final isVideoCover = cover != null && cover.type == 'video';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(recordTitle(record),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 6),
                      Text(DateFormat('M/d').format(d),
                          style: TextStyle(fontSize: 11, color: AppColors.faint)),
                    ],
                  ),
                  if (media.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('共 ${media.length} 个附件',
                          style: TextStyle(fontSize: 9, color: AppColors.faint)),
                    ),
                  const SizedBox(height: 6),
                  Text(tags,
                      style: TextStyle(fontSize: 11, color: AppColors.secondary)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(
                cover == null || isVideoCover ? Icons.play_arrow : Icons.image,
                color: AppColors.bg,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
