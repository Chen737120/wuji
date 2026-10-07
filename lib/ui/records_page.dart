import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../data/app_repository.dart' show ClassSaver;
import '../data/db.dart' show ClassRecord, ClassRecordRowX, MediaAsset;
import '../reload_bus.dart';
import '../services/abs_path_cache.dart';
import '../services/archive_fs.dart' show MediaPathResolver;
import '../theme.dart';
import 'detail_page.dart';
import 'widgets/app_route.dart';
import 'sheets/date_sheet.dart';

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
  bool _calendarMonthInitialized = false;
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
      if (!_calendarMonthInitialized && records.isNotEmpty) {
        final latest = DateTime.parse(records.first.date); // 已按日期倒序
        _calendarMonth = DateTime(latest.year, latest.month);
        _calendarMonthInitialized = true; // 终审 M7：用户翻页后不被拉回
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
                initialMonth: _calendarMonth,
                markedDaysFor: _markedDaysIn,
                coversFor: _coversIn,
                resolver: context.read<MediaPathResolver?>(),
                selectedDay: _selectedDay,
                onMonthChanged: (m) => setState(() {
                  _calendarMonth = m;
                  _selectedDay = null;
                  CalendarSelection.selectedDay = null;
                }),
                onDayTap: (d) => setState(() {
                  _selectedDay = _selectedDay == d ? null : d;
                  CalendarSelection.selectedDay = _selectedDay;
                }),
              )
            else
              _WeekStrip(
                selectedDay: _selectedDay,
                onDayTap: (d) => setState(() {
                  _selectedDay = d;
                  CalendarSelection.selectedDay = d;
                }),
                onExpand: () => setState(() => _expanded = true),
              ),
            if (_selectedDay != null) _filterBar(),
            Expanded(child: _stream()),
          ],
        ),
      ),
    );
  }

  Set<int> _markedDaysIn(DateTime month) {
    final days = <int>{};
    for (final r in _records) {
      final d = r.dateAsDateTime;
      if (d.year == month.year && d.month == month.month) {
        days.add(d.day);
      }
    }
    return days;
  }

  /// 指定月份有课的日期 → 第一个视频的封面（无视频退图片），供日历做底图。
  Map<int, String> _coversIn(DateTime month) {
    final covers = <int, String>{};
    for (final r in _records) {
      final d = r.dateAsDateTime;
      if (d.year != month.year || d.month != month.month) continue;
      if (covers.containsKey(d.day)) continue; // 同天取第一条记录
      final media = _mediaByClass[r.id];
      if (media == null || media.isEmpty) continue;
      MediaAsset? pick;
      for (final m in media) {
        if (m.type == 'video' && m.thumbName != null) {
          pick = m;
          break;
        }
      }
      pick ??= media.first;
      final rel =
          pick.thumbName ?? (pick.type == 'image' ? pick.fileName : null);
      if (rel != null) covers[d.day] = rel;
    }
    return covers;
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
              context, AppRoute(builder: (_) => DetailPage(classId: r.id))),
        ));
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
      children: children,
    );
  }
}


/// 日历当前选中的日期：FAB 新增记录时作为默认日期（App 内存态，不持久化）。
class CalendarSelection {
  CalendarSelection._();
  static DateTime? selectedDay;
}

/// 记录页日历：左右滑动切月、点顶部年月跳转；有课的日期用第一个视频
/// 封面做底图（缩小居中不重叠），背景衬当月份数字水印。
/// 显示中的月份由本组件自持（父层只给初始值），避免双向同步互跳。
class _Calendar extends StatefulWidget {
  const _Calendar({
    required this.initialMonth,
    required this.markedDaysFor,
    required this.coversFor,
    required this.resolver,
    required this.selectedDay,
    required this.onMonthChanged,
    required this.onDayTap,
  });

  final DateTime initialMonth;
  final Set<int> Function(DateTime month) markedDaysFor;
  final Map<int, String> Function(DateTime month) coversFor;
  final MediaPathResolver? resolver;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDayTap;

  @override
  State<_Calendar> createState() => _CalendarState();
}

