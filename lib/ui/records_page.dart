import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/app_repository.dart' show ClassSaver;
import '../data/db.dart' show ClassRecord, ClassRecordRowX, MediaAsset;
import '../reload_bus.dart';
import '../services/abs_path_cache.dart';
import '../services/archive_fs.dart' show MediaPathResolver;
import '../services/startup_warmup.dart';
import '../theme.dart';
import 'player_page.dart';
import 'record_form_page.dart';
import 'widgets/app_route.dart';
import 'widgets/pressable_scale.dart';
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

/// 按天分组（2026-10-31 T5 v1 形态：日期与星期拆开展示），日期倒序、
/// 组内按日期倒序。
class DayGroup {
  DayGroup(this.dateLabel, this.weekday, this.records);

  /// 「10月31日」
  final String dateLabel;

  /// 「周六」
  final String weekday;
  final List<ClassRecord> records;
}

List<DayGroup> groupByDay(List<ClassRecord> records) {
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  final sorted = [...records]..sort((a, b) => b.date.compareTo(a.date));
  final map = <String, DayGroup>{};
  for (final r in sorted) {
    final d = r.dateAsDateTime;
    final key = '${d.year}-${d.month}-${d.day}';
    final group = map.putIfAbsent(
        key,
        () => DayGroup('${d.month}月${d.day}日',
            weekdays[d.weekday - 1], <ClassRecord>[]));
    group.records.add(r);
  }
  return map.values.toList();
}

/// 卡片阴影（原型 --shadow-card：0 1px 2px 4% / 0 4px 14px 5%），
/// 日历卡与记录卡共用（T5 子项 3/5）。
const List<BoxShadow> kCardShadow = [
  BoxShadow(
      color: Color(0x0A1A1A1A), offset: Offset(0, 1), blurRadius: 2),
  BoxShadow(
      color: Color(0x0D1A1A1A), offset: Offset(0, 4), blurRadius: 14),
];

