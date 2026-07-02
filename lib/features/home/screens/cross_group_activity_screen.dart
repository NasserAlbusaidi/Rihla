import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/localized_dates.dart';
import '../../activity/utils/activity_display.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/r_icon_button.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../providers/dashboard_providers.dart';

/// Full-screen cross-group activity feed (saffron travel-journal direction).
///
/// Wireframe ref: `Wireframes/Rihla/hifi/screens-shell.jsx` → `Hi_Activity()`.
/// Layout, top to bottom:
///   1. Large top bar — italic display "Activity" + ink-3 subtitle
///   2. Filter chips strip (All / Settlements / Events / Members)
///   3. Day-grouped sections, each wrapped in a card-surface card
///   4. Rows: category icon + actor/verb/description title + group context
///
/// Filter set differs from the wireframe because our activity log records
/// group-life events (settlement, event creation, member changes) rather
/// than per-expense entries. Chip labels are remapped to our type vocabulary.
class CrossGroupActivityScreen extends ConsumerStatefulWidget {
  const CrossGroupActivityScreen({super.key, this.showBack = false});

  /// Whether to render the back affordance. `false` (default) when the screen
  /// is the Activity bottom-nav tab (`BottomNavShell`); the `/activity` route
  /// builds it with `true`. Mirrors `ProfileScreen.showBack`. (#666)
  final bool showBack;

  @override
  ConsumerState<CrossGroupActivityScreen> createState() =>
      _CrossGroupActivityScreenState();
}

enum _Filter { all, settlements, events, members }

class _CrossGroupActivityScreenState
    extends ConsumerState<CrossGroupActivityScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final activityAsync = ref.watch(crossGroupActivityProvider);
    return Scaffold(
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(showBack: widget.showBack),
            const SizedBox(height: 6),
            _FilterStrip(
              current: _filter,
              onChange: (f) => setState(() => _filter = f),
            ),
            SizedBox(height: context.spacing.space8),
            Expanded(child: _buildBody(context, activityAsync)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<List<CrossGroupActivityEntry>> activityAsync,
  ) {
    return activityAsync.when(
      // #488: a layout-matched skeleton, not a blank screen, while loading.
      loading: SkeletonLoader.expenseList,
      error: (_, _) => EmptyStateView(
        icon: Iconsax.warning_2,
        title: context.l10n.activityLoadFailedTitle,
        message: context.l10n.activityLoadFailedMessage,
        onAction: () => ref.invalidate(crossGroupActivityProvider),
        actionLabel: context.l10n.commonRetry,
      ),
      data: (entries) {
        final filtered = entries
            .where((e) => _matchesFilter(e.log.type, _filter))
            .toList();
        if (filtered.isEmpty) {
          return EmptyStateView(
            icon: Iconsax.activity,
            title: entries.isEmpty
                ? context.l10n.activityNoActivityTitle
                : context.l10n.activityNoFilterTitle,
            message: entries.isEmpty
                ? context.l10n.activityCrossGroupEmptyMessage
                : context.l10n.activityNoFilterMessage,
          );
        }
        final days = _groupByDay(context, filtered, DateTime.now());
        return ListView.builder(
          // Bottom inset clears the tab-shell add-expense FAB (#364).
          padding: EdgeInsetsDirectional.fromSTEB(
            context.spacing.space20,
            context.spacing.space4,
            context.spacing.space20,
            96,
          ),
          itemCount: days.length,
          itemBuilder: (ctx, i) => Padding(
            padding: EdgeInsets.only(top: i == 0 ? 4 : 22),
            child: _DaySection(label: days[i].label, entries: days[i].entries),
          ),
        );
      },
    );
  }
}

// ──────────────────────────── Top bar

class _TopBar extends StatelessWidget {
  const _TopBar({required this.showBack});

  final bool showBack;