class _CalendarState extends State<_Calendar> {
  late PageController _pc;
  late DateTime _shown;

  static int _indexOf(DateTime m) => (m.year - 2000) * 12 + (m.month - 1);
  static DateTime _monthOf(int page) => DateTime(2000, page + 1);

  @override
  void initState() {
    super.initState();
    _shown = widget.initialMonth;
    _pc = PageController(initialPage: _indexOf(_shown));
  }

  @override
  void didUpdateWidget(covariant _Calendar old) {
    super.didUpdateWidget(old);
    // 仅父层主动变月（如首次加载定位到最新记录月）时跟随；
    // 日历内部的滑月/跳月经 onMonthChanged 已同步父层，不会走到这里
    if (widget.initialMonth != _shown) {
      _shown = widget.initialMonth;
      _pc.jumpToPage(_indexOf(_shown));
    }
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final m = DateTime(_shown.year, _shown.month + delta);
    setState(() => _shown = m);
    widget.onMonthChanged(m);
    _pc.animateToPage(_indexOf(m),
        duration: const Duration(milliseconds: 250), curve: Curves.ease);
  }

  /// 点顶部年月：弹日期弹层，跳到所选月份并选中该天
  Future<void> _pickMonthViaSheet() async {
    final picked =
        await showDateSheet(context, initial: widget.selectedDay ?? _shown);
    if (picked == null || !mounted) return;
    final m = DateTime(picked.year, picked.month);
    if (m != _shown) {
      setState(() => _shown = m);
      widget.onMonthChanged(m);
      _pc.jumpToPage(_indexOf(m));
    }
    widget.onDayTap(picked);
  }