/// 记录页（规格 §3.3）：日历（默认展开、记住状态）＋按月分组时间流。
class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key});

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  List<ClassRecord> _records = [];
  Map<String, List<MediaAsset>> _mediaByClass = {};
  bool _expanded = true;
  bool _loaded = false;
  DateTime? _selectedDay;
  // 2026-10-08 需求 #6：日历默认显示**当前月份**（不再定位到最新记录月）
  late DateTime _calendarMonth = DateTime.now();
  // 搜索（需求 #11）
  bool _searching = false;
  String _query = '';
  final TextEditingController _searchCtl = TextEditingController();

  ClassSaver get _saver => context.read<ClassSaver>();

  // 2026-10-07 需求 #5：每次重新打开软件，选择状态恢复默认——
  // 监听生命周期，从后台回到前台（即"重新打开"）时统一重置
  bool _wasPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    ReloadBus.instance.addListener(_load);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ReloadBus.instance.removeListener(_load);
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasPaused = true;
    } else if (state == AppLifecycleState.resumed && _wasPaused) {
      _wasPaused = false;
      if (!mounted) return;
      setState(() {
        _selectedDay = null;
        CalendarSelection.selectedDay = null;
        _searching = false;
        _query = '';
        _searchCtl.clear();
        _expanded = true; // 日历展开为默认
      });
    }
  }

  Future<void> _toggleExpanded() async {
    setState(() => _expanded = !_expanded);
  }

  Future<void> _load() async {
    final records = await _saver.allRecords();
    // 一次查询取回全部附件（评审建议：替代逐课 N+1 查询）
    final media = await _saver.mediaByClass();
    if (!mounted) return;
    setState(() {
      _records = records;
      _mediaByClass = media;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 页头（用户 2026-10-31 反馈 1/3：还原 16/w700/ls3，搜索钮同一行、
            // 收紧顶部留白；大标题与毛玻璃收缩顶栏随之移除）
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Text('记录',
                      style: AppText.pageTitle.copyWith(color: AppColors.ink)),
                  const Spacer(),
                  // 搜索（需求 #11；#10 放大：圆底按钮更明显）
                  GestureDetector(
                    onTap: () => setState(() {
                      _searching = !_searching;
                      if (!_searching) _query = '';
                    }),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _searching
                            ? accent.withValues(alpha: .14)
                            : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: _searching ? accent : AppColors.hairline),
                      ),
                      child: Icon(
                          _searching ? Icons.search_off : Icons.search,
                          size: 20,
                          color: _searching ? accent : AppColors.ink),
                    ),
                  ),
                ],
              ),
            ),
            if (_searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                child: TextField(
                  autofocus: true,
                  controller: _searchCtl,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '搜索老师 / 舞种 / 舞室',
                    hintStyle:
                        const TextStyle(fontSize: 12, color: AppColors.faint),
                    prefixIcon:
                        const Icon(Icons.search, size: 18, color: AppColors.faint),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.hairline),
                    ),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
            Expanded(
              // 2026-10-07 需求 #2：日历随列表一起滚动（不再固定顶部）。
              // 滚动即上报：后台预热据此给交互让路（修 v1.5.20 预热
              // 与滚动抢 UI 线程导致卡顿/ANR）
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: (_) {
                  StartupWarmup.noteUserScroll();
                  return false;
                },
                child: _stream(),
              ),
            ),
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
    var filtered = _selectedDay == null
        ? _records
        : _records
            .where((r) =>
                r.dateAsDateTime.year == _selectedDay!.year &&
                r.dateAsDateTime.month == _selectedDay!.month &&
                r.dateAsDateTime.day == _selectedDay!.day)
            .toList();
    // 搜索过滤（需求 #11）：老师/舞种/舞室/感受
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      bool hit(ClassRecord r) =>
          (r.styleName ?? '').toLowerCase().contains(q) ||
          (r.teacherName ?? '').toLowerCase().contains(q) ||
          (r.studioName ?? '').toLowerCase().contains(q) ||
          (r.note ?? '').toLowerCase().contains(q);
      filtered = filtered.where(hit).toList();
    }
    // 时间流：日历壳随列表滚动，时间轴圆点竖线已移除（T5）
    final children = <Widget>[
      _calendarShell(),
      if (_selectedDay != null) _filterBar(),
    ];
    if (filtered.isEmpty) {
      children.add(Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Text(_query.isNotEmpty ? '没有匹配的记录' : '这一天还没有课堂记录',
              style: TextStyle(fontSize: 12, color: AppColors.faint)),
        ),
      ));
    }
    for (final g in groupByDay(filtered)) {
      // 日期头（T5 子项 4）：「10月31日 · 周六」＝14/700 ＋ 11/faint
      children.add(Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10, left: 2, right: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(g.dateLabel,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text('· ${g.weekday}',
                style: const TextStyle(fontSize: 11, color: AppColors.faint)),
          ],
        ),
      ));
      for (final r in g.records) {
        children.add(RecordCard(
          record: r,
          media: _mediaByClass[r.id] ?? const [],
        ));
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
      children: children,
    );
  }

  /// 日历/周条（需求 #2：放进滚动流，随页面滚动；T5 子项 5：
  /// AnimatedSize 弹簧高度＋进入者淡入，替换现状 setState 直切）
  Widget _calendarShell() {
    Widget fadeIn(Widget child) => TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          builder: (_, v, c) => Opacity(opacity: v, child: c),
          child: child,
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedSize(
        alignment: Alignment.topCenter,
        duration: const Duration(milliseconds: 700),
        curve: const SpringHeightCurve(),
        child: _expanded
            ? KeyedSubtree(
                key: const ValueKey('cal'),
                child: fadeIn(_Calendar(
                  initialMonth: _calendarMonth,
                  markedDaysFor: _markedDaysIn,
                  coversFor: _coversIn,
                  resolver: context.read<MediaPathResolver?>(),
                  selectedDay: _selectedDay,
                  expanded: _expanded,
                  onToggleExpanded: _toggleExpanded,
                  onMonthChanged: (m) => setState(() {
                    _calendarMonth = m;
                    _selectedDay = null;
                    CalendarSelection.selectedDay = null;
                  }),
                  onDayTap: (d) => setState(() {
                    _selectedDay = _selectedDay == d ? null : d;
                    CalendarSelection.selectedDay = _selectedDay;
                  }),
                )),
              )
            : KeyedSubtree(
                key: const ValueKey('week'),
                child: fadeIn(_WeekStrip(
                  selectedDay: _selectedDay,
                  hasClassDay: _hasClassDay,
                  onDayTap: (d) => setState(() {
                    _selectedDay = d;
                    CalendarSelection.selectedDay = d;
                  }),
                  onExpand: () => setState(() => _expanded = true),
                )),
              ),
      ),
    );
  }

  bool _hasClassDay(DateTime day) {
    for (final r in _records) {
      final d = r.dateAsDateTime;
      if (d.year == day.year && d.month == day.month && d.day == day.day) {
        return true;
      }
    }
    return false;
  }
}


