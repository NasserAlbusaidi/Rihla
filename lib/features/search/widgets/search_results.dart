import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/directional_icon.dart';
import '../../../shared/widgets/section_header.dart';
import '../../events/models/event_model.dart';
import '../../events/providers/event_provider.dart';
import '../../groups/models/group_model.dart';
import '../../groups/providers/group_provider.dart';
import '../../home/providers/active_journeys_provider.dart';
import '../keys/search_keys.dart';
import '../utils/search_match.dart';

/// Results body for [SearchScreen] (kept in its own file/widget so the
/// per-group [groupEventsProvider] watch — the R1 data-source fix — sits next
/// to the match/render logic it drives).
///
/// **Data source (Gate R1 P1 fix):** iterates `userGroupsProvider`; per group
/// watches `groupEventsProvider(gid)` — `EventService.watchGroupEvents` filters
/// only `isDeleted`, so CLOSED events are kept (a concluded trip must stay
/// findable). NEVER watch expense/settlement providers here — full expense
/// search is Option C (deferred, needs a server index).
///
/// **Listener math:** the always-mounted home tab already holds
/// `groupEventsProvider(gid)` live for every group (via `activeJourneysProvider`
/// / `addExpenseTargetsProvider`), so on the warm path this adds zero
/// incremental Firestore listeners; on a cold `/search` deep link it's the
/// sole watcher — O(G) event-list listeners, bounded and disposed on pop.
class SearchResults extends ConsumerWidget {
  const SearchResults({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trimmed = query.trim();
    // Empty/absent q (#1012, reversing the PR-5b blank-panel pin): show muted
    // pre-query guidance — a search glyph + the scope line — so the v1 search
    // scope (past events included) is honest before the first keystroke,
    // instead of a blank panel. Still no results section / no empty-state.
    if (trimmed.isEmpty) return const _PreQueryGuidance();

    final groups = ref.watch(userGroupsProvider).valueOrNull ?? const <Group>[];
    final matchedGroups = groups
        .where((group) => matchesSearchQuery(group.name, trimmed))
        .toList();

    final eventHits = <({Event event, String groupName})>[];
    for (final group in groups) {
      final events = ref.watch(groupEventsProvider(group.id)).valueOrNull;
      if (events == null) continue;
      for (final event in events) {
        if (event.isDeleted) continue;
        if (matchesSearchQuery(event.name, trimmed)) {
          eventHits.add((event: event, groupName: group.name));
        }
      }
    }

    if (matchedGroups.isEmpty && eventHits.isEmpty) {
      return const _NoMatches();
    }

    final l10n = context.l10n;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        context.spacing.space16,
        0,
        context.spacing.space16,
        context.spacing.space16,
      ),
      children: [
        Padding(
          key: SearchKeys.scopeLabel,
          padding: EdgeInsets.symmetric(vertical: context.spacing.space8),
          child: Text(
            l10n.searchScopeLabel,
            style: AppTypography.caption(
              context,
              fontSize: 11,
              color: context.colors.textSecondary,
              letterSpacing: 1.0,
            ),
          ),
        ),
        if (matchedGroups.isNotEmpty) ...[
          SectionHeader(
            title: l10n.searchSectionGroups,
            padding: EdgeInsets.zero,
          ),
          SizedBox(height: context.spacing.space8),
          for (final group in matchedGroups) ...[
            _GroupRow(group: group),
            SizedBox(height: context.spacing.space8),
          ],
          SizedBox(height: context.spacing.space8),
        ],
        if (eventHits.isNotEmpty) ...[
          SectionHeader(
            title: l10n.searchSectionEvents,
            padding: EdgeInsets.zero,
          ),
          SizedBox(height: context.spacing.space8),
          for (final hit in eventHits) ...[
            _EventRow(event: hit.event, groupName: hit.groupName),
            SizedBox(height: context.spacing.space8),
          ],
        ],
      ],
    );
  }
}