  @override
  Widget build(BuildContext context) {
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
                  onPressed: () => _go(-1)),
              GestureDetector(
                onTap: _pickMonthViaSheet,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${_shown.year}年${_shown.month}月',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 4),
                      Icon(Icons.expand_more,
                          size: 15, color: AppColors.secondary),
                    ],
                  ),
                ),
              ),
              IconButton(
                  icon: const Icon(Icons.chevron_right, size: 18),
                  onPressed: () => _go(1)),
            ],
          ),
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
          const SizedBox(height: 2),
          LayoutBuilder(builder: (context, constraints) {
            final cellH = constraints.maxWidth / 7 / 1.15; // 压扁一点，给记录流留空间
            return SizedBox(
              height: cellH * 6,
              child: PageView.builder(
                controller: _pc,
                onPageChanged: (page) {
                  final m = _monthOf(page);
                  if (m != _shown) {
                    setState(() => _shown = m);
                    widget.onMonthChanged(m);
                  }
                },
                itemBuilder: (context, page) =>
                    _monthPage(_monthOf(page), accent),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _monthPage(DateTime month, Color accent) {
    final today = DateTime.now();
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // 周一首列：Mon=1..Sun=7
    final leadingBlanks = (first.weekday + 6) % 7;
    final markedDays = widget.markedDaysFor(month);
    final covers = widget.coversFor(month);

    return Stack(
      children: [
        // 当月份数字水印（衬底）
        Center(
          child: Text('${month.month}',
              style: TextStyle(
                  fontSize: 150,
                  fontWeight: FontWeight.w900,
                  color: accent.withValues(alpha: .06))),
        ),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.15,
          padding: EdgeInsets.zero,
          children: [
            for (var i = 0; i < leadingBlanks; i++) const SizedBox(),
            for (var day = 1; day <= daysInMonth; day++)
              Builder(builder: (context) {
                final d = DateTime(month.year, month.month, day);
                final isToday = today.year == d.year &&
                    today.month == d.month &&
                    today.day == d.day;
                final isSelected = widget.selectedDay == d;
                final hasClass = markedDays.contains(day);
                final cover = covers[day];
                return GestureDetector(
                  key: ValueKey('day-${month.year}-${month.month}-$day'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onDayTap(d),
                  child: cover == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? accent
                                    : (isToday
                                        ? accent.withValues(alpha: .15)
                                        : null),
                              ),
                              child: Text('$day',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: isSelected
                                          ? Colors.white
                                          : AppColors.ink,
                                      fontWeight: isToday || isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w400)),
                            ),
                            SizedBox(
                              height: 4,
                              child: hasClass
                                  ? CircleAvatar(
                                      radius: 2, backgroundColor: accent)
                                  : null,
                            ),
                          ],
                        )
                      : _coverCell(day, cover, isSelected, isToday, accent),
                );
              }),
          ],
        ),
      ],
    );
  }

  /// 封面底图格子：内缩不重叠、数字居中叠在封面上。
  Widget _coverCell(
      int day, String rel, bool isSelected, bool isToday, Color accent) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<String?>(
            future: AbsPathCache.resolve(widget.resolver, rel),
            builder: (context, snap) {
              final path = snap.data;
              return ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  color: AppColors.hairline,
                  child: path == null
                      ? null
                      : Image.file(File(path),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink()),
                ),
              );
            },
          ),
          if (isSelected || isToday)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: isSelected ? accent : accent.withValues(alpha: .7),
                      width: 2),
                ),
              ),
            ),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? accent : Colors.black54,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text('$day',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 收起状态的周条（参考舞动时光）：本周 7 天（周一起），今天高亮，
/// 点某天即筛选；右侧日历图标展开整月日历。
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.selectedDay,
    required this.onDayTap,
    required this.onExpand,
  });

  final DateTime? selectedDay;
  final ValueChanged<DateTime> onDayTap;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final today = DateTime.now();
    final today0 = DateTime(today.year, today.month, today.day);
    final weekStart =
        today0.subtract(Duration(days: (today0.weekday + 6) % 7));
    final days = [
      for (var i = 0; i < 7; i++) weekStart.add(Duration(days: i)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: [
            for (final d in days)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onDayTap(d),
                  child: Center(
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: d == today0 ? accent : null,
                        border: (selectedDay == d && d != today0)
                            ? Border.all(color: accent, width: 1.5)
                            : null,
                      ),
                      child: Text('${d.day}',
                          style: TextStyle(
                              fontSize: 12,
                              color: d == today0
                                  ? Colors.white
                                  : AppColors.ink,
                              fontWeight: d == today0
                                  ? FontWeight.w700
                                  : FontWeight.w400)),
                    ),
                  ),
                ),
              ),
            IconButton(
              icon: Icon(Icons.calendar_month,
                  size: 20, color: AppColors.secondary),
              tooltip: '展开日历',
              onPressed: onExpand,
            ),
          ],
        ),
      ),
    );
  }
}

/// 封面缩略图（规格 §3.3）：有缩略图文件则渲染，否则回退图标；右下角 ×N 角标。
class _CoverThumb extends StatelessWidget {
  const _CoverThumb({required this.cover, required this.resolver});

  final MediaAsset? cover;
  final MediaPathResolver? resolver;

  @override
  Widget build(BuildContext context) {
    final thumb = cover?.thumbName;
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 56,
              height: 56,
              child: (thumb != null)
                  ? FutureBuilder<String?>(
                      future: AbsPathCache.resolve(resolver, thumb),
                      builder: (context, snap) {
                        final path = snap.data;
                        if (path == null || !File(path).existsSync()) {
                          return _fallback();
                        }
                        return Image.file(File(path),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _fallback());
                      },
                    )
                  : _fallback(),
            ),
          ),
          if (cover != null)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('▶',
                    style: TextStyle(
                        fontSize: 8, color: AppColors.bg)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fallback() => Container(
        color: AppColors.ink,
        alignment: Alignment.center,
        child: Icon(
          cover == null || cover!.type == 'video'
              ? Icons.play_arrow
              : Icons.image,
          color: AppColors.bg,
          size: 22,
        ),
      );
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
            // 无附件的课：卡片右侧留白（不显示黑色占位块）
            if (cover != null)
              // Hero：卡片封面 → 详情页首图，点击时"卡片展开成详情页"
              Hero(
                tag: 'record-cover-${record.id}',
                child: _CoverThumb(
                    cover: cover, resolver: context.read<MediaPathResolver?>()),
              ),
          ],
        ),
      ),
    );
  }
}