/// 日历当前选中的日期：FAB 新增记录时作为默认日期（App 内存态，不持久化）。
class CalendarSelection {
  CalendarSelection._();
  static DateTime? selectedDay;
}

/// 记录页日历（T5 子项 5：radius 16 白卡阴影；卡头右侧 chevron 圆钮
/// 展开/收起，带旋转动画）：左右滑动切月、点顶部年月跳转；有课的日期
/// 用第一个视频封面做底图（缩小居中不重叠），背景衬当月份数字水印。
/// 显示中的月份由本组件自持（父层只给初始值），避免双向同步互跳。
class _Calendar extends StatefulWidget {
  const _Calendar({
    required this.initialMonth,
    required this.markedDaysFor,
    required this.coversFor,
    required this.resolver,
    required this.selectedDay,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onMonthChanged,
    required this.onDayTap,
  });

  final DateTime initialMonth;
  final Set<int> Function(DateTime month) markedDaysFor;
  final Map<int, String> Function(DateTime month) coversFor;
  final MediaPathResolver? resolver;
  final DateTime? selectedDay;
  final bool expanded;
  final VoidCallback onToggleExpanded;
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
        boxShadow: kCardShadow,
      ),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Column(
        children: [
          // 卡头：切月箭头｜年月 pill｜收起/展开 chevron 圆钮（T5 子项 1 归宿）
          Row(
            children: [
              IconButton(
                  icon: const Icon(Icons.chevron_left, size: 18),
                  onPressed: () => _go(-1)),
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: _pickMonthViaSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
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
                ),
              ),
              IconButton(
                  icon: const Icon(Icons.chevron_right, size: 18),
                  onPressed: () => _go(1)),
              GestureDetector(
                onTap: widget.onToggleExpanded,
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: AnimatedRotation(
                    turns: widget.expanded ? 0 : 0.5,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.ease,
                    child: const Icon(Icons.keyboard_arrow_down,
                        size: 20, color: AppColors.secondary),
                  ),
                ),
              ),
              const SizedBox(width: 6),
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
                            _dayCell(day, isSelected, isToday),
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

  /// 普通数字格（无封面）：选中/今天＝accent 实底圆角方白字（T5 子项 5）。
  Widget _dayCell(int day, bool isSelected, bool isToday) {
    final filled = isSelected || isToday;
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        color: filled ? Theme.of(context).colorScheme.primary : null,
      ),
      child: Text('$day',
          style: TextStyle(
              fontSize: 11,
              color: filled ? Colors.white : AppColors.ink,
              fontWeight: filled ? FontWeight.w700 : FontWeight.w400)),
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
                          cacheWidth: 300, // 日历格子小图：限解码宽防卡顿
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
          // 2026-10-07 调整 #2：去掉黑色圆角底（黑阴影感），只留底图+白色数字
          Center(
            child: Container(
              padding: isSelected
                  ? const EdgeInsets.symmetric(horizontal: 7, vertical: 2)
                  : EdgeInsets.zero,
              decoration: isSelected
                  ? BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(9),
                    )
                  : null,
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

/// 收起状态的周条（T5 子项 5：radius 16 白卡阴影；样式按原型 .ws-cell＝
/// 星期小字 9/faint＋日期 13/ink＋有课 dot；今天/选中 accent 实底圆角方）。
/// 右侧日历图标展开整月日历（收起态的唯一展开入口，行为不回归）。
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.selectedDay,
    required this.hasClassDay,
    required this.onDayTap,
    required this.onExpand,
  });

  final DateTime? selectedDay;
  final bool Function(DateTime day) hasClassDay;
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
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
        boxShadow: kCardShadow,
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(child: () {
              final d = days[i];
              final isToday = d == today0;
              final isSelected = selectedDay == d && !isToday;
              final filled = isToday;
              final hasClass = hasClassDay(d);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onDayTap(d),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: filled ? accent : null,
                    border: isSelected
                        ? Border.all(color: accent, width: 1.5)
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(weekdays[i],
                          style: TextStyle(
                              fontSize: 9,
                              color: filled
                                  ? Colors.white.withValues(alpha: .78)
                                  : AppColors.faint)),
                      const SizedBox(height: 2),
                      Text('${d.day}',
                          style: TextStyle(
                              fontSize: 13,
                              color: filled ? Colors.white : AppColors.ink,
                              fontWeight:
                                  filled ? FontWeight.w700 : FontWeight.w400)),
                      SizedBox(
                        height: 7,
                        child: hasClass
                            ? CircleAvatar(
                                radius: 2,
                                backgroundColor:
                                    filled ? Colors.white : accent)
                            : null,
                      ),
                    ],
                  ),
                ),
              );
            }()),
          IconButton(
            icon: Icon(Icons.calendar_month,
                size: 20, color: AppColors.secondary),
            tooltip: '展开日历',
            onPressed: onExpand,
          ),
        ],
      ),
    );
  }
}