  // #666: top-level route entry. When /activity is the sole stack page
  // (canPop()==false), pop has nothing to return to — fall back to /home so
  // the user is never stranded. Mirrors ProfileScreen._back.
  void _back(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      if (router.canPop()) {
        router.pop();
      } else {
        router.go(AppRoutes.home);
      }
      return;
    }

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        context.spacing.space20,
        context.spacing.space8,
        context.spacing.space20,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showBack)
            RIconButton(
              variant: RIconButtonVariant.ghost,
              icon: Directionality.of(context) == TextDirection.rtl
                  ? Iconsax.arrow_right
                  : Iconsax.arrow_left,
              tooltip: context.l10n.commonBack,
              onTap: () => _back(context),
            )
          else
            const SizedBox(width: 40),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.activityTitle,
                  style: AppTypography.display(
                    fontSize: 28,
                    color: colors.textPrimary,
                    letterSpacing: -0.5,
                    height: 1.0,
                  ),
                ),
                SizedBox(height: context.spacing.space4),
                Text(
                  context.l10n.activitySubtitle,
                  style: AppTypography.sans(
                    fontSize: 13,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

// ──────────────────────────── Filter chips

class _FilterStrip extends StatelessWidget {
  const _FilterStrip({required this.current, required this.onChange});
  final _Filter current;
  final ValueChanged<_Filter> onChange;

  @override
  Widget build(BuildContext context) {
    final labels = {
      _Filter.all: context.l10n.activityFilterAll,
      _Filter.settlements: context.l10n.activityFilterSettlements,
      _Filter.events: context.l10n.activityFilterEvents,
      _Filter.members: context.l10n.activityFilterMembers,
    };
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
        children: [
          for (final entry in labels.entries) ...[
            _Chip(
              label: entry.value,
              active: current == entry.key,
              onTap: () => onChange(entry.key),
            ),
            SizedBox(width: context.spacing.space8),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? colors.textPrimary : colors.cardSoft,
          borderRadius: BorderRadius.circular(context.spacing.radiusPill),
          border: Border.all(
            color: active ? colors.textPrimary : colors.rule,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.sans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? colors.scaffoldBackground : colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────── Day section

class _DaySection extends StatelessWidget {
  const _DaySection({required this.label, required this.entries});
  final String label;
  final List<CrossGroupActivityEntry> entries;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label.toUpperCase(),
              style: AppTypography.mono(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 0.5, color: colors.rule2)),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: colors.cardSurface,
            borderRadius: BorderRadius.circular(context.spacing.radiusCard),
            boxShadow: context.shadows.raised,
          ),
          padding: EdgeInsets.symmetric(horizontal: context.spacing.space16),
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++)
                _ActivityRow(
                  entry: entries[i],
                  divider: i < entries.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────── Row

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry, required this.divider});
  final CrossGroupActivityEntry entry;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final log = entry.log;
    final description = localizedGroupActivityText(context.l10n, log);
    final amount = _coerceAmount(log.metadata['amount']);

    return InkWell(
      onTap: () => GoRouter.of(context).push('/group/${entry.groupId}'),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: context.spacing.space12),
        child: Column(
          children: [
            Row(
              // Top-align so the category icon pins to the first line when a
              // long actor + verb phrase wraps to two lines (#159).
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CategoryIcon(type: log.type),
                SizedBox(width: context.spacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: log.actorName,
                              style: AppTypography.sans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                            const TextSpan(text: ' '),
                            TextSpan(
                              text: description,
                              style: AppTypography.sans(
                                fontSize: 14,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        entry.groupName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.sans(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: context.spacing.space12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (amount != null)
                      RAmount(
                        value: amount,
                        // #382 PR-4: stamped settlement currency wins; legacy
                        // rows fall back to the entry's group currency.
                        currency: activityAmountCurrency(log, entry.currency),
                        size: 14,
                      )
                    else
                      const SizedBox.shrink(),
                    SizedBox(height: amount != null ? 3 : 0),
                    Text(
                      formatRelativeShort(context, log.timestamp),
                      style: AppTypography.mono(
                        fontSize: 10,
                        color: colors.textSecondary,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (divider) ...[
              SizedBox(height: context.spacing.space12),
              Container(height: 0.5, color: colors.rule),
            ],
          ],
        ),
      ),
    );
  }

  /// Settlement amounts arrive as a stringified Decimal
  /// (`GroupSettleUpScreen.logGroupEvent` writes `amount.toString()`) or, for
  /// some logs, as a num. Coerce both to a `Decimal` WITHOUT forcing OMR's 3dp
  /// (#380) — [RAmount] applies the entry's own currency precision. Mirrors
  /// `GroupActivityScreen._coerceAmount`.
  Decimal? _coerceAmount(Object? raw) {
    if (raw == null) return null;
    if (raw is num) return Decimal.parse(raw.toString());
    if (raw is String) return Decimal.tryParse(raw);
    return null;
  }
}

class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (bg, fg, icon) = switch (type) {
      'group_settlement' => (
        colors.cardSoft,
        colors.success,
        // Money/wallet glyph, not a navigation chevron (#160) — matches the
        // group activity feed and the settle-up total chip.
        Iconsax.wallet_3,
      ),
      'event_created' => (
        colors.saffronSoft,
        colors.primaryDark,
        Iconsax.calendar_1,
      ),
      'event_deleted' => (
        colors.cardSoft,
        colors.textSecondary,
        Iconsax.calendar_remove,
      ),
      'member_joined' => (colors.cardSoft, colors.cat2, Iconsax.user_add),
      'member_left' => (
        colors.cardSoft,
        colors.textSecondary,
        Iconsax.user_minus,
      ),
      _ => (colors.cardSoft, colors.textSecondary, Iconsax.activity),
    };
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.rule, width: 0.5),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: fg),
    );
  }
}

// ──────────────────────────── Helpers

bool _matchesFilter(String type, _Filter f) {
  return switch (f) {
    _Filter.all => true,
    _Filter.settlements => type == 'group_settlement',
    _Filter.events => type == 'event_created' || type == 'event_deleted',
    _Filter.members => type == 'member_joined' || type == 'member_left',
  };
}

class _DayGroup {
  const _DayGroup({required this.label, required this.entries});
  final String label;
  final List<CrossGroupActivityEntry> entries;
}

List<_DayGroup> _groupByDay(
  BuildContext context,
  List<CrossGroupActivityEntry> entries,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final groups = <String, List<CrossGroupActivityEntry>>{};
  final order = <String>[];

  for (final e in entries) {
    final ts = e.log.timestamp;
    final day = DateTime(ts.year, ts.month, ts.day);
    final diff = today.difference(day).inDays;
    final label = diff == 0
        ? context.l10n.timelineToday
        : diff == 1
        ? context.l10n.timelineYesterday
        : formatShortMonthDay(context, ts);
    if (!groups.containsKey(label)) {
      groups[label] = [];
      order.add(label);
    }
    groups[label]!.add(e);
  }
  return [
    for (final label in order) _DayGroup(label: label, entries: groups[label]!),
  ];
}
