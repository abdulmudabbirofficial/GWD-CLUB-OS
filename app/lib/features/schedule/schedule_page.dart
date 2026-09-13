import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/brand.dart';
import '../../app/widgets/common.dart';
import '../../core/models/schedule_category.dart';
import '../../core/models/schedule_entry.dart';
import '../tasks/task_detail_page.dart';
import 'schedule_editor.dart';
import 'schedule_entry_page.dart';

const _months = ['January', 'February', 'March', 'April', 'May', 'June',
                 'July', 'August', 'September', 'October', 'November', 'December'];
const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const _weekdaysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// The club schedule.
///
/// Agenda-first, not a month grid: a grid looks like a calendar but answers
/// almost nothing a member asks ("what's on today", "when does my post go
/// out"). The date rail above is only for jumping, and it runs a full year
/// forward — the previous version stopped dead after fourteen days with no way
/// to go further, which made the whole screen feel broken.
///
/// Categories are club-defined, so the filter row is built from data.
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  String? _categoryId; // null = everything
  DateTime? _focusDay;
  final _railController = ScrollController();

  /// "The club" or "Mine".
  ///
  /// The club schedule stays open to everyone — the commonest complaint about
  /// running a club is not knowing what is happening. But *what is the club
  /// doing* and *what do I owe, and by when* are different questions, and
  /// answering the second by making somebody scan the first is how deadlines
  /// get missed.
  ///
  /// Filtered on the client because the schedule is already loaded: switching
  /// should be instant, not a round trip.
  bool _mineOnly = false;

  /// The rail runs a year ahead. Long enough that nobody hits the end while
  /// planning a semester, short enough to build in one pass.
  static const _railDays = 365;
  static const _dayExtent = 54.0;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _railController.dispose();
    super.dispose();
  }

  void _jumpToToday() {
    setState(() => _focusDay = null);
    _railController.animateTo(
      0,
      duration: AppleDuration.slow,
      curve: AppleCurves.standard,
    );
  }

  /// The month label follows the rail, so scrolling three months out does not
  /// leave a header claiming it is still September.
  DateTime get _visibleMonth {
    if (!_railController.hasClients) return _focusDay ?? _today;
    final index = (_railController.offset / _dayExtent).floor().clamp(0, _railDays - 1);
    return _today.add(Duration(days: index));
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final layout = Layout.of(context);

    final meId = AppScope.sessionOf(context).me?.id;
    final all = store.entriesIn(_categoryId);
    final visible = all.where((e) {
      if (_mineOnly && !e.isMine(meId)) return false;
      if (e.isPast && !e.isToday) return false;
      if (_focusDay != null) return e.day == _focusDay;
      return true;
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    // How much is actually mine, for the toggle's own label. A switch that
    // cannot say what it would show is a switch people press once.
    final mineCount = all
        .where((e) => e.isMine(meId) && (!e.isPast || e.isToday))
        .length;

    final grouped = <DateTime, List<ScheduleEntry>>{};
    for (final entry in visible) {
      grouped.putIfAbsent(entry.day, () => []).add(entry);
    }
    final days = grouped.keys.toList()..sort();

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      floatingActionButton: store.capabilities.canCreateScheduleEntry
          ? FloatingActionButton.extended(
              onPressed: () => showScheduleEditor(
                context,
                categoryId: _categoryId == ScheduleCategory.deadlineId ? null : _categoryId,
                initialDate: _focusDay,
              ),
              backgroundColor: GwdColors.primaryRed,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text('Add', style: GwdType.headline.copyWith(color: Colors.white)),
            )
          : null,
      body: RefreshIndicator(
        color: GwdColors.primaryRed,
        onRefresh: () => store.loadAll(silent: true),
        child: ContentWidth(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(layout.gutter, GwdSpace.lg, layout.gutter, 0),
                    child: _Header(
                      month: _visibleMonth,
                      focusDay: _focusDay,
                      onToday: _jumpToToday,
                    ),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: GwdSpace.md, bottom: GwdSpace.md),
                  child: _DateRail(
                    controller: _railController,
                    start: _today,
                    days: _railDays,
                    extent: _dayExtent,
                    gutter: layout.gutter,
                    selected: _focusDay,
                    entries: store.schedule,
                    onSelect: (day) => setState(
                        () => _focusDay = _focusDay == day ? null : day),
                    onScroll: () => setState(() {}),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: layout.gutter),
                  child: _ScopeSwitch(
                    mineOnly: _mineOnly,
                    mineCount: mineCount,
                    onChanged: (next) => setState(() => _mineOnly = next),
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: GwdSpace.md)),

              SliverToBoxAdapter(
                child: _CategoryBar(
                  gutter: layout.gutter,
                  categories: store.activeCategories,
                  selected: _categoryId,
                  counts: _counts(store.schedule),
                  onChanged: (id) => setState(() => _categoryId = id),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: GwdSpace.lg)),

              if (store.loading && !store.hasLoadedOnce)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: layout.gutter),
                    child: const SkeletonList(count: 4, height: 64),
                  ),
                )
              else if (days.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptySchedule(
                    category: store.categoryById(_categoryId),
                    focusDay: _focusDay,
                    canAdd: store.capabilities.canCreateScheduleEntry,
                    onClear: _focusDay != null
                        ? () => setState(() => _focusDay = null)
                        : null,
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, 110),
                  sliver: SliverList.builder(
                    itemCount: days.length,
                    itemBuilder: (context, i) {
                      final day = days[i];
                      final items = grouped[day]!;
                      return AppleStaggerItem(
                        index: i,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _DayHeader(day: day, count: items.length),
                            for (final entry in items)
                              Padding(
                                padding: const EdgeInsets.only(bottom: GwdSpace.sm),
                                child: _EntryRow(
                                  key: ValueKey(entry.id),
                                  entry: entry,
                                  onTap: () => _open(entry),
                                ),
                              ),
                            const SizedBox(height: GwdSpace.lg),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(ScheduleEntry entry) {
    // A deadline *is* a task — open the task, not a read-only copy of it.
    if (entry.isDeadline && entry.taskId != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TaskDetailPage(taskId: entry.taskId!)),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScheduleEntryPage(entryId: entry.id)),
    );
  }

  Map<String, int> _counts(List<ScheduleEntry> all) {
    final counts = <String, int>{};
    for (final entry in all) {
      if (entry.isPast && !entry.isToday) continue;
      final key = entry.isDeadline
          ? ScheduleCategory.deadlineId
          : (entry.categoryId ?? '');
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }
}

/// "The club" / "Mine" — two segments, one question each.
///
/// Not a filter chip among the categories: those narrow *what kind of thing*,
/// this narrows *whose*. Mixing the two axes into one row is how a filter bar
/// stops being readable.
class _ScopeSwitch extends StatelessWidget {
  const _ScopeSwitch({
    required this.mineOnly,
    required this.mineCount,
    required this.onChanged,
  });

  final bool mineOnly;
  final int mineCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: GwdColors.sunkenOf(context),
        borderRadius: BorderRadius.circular(GwdRadius.md),
      ),
      child: Row(
        children: [
          _Segment(
            label: 'The club',
            selected: !mineOnly,
            onTap: () => onChanged(false),
          ),
          _Segment(
            // The count is the point: "Mine · 3" answers the question before
            // you even press it.
            label: mineCount == 0 ? 'Mine' : 'Mine · $mineCount',
            selected: mineOnly,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: PressableScale(
        onTap: onTap,
        pressedScale: 0.98,
        haptic: HapticStrength.selection,
        child: AnimatedContainer(
          duration: AppleDuration.fast,
          curve: AppleCurves.standard,
          padding: const EdgeInsets.symmetric(vertical: GwdSpace.sm + 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? GwdColors.surfaceOf(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(GwdRadius.sm + 2),
            boxShadow: selected
                ? GwdShadow.resting(Theme.of(context).brightness == Brightness.dark)
                : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GwdType.footnote.copyWith(
              color: selected
                  ? GwdColors.inkOf(context)
                  : GwdColors.inkTertiaryOf(context),
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.month, required this.focusDay, required this.onToday});

  final DateTime month;
  final DateTime? focusDay;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final showToday = focusDay != null
        || month.month != now.month
        || month.year != now.year;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Schedule',
                  style: GwdType.largeTitle.copyWith(color: GwdColors.inkOf(context))),
              const SizedBox(height: 2),
              // The month follows the rail rather than sitting fixed, so it is
              // always telling the truth about what you are looking at.
              AnimatedSwitcher(
                duration: AppleDuration.fast,
                child: Text(
                  '${_months[month.month - 1]} ${month.year}',
                  key: ValueKey('${month.year}-${month.month}'),
                  style: GwdType.callout
                      .copyWith(color: GwdColors.inkTertiaryOf(context)),
                ),
              ),
            ],
          ),
        ),
        AnimatedOpacity(
          duration: AppleDuration.fast,
          opacity: showToday ? 1 : 0,
          child: IgnorePointer(
            ignoring: !showToday,
            child: PressableScale(
              haptic: HapticStrength.selection,
              onTap: onToday,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: GwdSpace.md, vertical: 7),
                decoration: BoxDecoration(
                  color: GwdColors.surfaceOf(context),
                  borderRadius: BorderRadius.circular(GwdRadius.pill),
                  border: Border.all(color: GwdColors.hairlineOf(context)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.today_outlined, size: 13, color: GwdColors.primaryRed),
                    const SizedBox(width: 5),
                    Text('Today',
                        style: GwdType.footnote.copyWith(
                            color: GwdColors.primaryRed, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A year of days, scrollable. Month boundaries get a divider so scrolling
/// feels located rather than endless.
class _DateRail extends StatelessWidget {
  const _DateRail({
    required this.controller,
    required this.start,
    required this.days,
    required this.extent,
    required this.gutter,
    required this.selected,
    required this.entries,
    required this.onSelect,
    required this.onScroll,
  });

  final ScrollController controller;
  final DateTime start;
  final int days;
  final double extent;
  final double gutter;
  final DateTime? selected;
  final List<ScheduleEntry> entries;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onScroll;

  @override
  Widget build(BuildContext context) {
    final busy = <DateTime, List<Color>>{};
    for (final entry in entries) {
      final list = busy.putIfAbsent(entry.day, () => []);
      if (list.length < 3 && !list.contains(entry.tint)) list.add(entry.tint);
    }

    return SizedBox(
      height: 76,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollUpdateNotification) onScroll();
          return false;
        },
        child: ListView.builder(
          controller: controller,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: gutter),
          itemCount: days,
          itemExtent: extent,
          itemBuilder: (context, i) {
            final day = start.add(Duration(days: i));
            final dots = busy[day] ?? const <Color>[];
            final isToday = i == 0;
            final isSelected = selected == day;
            final isFirstOfMonth = day.day == 1;

            return Row(
              children: [
                if (isFirstOfMonth && i != 0)
                  Container(
                    width: 1,
                    height: 30,
                    margin: const EdgeInsets.only(right: 5),
                    color: GwdColors.hairlineOf(context),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: GwdSpace.sm),
                    child: PressableScale(
                      haptic: HapticStrength.selection,
                      pressedScale: 0.9,
                      onTap: () => onSelect(day),
                      child: AnimatedContainer(
                        duration: AppleDuration.fast,
                        curve: AppleCurves.standard,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? GwdColors.inkOf(context)
                              : GwdColors.surfaceOf(context),
                          borderRadius: BorderRadius.circular(GwdRadius.md),
                          border: Border.all(
                            color: isToday && !isSelected
                                ? GwdColors.primaryRed.withValues(alpha: 0.55)
                                : GwdColors.hairlineOf(context),
                            width: isToday && !isSelected ? 1.4 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _weekdays[day.weekday - 1],
                              style: GwdType.caption.copyWith(
                                fontSize: 8,
                                color: isSelected
                                    ? GwdColors.surfaceOf(context).withValues(alpha: 0.7)
                                    : GwdColors.inkTertiaryOf(context),
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              '${day.day}',
                              style: GwdType.title3.merge(GwdType.numeric).copyWith(
                                    fontSize: 17,
                                    color: isSelected
                                        ? GwdColors.surfaceOf(context)
                                        : GwdColors.inkOf(context),
                                  ),
                            ),
                            // Show the month on the 1st so a long scroll never
                            // loses its place.
                            if (isFirstOfMonth)
                              Text(
                                _monthsShort[day.month - 1].toUpperCase(),
                                style: GwdType.caption.copyWith(
                                  fontSize: 7.5,
                                  color: isSelected
                                      ? GwdColors.surfaceOf(context)
                                      : GwdColors.primaryRed,
                                ),
                              )
                            else
                              SizedBox(
                                height: 6,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (final tint in dots)
                                      Container(
                                        width: 3.5,
                                        height: 3.5,
                                        margin: const EdgeInsets.symmetric(horizontal: 1),
                                        decoration: BoxDecoration(
                                          color: isSelected ? Colors.white : tint,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.gutter,
    required this.categories,
    required this.selected,
    required this.counts,
    required this.onChanged,
  });

  final double gutter;
  final List<ScheduleCategory> categories;
  final String? selected;
  final Map<String, int> counts;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: gutter),
        children: [
          _chip(context, null, 'All', null,
              counts.values.fold(0, (a, b) => a + b), GwdColors.inkOf(context)),
          for (final category in categories)
            _chip(context, category.id, category.name, category.iconData,
                counts[category.id] ?? 0, category.tint),
          // The derived lane sits alongside the real ones because to a member
          // it is just another thing on the calendar.
          _chip(context, ScheduleCategory.deadlineId, 'Deadlines',
              ScheduleCategory.deadline.iconData,
              counts[ScheduleCategory.deadlineId] ?? 0,
              ScheduleCategory.deadline.tint),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String? id, String label, IconData? icon,
      int count, Color tint) {
    final isSelected = selected == id;
    return Padding(
      padding: const EdgeInsets.only(right: GwdSpace.sm),
      child: PressableScale(
        haptic: HapticStrength.selection,
        onTap: () => onChanged(id),
        child: AnimatedContainer(
          duration: AppleDuration.fast,
          curve: AppleCurves.standard,
          padding: const EdgeInsets.symmetric(horizontal: GwdSpace.md, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? tint : GwdColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(GwdRadius.pill),
            border: Border.all(
                color: isSelected ? tint : GwdColors.hairlineOf(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 13,
                    color: isSelected ? Colors.white : GwdColors.inkSecondaryOf(context)),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: GwdType.footnote.copyWith(
                  color: isSelected ? Colors.white : GwdColors.inkSecondaryOf(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 5),
                Text('$count',
                    style: GwdType.caption.copyWith(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.75)
                          : GwdColors.inkTertiaryOf(context),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.count});
  final DateTime day;
  final int count;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = day.difference(today).inDays;
    final label = switch (diff) {
      0 => 'Today',
      1 => 'Tomorrow',
      _ => '${_weekdaysShort[day.weekday - 1]} ${day.day} ${_monthsShort[day.month - 1]}',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: GwdSpace.sm, top: GwdSpace.xs),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 12,
            decoration: BoxDecoration(
              color: diff == 0 ? GwdColors.primaryRed : GwdColors.hairlineOf(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: GwdSpace.sm),
          Text(
            label.toUpperCase(),
            style: GwdType.eyebrow.copyWith(
              color: diff == 0 ? GwdColors.primaryRed : GwdColors.inkTertiaryOf(context),
            ),
          ),
          const SizedBox(width: GwdSpace.sm),
          Expanded(child: Container(height: 1, color: GwdColors.hairlineOf(context))),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({super.key, required this.entry, required this.onTap});

  final ScheduleEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(GwdSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Time first — it is what people scan a schedule for.
          SizedBox(
            width: 42,
            child: Text(
              entry.timeLabel,
              style: GwdType.callout.merge(GwdType.numeric).copyWith(
                    color: GwdColors.inkOf(context),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Container(
            width: 3,
            height: 32,
            margin: const EdgeInsets.only(right: GwdSpace.md),
            decoration: BoxDecoration(
              color: entry.tint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GwdType.headline.copyWith(color: GwdColors.inkOf(context)),
                ),
                const SizedBox(height: 3),
                // One line of context, not a wall of chips. Whatever is most
                // useful for this kind of entry wins.
                Row(
                  children: [
                    Icon(entry.icon, size: 11, color: entry.tint),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _context(entry),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GwdType.footnote
                            .copyWith(color: GwdColors.inkTertiaryOf(context)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (entry.stage != null) ...[
            const SizedBox(width: GwdSpace.sm),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: entry.stage!.tint, shape: BoxShape.circle),
            ),
          ],
          const SizedBox(width: GwdSpace.sm),
          Icon(Icons.chevron_right_rounded,
              size: 18, color: GwdColors.inkTertiaryOf(context)),
        ],
      ),
    );
  }

  static String _context(ScheduleEntry entry) {
    final parts = <String>[entry.categoryName];
    if (entry.format != null) parts.add(entry.format!.label);
    if (entry.stage != null) parts.add(entry.stage!.label);
    if (entry.location.isNotEmpty) parts.add(entry.location);
    if (entry.isDeadline && entry.ownerName != null) parts.add(entry.ownerName!);
    return parts.join(' · ');
  }
}

class _EmptySchedule extends StatelessWidget {
  const _EmptySchedule({
    required this.category,
    required this.focusDay,
    required this.canAdd,
    this.onClear,
  });

  final ScheduleCategory? category;
  final DateTime? focusDay;
  final bool canAdd;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final tint = category?.tint ?? GwdColors.primaryRed;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GwdSpace.xxl),
        child: FluidReveal(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The brand bracket instead of a stock empty-state circle.
              SizedBox(
                width: 84,
                height: 84,
                child: BracketFrame(
                  color: tint.withValues(alpha: 0.45),
                  thickness: 2,
                  armLength: 0.42,
                  padding: EdgeInsets.zero,
                  child: Center(
                    child: Icon(category?.iconData ?? Icons.event_available_outlined,
                        size: 26, color: tint),
                  ),
                ),
              ),
              const SizedBox(height: GwdSpace.xl),
              Text(
                focusDay != null
                    ? 'Nothing on this day'
                    : category == null
                        ? 'Nothing scheduled'
                        : 'No ${category!.name.toLowerCase()} coming up',
                textAlign: TextAlign.center,
                style: GwdType.title3.copyWith(color: GwdColors.inkOf(context)),
              ),
              const SizedBox(height: GwdSpace.xs),
              Text(
                canAdd
                    ? 'Add something and the whole club sees it instantly.'
                    : 'When the club schedules something, it shows up here.',
                textAlign: TextAlign.center,
                style: GwdType.callout
                    .copyWith(color: GwdColors.inkSecondaryOf(context)),
              ),
              if (onClear != null) ...[
                const SizedBox(height: GwdSpace.xl),
                SecondaryButton(label: 'Show all days', onPressed: onClear),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