/// 记录卡片（2026-10-07 需求 #10 重做；2026-10-31 T5 v1 形态）：
/// 阴影白卡 radius 16（无边框）→ 感受 13.5/1.62 → 媒体网格
/// （1 个 16:9、2 个 16:10、≥3 个 1:1；视频格叠播放角标＋时长胶囊）→
/// 图标化元数据行。长按弹快捷菜单；点媒体直接全屏播放（PressableScale 按压）。
class RecordCard extends StatefulWidget {
  const RecordCard({
    super.key,
    required this.record,
    required this.media,
  });

  final ClassRecord record;
  final List<MediaAsset> media;

  @override
  State<RecordCard> createState() => _RecordCardState();
}

class _RecordCardState extends State<RecordCard> {
  ClassRecord get r => widget.record;

  /// 防连点叠层（2026-10-28 反馈 #1）：一次点击只入栈一页。
  bool _opening = false;

  void _openMedia(MediaAsset m) {
    // 图片不跳转（2026-10-07：旧详情查看页已从记录卡移除）；视频立即进
    // 播放页，SAF 解析与播放器初始化在页内做（反馈 #1：原实现在 push 前
    // await 缓存拷贝，debug 下数秒零反馈、连点会叠多层页面）
    if (m.type != 'video') return;
    if (_opening) return;
    _opening = true;
    Navigator.push(
      context,
      AppRoute(
        builder: (_) => PlayerPage.pendingMedia(
          rel: m.fileName,
          resolver: context.read<MediaPathResolver?>(), // push 前取好
          // 顶栏标题（T10b）：日期 · 舞种，与原型 pv-title 同构
          title: _playerTitle(),
        ),
      ),
    ).whenComplete(() => _opening = false);
  }

  /// 播放器顶栏标题：「10月31日 · 爵士舞」（无舞种时只留日期）
  String _playerTitle() {
    final d = r.dateAsDateTime;
    final style = (r.styleName == null || r.styleName!.isEmpty)
        ? null
        : r.styleName;
    return style == null ? '${d.month}月${d.day}日' : '${d.month}月${d.day}日 · $style';
  }

