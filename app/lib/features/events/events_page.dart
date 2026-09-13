import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/responsive.dart';
import '../../app/theme/apple_motion.dart';
import '../../app/theme/gwd_theme.dart';
import '../../app/widgets/brand.dart';
import '../../app/widgets/common.dart';
import '../../core/models/club_event.dart';
import 'create_event_flow.dart';
import 'event_workspace_page.dart';

/// The Events tab.
///
/// An event is the unit of work a club actually organises around — everything
/// else (tasks, paperwork, who is doing what) hangs off one. So this screen
/// answers, in order: is anything happening *right now*, what is coming, and
/// what did we do.
class EventsPage extends StatefulWidget {
  const EventsPage({super.key});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  /// Null until the first build picks the most useful group to land on.
  int? _tab;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.storeOf(context);
    final layout = Layout.of(context);

    final ongoing = store.eventsOngoing;
    final upcoming = store.eventsUpcoming;
    final completed = store.eventsCompleted;

    // Land on whichever group has something in it, rather than on an empty
    // "Upcoming" the first time somebody opens the tab after a festival.
    final tab = _tab ?? (upcoming.isNotEmpty ? 0 : (completed.isNotEmpty ? 2 : 0));

    final visible = switch (tab) {
      1 => ongoing,
      2 => completed,
      _ => upcoming,
    };

    var step = 0;
    int next() => step++;

    return Scaffold(
      backgroundColor: GwdColors.canvasOf(context),
      floatingActionButton: store.canCreateEvents
          ? _CreateEventButton(onPressed: () => CreateEventFlow.open(context))
          : null,
      body: RefreshIndicator(
        color: GwdColors.primaryRed,
        onRefresh: () => store.loadEvents(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, 96),
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: GwdSpace.lg),
                child: AppleStaggerItem(
                  index: next(),
                  child: _Header(
                    upcoming: upcoming.length,
                    ongoing: ongoing.length,
                    completed: completed.length,
                  ),
                ),
              ),
            ),

            // Anything live gets the full width and the brand colour. This is
            // the one moment the club genuinely needs to look at together.
            if (ongoing.isNotEmpty) ...[
              const SizedBox(height: GwdSpace.xl),
              for (final event in ongoing)
                AppleStaggerItem(
                  index: next(),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: GwdSpace.md),
                    child: _HappeningNowCard(
                      event: event,
                      onTap: () => _open(context, event),
                    ),
                  ),
                ),
            ],

            const SizedBox(height: GwdSpace.xl),
            AppleStaggerItem(
              index: next(),
              child: _GroupSwitcher(
                index: tab,
                counts: [upcoming.length, ongoing.length, completed.length],
                onChanged: (value) => setState(() => _tab = value),
              ),
            ),
            const SizedBox(height: GwdSpace.lg),

            if (!store.hasLoadedOnce)
              const SkeletonList(count: 3, height: 108)
            else if (visible.isEmpty)
              _emptyFor(context, tab, store.canCreateEvents)
            else
              for (final event in visible)
                AppleStaggerItem(
                  index: next(),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: GwdSpace.md),
                    child: EventCard(
                      event: event,
                      onTap: () => _open(context, event),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, ClubEvent event) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EventWorkspacePage(eventId: event.id)),
    );
  }

  Widget _emptyFor(BuildContext context, int tab, bool canCreate) => switch (tab) {
        1 => const EmptyState(
            icon: Icons.sensors_off_rounded,
            title: 'Nothing running right now',
            message: 'When an event starts, it will take over the top of this screen.',
          ),
        2 => const EmptyState(
            icon: Icons.history_rounded,
            title: 'No finished events yet',
            message:
                'Once an event wraps up it moves here, with its work and paperwork intact.',
          ),
        _ => EmptyState(
            icon: Icons.event_available_outlined,
            title: 'Nothing planned yet',
            message: canCreate
                ? 'Start one and the club will see it the moment you save.'
                : 'When the club plans something, it will show up here first.',
            action: canCreate
                ? PrimaryButton(
                    label: 'Plan an event',
                    icon: Icons.add_rounded,
                    expand: false,
                    onPressed: () => CreateEventFlow.open(context),
                  )
                : null,
          ),
      };
}

class _Header extends StatelessWidget {
  const _Header({
    required this.upcoming,
    required this.ongoing,
    required this.completed,
  });

  final int upcoming;
  final int ongoing;
  final int completed;