/// A matched group row (v1: group name ONLY — the member/event count idea
/// was dropped at Gate R3 as an un-keyed pluralized string).
///
/// Tap forwards via the #900 §2 smart-forward CONTRACT verbatim (spec:
/// `home_screen.dart:196-210`) — duplicated inline per spec ("extracting a
/// shared helper is optional, NOT required").
class _GroupRow extends ConsumerWidget {
  const _GroupRow({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targetsAsync = ref.watch(addExpenseTargetsProvider);
    return _ResultRow(
      icon: Iconsax.people,
      title: group.name,
      onTap: () {
        HapticService.lightClick();
        final gid = group.id;
        final targets = targetsAsync.valueOrNull ?? AddExpenseTargets.empty;
        final open = targets.openByGroup[gid];
        final soleEvent =
            (targets.allResolved && open != null && open.length == 1)
            ? open.single
            : null;
        if (soleEvent != null) {
          // #996: push the /group/:gid ancestor FIRST (imperative push does
          // not materialize ancestors) so Back walks hub → overview → these
          // results with the query intact.
          context.push('/group/$gid');
          context.push('/group/$gid/event/${soleEvent.eventId}');
        } else {
          context.push('/group/$gid');
        }
      },
    );
  }
}

/// A matched event row — name + PARENT GROUP subtitle (cross-group
/// disambiguation, Gate R2 rubric fix) + a compact "Ended" pill when closed.
/// Works for closed events: the hub renders the Recap tab whenever
/// `event.isClosed`.
class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.groupName});

  final Event event;
  final String groupName;

  @override
  Widget build(BuildContext context) {
    return _ResultRow(
      icon: Iconsax.calendar_1,
      title: event.name,
      subtitle: groupName,
      trailingBadge: event.isClosed ? const _EndedBadge() : null,
      onTap: () {
        HapticService.lightClick();
        // Deliberately SINGLE push (#996): an event-intent tap — Back
        // returns to these results, not to the group overview. Don't "fix"
        // this into the group-row double-push.
        context.push('/group/${event.groupId}/event/${event.id}');
      },
    );
  }
}

/// Compact lifecycle pill echoing the ledger SETTLED badge's *container idiom*
/// (padding + radiusPill + mono caption) — NOT its "settled" balance-state
/// styling/copy. `event.isClosed` is a lifecycle state, never a balance state.
class _EndedBadge extends StatelessWidget {
  const _EndedBadge();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 10,
        vertical: context.spacing.space4,
      ),
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(context.spacing.radiusPill),
      ),
      child: Text(
        context.l10n.searchEventEnded,
        style: AppTypography.caption(
          context,
          fontSize: 10,
          color: colors.textSecondary,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailingBadge,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailingBadge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: context.spacing.space12,
              vertical: context.spacing.space12,
            ),
            decoration: BoxDecoration(
              color: colors.cardSurface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: context.shadows.flat,
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.inputFill,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: colors.textSecondary),
                ),
                SizedBox(width: context.spacing.space12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.sans(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailingBadge != null) ...[
                  SizedBox(width: context.spacing.space8),
                  trailingBadge!,
                ],
                SizedBox(width: context.spacing.space8),
                DirectionalIcon(
                  Iconsax.arrow_right_3,
                  size: 16,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// #1012: pre-query guidance shown before the first keystroke. Mirrors the
/// static [_NoMatches] structure (Center > Padding > Column, no animation /
/// no ticker — do NOT reuse EmptyStateView, whose flutter_animate entrance
/// breaks widget-test teardown). Reuses the existing `searchScopeLabel` string
/// (already localized EN + AR) so the v1 scope is honest before any results.
class _PreQueryGuidance extends StatelessWidget {
  const _PreQueryGuidance();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      key: SearchKeys.preQueryGuidance,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space32,
          vertical: context.spacing.space16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Iconsax.search_normal, size: 32, color: colors.textSecondary),
            SizedBox(height: context.spacing.space12),
            Text(
              context.l10n.searchScopeLabel,
              textAlign: TextAlign.center,
              style: AppTypography.sans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      key: SearchKeys.emptyState,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space32,
          vertical: context.spacing.space16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Iconsax.search_normal, size: 32, color: colors.textSecondary),
            SizedBox(height: context.spacing.space12),
            Text(
              context.l10n.searchEmpty,
              textAlign: TextAlign.center,
              style: AppTypography.sans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