  void _showActions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, size: 20),
              title: const Text('编辑记录', style: TextStyle(fontSize: 13)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context,
                    AppRoute(builder: (_) => RecordFormPage(existing: r)));
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  size: 20, color: Theme.of(context).colorScheme.error),
              title: Text('删除记录',
                  style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.error)),
              onTap: () async {
                Navigator.pop(ctx);
                final n = widget.media.length;
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    backgroundColor: Colors.white,
                    title:
                        const Text('删除这节课？', style: TextStyle(fontSize: 16)),
                    content: Text('将删除 $n 个视频/图片，不可恢复。',
                        style: const TextStyle(fontSize: 13)),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dctx, false),
                          child: const Text('取消')),
                      TextButton(
                          onPressed: () => Navigator.pop(dctx, true),
                          child: Text('确认删除',
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.error))),
                    ],
                  ),
                );
                if (ok != true) return;
                if (!mounted) return;
                try {
                  await context.read<ClassSaver>().deleteRecord(r.id);
                  ReloadBus.instance.bump();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('删除失败：$e')));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = (r.styleName == null || r.styleName!.isEmpty)
        ? null
        : r.styleName;
    // 感受只显示一遍（2026-10-07 需求 #6/#7）：完整原文、黑色正常字重、
    // 不折叠；无感受时退回标题（M/D 舞种课）
    final hasNote = (r.note?.trim() ?? '').isNotEmpty;
    final noteText = hasNote ? r.note!.trim() : recordTitle(r);

    return GestureDetector(
      // 2026-10-07 需求 #2：点卡片不再进入旧详情查看页（媒体格/…按钮各自响应）
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: kCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 感受/标题：完整一遍、不折叠（需求 #6/#7；T5 字阶 13.5/1.62）
            Text(noteText,
                style:
                    AppText.cardBody.copyWith(color: AppColors.ink)),
            if (widget.media.isNotEmpty) ...[
              const SizedBox(height: 10),
              _mediaGrid(),
            ],
            const SizedBox(height: 10),
            // 图标化元数据 + "…"同行（2026-10-07 调整 #3：不额外占一行）
            Wrap(
              spacing: 14,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final (icon, text) in [
                  (Icons.music_note, style ?? '未设舞种'),
                  (Icons.schedule, '${r.sessionCount}节×${r.minutesEach}分'),
                  if (r.teacherName?.isNotEmpty ?? false)
                    (Icons.person, r.teacherName!),
                  // 舞室（spec §1：元数据行＝舞种/分钟/老师/舞室＋「…」；
                  // 用户 2026-10-31 走查指出此前缺失）
                  if (r.studioName?.isNotEmpty ?? false)
                    (Icons.place_outlined, r.studioName!),
                ])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 12, color: AppColors.faint),
                      const SizedBox(width: 3),
                      Text(text,
                          style: TextStyle(
                              fontSize: 10, color: AppColors.secondary)),
                    ],
                  ),
                // "…"快捷菜单（跟在标签尾部同一行）
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _showActions,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 2, right: 2),
                    child: Icon(Icons.more_horiz,
                        size: 20, color: AppColors.secondary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 媒体网格（T5 子项 3）：1 个 16:9；2 个 16:10 并排；≥3 个每行 3 格 1:1。
  /// 视频格叠播放角标＋右下时长胶囊（durationSec 为 null 不显示胶囊）。
  Widget _mediaGrid() {
    final list = widget.media.take(6).toList();
    // 软占位色（2026-10-08 需求 #5）：浅灰替代黑底；解码/文件错误也落到这里
    Widget placeholder(MediaAsset m) => Container(
        color: AppColors.hairline,
        alignment: Alignment.center,
        child: Icon(m.type == 'video' ? Icons.play_arrow : Icons.image_outlined,
            color: AppColors.faint, size: 22));

    /// 时长胶囊（原型 .mdur）：黑 55% 底白字 10、tabular 数字
    Widget durBadge(int sec) => Positioned(
          right: 6,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '${(sec ~/ 60).toString().padLeft(2, '0')}:${(sec % 60).toString().padLeft(2, '0')}',
              style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
        );

    Widget cell(MediaAsset m) {
      final rel = m.thumbName ?? (m.type == 'image' ? m.fileName : null);
      final first = m == widget.media.first;
      final isVideo = m.type == 'video';
      // 不在 build 里做 existsSync（快速滚动时是 UI 线程同步盘 IO）；
      // 文件丢失/解码失败统一走 errorBuilder 的占位态
      final inner = rel == null
          ? placeholder(m)
          : FutureBuilder<String?>(
              future: AbsPathCache.resolve(
                  context.read<MediaPathResolver?>(), rel),
              builder: (context, snap) {
                final path = snap.data;
                final hasImg = path != null;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasImg)
                      Image.file(File(path),
                          fit: BoxFit.cover,
                          cacheWidth: 500, // 网格格子小图：限解码宽防卡顿
                          errorBuilder: (_, _, _) => placeholder(m))
                    else
                      placeholder(m),
                    // 播放角标只在有封面图时叠加（浅灰占位上白角标不可见）
                    if (isVideo && hasImg)
                      const Center(
                        child: Icon(Icons.play_arrow,
                            size: 30,
                            color: Color(0xEBFFFFFF),
                            shadows: [
                              Shadow(
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                  color: Color(0x59000000))
                            ]),
                      ),
                    if (isVideo && hasImg && m.durationSec != null)
                      durBadge(m.durationSec!),
                  ],
                );
              },
            );
      Widget core = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openMedia(m),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox.expand(child: inner)),
      );
      // T5 子项 6：媒体格按压反馈（Listener 不消费事件，onTap 照常）
      core = PressableScale(child: core);
      // 首图与详情页首图共用 Hero tag（卡片"展开成详情页"）
      return first ? Hero(tag: 'record-cover-${r.id}', child: core) : core;
    }

    final count = list.length;
    if (count == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
            aspectRatio: 16 / 9, child: cell(list.first)),
      );
    }
    if (count == 2) {
      return Row(
        children: [
          for (final m in list)
            Expanded(
                child: AspectRatio(
                    aspectRatio: 16 / 10,
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: cell(m)))),
        ],
      );
    }
    // ≥3：每行 3 格 1:1
    final rows = <Widget>[];
    for (var i = 0; i < count; i += 3) {
      final chunk = list.skip(i).take(3).toList();
      rows.add(Row(
        children: [
          for (var j = 0; j < 3; j++)
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: j < chunk.length
                        ? cell(chunk[j])
                        : const SizedBox.shrink()),
              ),
            ),
        ],
      ));
    }
    return Column(children: rows);
  }
}