  @override
  Widget build(BuildContext context) {
    // Never "nothing on the calendar" when the club has a back catalogue —
    // that reads as a broken screen to somebody scrolling past forty events.
    final line = switch ((ongoing, upcoming)) {
      (0, 0) when completed == 0 => 'Nothing on the calendar yet',
      (0, 0) when completed == 1 => 'One event behind you',
      (0, 0) => '$completed events behind you',
      (0, 1) => 'One event being planned',
      (0, final u) => '$u events being planned',
      (1, 0) => 'One happening today',
      (final o, 0) => '$o happening today',
      (final o, final u) => '$o live · $u coming up',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Events',
            style: GwdType.largeTitle.copyWith(color: GwdColors.inkOf(context))),
        const SizedBox(height: 2),
        Text(line,
            style: GwdType.callout.copyWith(color: GwdColors.inkTertiaryOf(context))),
      ],
    );
  }
}

/// Three-way group switcher with counts.
///
/// Segments carry their count because "Completed" meaning 0 or 40 changes
/// whether it is worth tapping, and a number is cheaper to read than a tap.
class _GroupSwitcher extends StatelessWidget {
  const _GroupSwitcher({
    required this.index,
    required this.counts,
    required this.onChanged,
  });

  final int index;
  final List<int> counts;
  final ValueChanged<int> onChanged;

  static const _labels = ['Upcoming', 'Live', 'Done'];

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
          for (var i = 0; i < _labels.length; i++)
            Expanded(
              child: PressableScale(
                onTap: () => onChanged(i),
                pressedScale: 0.97,
                haptic: HapticStrength.selection,
                child: AnimatedContainer(
                  duration: AppleDuration.standard,
                  curve: AppleCurves.standard,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: i == index ? GwdColors.surfaceOf(context) : Colors.transparent,
                    borderRadius: BorderRadius.circular(GwdRadius.sm),
                    boxShadow: i == index
                        ? GwdShadow.resting(
                            Theme.of(context).brightness == Brightness.dark)
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _labels[i],
                        style: GwdType.footnote.copyWith(
                          color: i == index
                              ? GwdColors.inkOf(context)
                              : GwdColors.inkTertiaryOf(context),
                          fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      if (counts[i] > 0) ...[
                        const SizedBox(width: 5),
                        Text(
                          '${counts[i]}',
                          style: GwdType.caption.copyWith(
                            fontSize: 9.5,
                            color: i == index
                                ? GwdColors.primaryRed
                                : GwdColors.inkTertiaryOf(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The card for an event that is happening today.
///
/// Full bleed, in the event's own colour, with a live dot. Deliberately unlike
/// every other card in the app — on the day, this should be the only thing your
/// eye lands on.
class _HappeningNowCard extends StatelessWidget {
  const _HappeningNowCard({required this.event, required this.onTap});
  final ClubEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = event.bannerColor;
    return PressableScale(
      onTap: onTap,
      haptic: HapticStrength.light,
      child: Container(
        padding: const EdgeInsets.all(GwdSpace.xl),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GwdRadius.xxl),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tint, Color.lerp(tint, Colors.black, 0.34)!],
          ),
          boxShadow: GwdShadow.accent(tint),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const BreathingDot(color: Colors.white, size: 7),
                const SizedBox(width: GwdSpace.sm),
                Text(
                  'HAPPENING NOW',
                  style: GwdType.eyebrow.copyWith(color: Colors.white),
                ),
                const Spacer(),
                if (event.timeLabel.isNotEmpty)
                  Text(
                    event.timeLabel,
                    style: GwdType.footnote
                        .copyWith(color: Colors.white.withValues(alpha: 0.85)),
                  ),
              ],
            ),
            const SizedBox(height: GwdSpace.md),
            Text(
              event.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GwdType.title1.copyWith(color: Colors.white),
            ),
            if (event.venue.isNotEmpty) ...[
              const SizedBox(height: GwdSpace.xs),
              Row(
                children: [
                  Icon(Icons.place_outlined,
                      size: 13, color: Colors.white.withValues(alpha: 0.8)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      event.venue,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GwdType.callout
                          .copyWith(color: Colors.white.withValues(alpha: 0.9)),
                    ),
                  ),
                ],
              ),
            ],
            if (event.taskCount > 0) ...[
              const SizedBox(height: GwdSpace.lg),
              ClipRRect(
                borderRadius: BorderRadius.circular(GwdRadius.pill),
                child: LinearProgressIndicator(
                  value: event.progress / 100,
                  minHeight: 5,
                  backgroundColor: Colors.white.withValues(alpha: 0.24),
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
              const SizedBox(height: GwdSpace.sm),
              Text(
                '${event.taskCompleted} of ${event.taskCount} done',
                style: GwdType.footnote
                    .copyWith(color: Colors.white.withValues(alpha: 0.9)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The standard event card.
///
/// Anchored on a torn-calendar date block rather than a generic leading icon:
/// for an event the date *is* the identity, and a big tabular numeral is the
/// fastest thing on the card to read.
class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, required this.onTap});

  final ClubEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = event.bannerColor;
    final done = event.status == EventStatus.completed;

    return SurfaceCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GwdRadius.xl),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The colour spine. Three pixels of identity, so a wall of cards
              // is scannable without every one shouting.
              Container(width: 4, color: done ? GwdColors.hairlineOf(context) : tint),
              Padding(
                padding: const EdgeInsets.fromLTRB(GwdSpace.lg, GwdSpace.lg, 0, GwdSpace.lg),
                child: _DateBlock(event: event, muted: done),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      GwdSpace.lg, GwdSpace.lg, GwdSpace.lg, GwdSpace.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              event.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GwdType.title3
                                  .copyWith(color: GwdColors.inkOf(context)),
                            ),
                          ),
                          const SizedBox(width: GwdSpace.sm),
                          GwdChip(
                            label: event.status.label,
                            color: done ? GwdColors.inkTertiaryOf(context) : tint,
                            dense: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: GwdSpace.xs + 2),
                      _MetaLine(event: event),
                      if (event.taskCount > 0) ...[
                        const SizedBox(height: GwdSpace.md),
                        _ProgressLine(event: event, tint: done ? GwdColors.success : tint),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.event, required this.muted});
  final ClubEvent event;
  final bool muted;

  static const _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  @override
  Widget build(BuildContext context) {
    final tint = muted ? GwdColors.inkTertiaryOf(context) : event.bannerColor;
    return SizedBox(
      width: 46,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _months[event.date.month - 1],
            style: GwdType.eyebrow.copyWith(color: tint, fontSize: 9.5),
          ),
          const SizedBox(height: 1),
          Text(
            '${event.date.day}',
            style: GwdType.numeric.copyWith(
              fontSize: 30,
              height: 1,
              color: GwdColors.inkOf(context),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            event.whenLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GwdType.caption.copyWith(
              fontSize: 9,
              letterSpacing: 0,
              color: GwdColors.inkTertiaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.event});
  final ClubEvent event;

  @override
  Widget build(BuildContext context) {
    final bits = <String>[
      if (event.organizingDepartmentName != null) event.organizingDepartmentName!,
      if (event.venue.isNotEmpty) event.venue,
      if (event.timeLabel.isNotEmpty) event.timeLabel,
    ];
    if (bits.isEmpty) return const SizedBox.shrink();
    return Text(
      bits.join('  ·  '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GwdType.footnote.copyWith(color: GwdColors.inkSecondaryOf(context)),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.event, required this.tint});
  final ClubEvent event;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(GwdRadius.pill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: event.progress / 100),
              duration: AppleDuration.slow,
              curve: AppleCurves.enter,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 4,
                backgroundColor: GwdColors.sunkenOf(context),
                valueColor: AlwaysStoppedAnimation(tint),
              ),
            ),
          ),
        ),
        const SizedBox(width: GwdSpace.sm),
        Text(
          '${event.taskCompleted}/${event.taskCount}',
          style: GwdType.caption.copyWith(
            fontSize: 10,
            letterSpacing: 0,
            color: GwdColors.inkTertiaryOf(context),
          ),
        ),
      ],
    );
  }
}

/// An extended FAB that keeps the bracket motif rather than being a plain pill.
class _CreateEventButton extends StatelessWidget {
  const _CreateEventButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onPressed,
      haptic: HapticStrength.medium,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: GwdSpace.xl),
        decoration: BoxDecoration(
          color: GwdColors.primaryRed,
          borderRadius: BorderRadius.circular(GwdRadius.lg),
          boxShadow: GwdShadow.accent(GwdColors.primaryRed),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BracketFrame(
              color: Colors.white,
              thickness: 1.6,
              armLength: 0.46,
              padding: EdgeInsets.all(4),
              child: Icon(Icons.add_rounded, size: 16, color: Colors.white),
            ),
            const SizedBox(width: GwdSpace.md),
            Text('Plan an event',
                style: GwdType.headline.copyWith(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
