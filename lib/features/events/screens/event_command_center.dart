import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/localized_dates.dart';
import '../../../shared/widgets/cover_art.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/r_icon_button.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../../groups/models/group_member_model.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../../core/constants/supported_currencies.dart';
import '../../groups/providers/group_provider.dart';
import '../../groups/services/member_name_resolver.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../ledger/providers/ledger_view_provider.dart';
import '../keys/event_keys.dart';
import '../models/event_model.dart';
import '../providers/event_provider.dart';
import '../utils/event_display.dart';

/// Per-event hub — V5R "dots" direction.
///
/// Layout, top to bottom:
///   1. Cover header (148px + status bar) with floating chrome, eyebrow,
///      italic title, and a half-overhanging Day-of-N pill (live trips only).
///   2. Balance hero — 4 states:
///        • youOwed   ("You are owed", sage, per-row breakdown)
///        • youOwe    ("You owe",      rust, per-row breakdown)
///        • settled   ("All settled",  italic display, sage)
///        • empty     ("Nothing to settle yet")
///      Single primary CTA `+ Add expense`.
///   3. Ledger summary strip — "Trip total · N expenses · Ledger →".
///      Hidden in the empty state.
///   4. Recent expenses — 3 rows, or a dashed CTA in the empty state.
///   5. Roster strip — horizontal cards with a 6px sage/rust dot beneath
///      each person's name (no dot for settled or self).
///
/// Kept for deep-link compatibility; current event cards route straight to
/// the ledger surface.
class EventCommandCenter extends ConsumerWidget {
  const EventCommandCenter({
    super.key,
    required this.groupId,
    required this.eventId,
  });

  final String groupId;
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(
      eventDetailProvider((groupId: groupId, eventId: eventId)),
    );
    final groupAsync = ref.watch(groupDetailProvider(groupId));

    return Scaffold(
      key: EventKeys.screen,
      backgroundColor: context.colors.scaffoldBackground,
      body: eventAsync.when(
        loading: () => const _LoadingState(),
        error: (_, _) => _ErrorState(
          onRetry: () => ref.invalidate(
            eventDetailProvider((groupId: groupId, eventId: eventId)),
          ),
        ),
        data: (event) {
          if (event == null) return const _NotFoundState();
          final group = groupAsync.valueOrNull;
          return _Content(
            event: event,
            groupId: groupId,
            eventId: eventId,
            groupName: group?.name,
          );
        },
      ),
    );
  }
}

// ──────────────────────────── Content

class _Content extends ConsumerWidget {
  const _Content({
    required this.event,
    required this.groupId,
    required this.eventId,
    required this.groupName,
  });

  final Event event;
  final String groupId;
  final String eventId;
  final String? groupName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventRef = (groupId: groupId, eventId: eventId);
    final currentUid = ref.watch(currentUserIdProvider);
    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    // #631: share the ledger's memoized balance pass instead of running a
    // second `calculateBalances` (via the now-deleted `eventBalancesProvider`)
    // plus an inline `disambiguateEventScoped`/`calculateTotalExpensesByCurrency`
    // on every rebuild. `ledgerViewProvider` is keyed by EventRef alone (watches
    // `eventDetailProvider` internally), so it also drops the same-id `Event`
    // staleness the old `({eventRef, event})` key carried. `eventRecapProvider`
    // already reuses this provider for the same reason.
    final view = ref.watch(ledgerViewProvider(eventRef));
    // Still needed for `_RecentRow`'s departed-payer `resolveEventScoped`
    // fallback — now just a cheap list read, no inline calc.
    final groupMembers =
        ref.watch(groupMembersProvider(groupId)).valueOrNull ?? [];

    final expenses = expensesAsync.valueOrNull ?? const <Expense>[];
    // #382 PR-5: hero lines, breakdown rows, and roster dots walk EVERY
    // currency bucket — currencies never net against each other, so each
    // bucket renders its own lines and "settled" means settled in all of them.
    final buckets = view.balances;
    // #289: distinguish same-named LIVE members across the hub (roster,
    // breakdown, recent rows) while still labelling departed ones.
    final participantDisplayNames = view.rosterDisplayNames;

    final totals = view.eventTotal;

    final myLines = nonZeroNetsGccFirst(myNetByCurrency(buckets, currentUid));

    final state = _resolveState(
      hasExpenses: expenses.isNotEmpty,
      lines: myLines,
    );

    final breakdown =
        (state == _HubState.youOwed ||
            state == _HubState.youOwe ||
            state == _HubState.mixed)
        ? _breakdownFor(
            currentUid!,
            buckets,
            participantDisplayNames,
            context.l10n.activitySomeone,
          )
        : const <_BreakdownEntry>[];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _CoverHeader(
            event: event,
            groupName: groupName,
            onSettings: () {
              HapticService.lightClick();
              GoRouter.of(
                context,
              ).push('/group/$groupId/event/$eventId/settings');
            },
            // Recap entry only once there's something to wrap up (#202 Slice 1).
            onRecap: expenses.isEmpty
                ? null
                : () => GoRouter.of(
                    context,
                  ).push('/group/$groupId/event/$eventId/recap'),
          ),
        ),
        const SliverToBoxAdapter(child: OfflineBanner()),
        SliverPadding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 28, 20, 0),
          sliver: SliverToBoxAdapter(
            child: _BalanceHero(
              state: state,
              lines: myLines,
              breakdown: breakdown,
              onAddExpense: () {
                HapticService.lightClick();
                GoRouter.of(
                  context,
                ).push('/group/$groupId/event/$eventId/ledger/add');
              },
              onSettleWith: (otherUid) {
                HapticService.lightClick();
                GoRouter.of(context).push(
                  '/group/$groupId/event/$eventId/ledger/settle-up'
                  '?memberId=$otherUid',
                );
              },
            ),
          ),
        ),
        if (state != _HubState.empty)
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 0),
            sliver: SliverToBoxAdapter(
              child: _LedgerSummaryStrip(
                totals: [
                  for (final c in sortedGccFirst(totals.keys))
                    (currency: c, total: totals[c]!),
                ],
                count: expenses.length,
                onTap: () {
                  HapticService.lightClick();
                  GoRouter.of(
                    context,
                  ).push('/group/$groupId/event/$eventId/ledger');
                },
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 24, 20, 0),
          sliver: SliverToBoxAdapter(
            child: _RecentExpensesSection(
              expenses: expenses,
              currentUid: currentUid,
              event: event,
              groupMembers: groupMembers,
              participantDisplayNames: participantDisplayNames,
              onSeeAll: () {
                HapticService.lightClick();
                GoRouter.of(
                  context,
                ).push('/group/$groupId/event/$eventId/ledger');
              },
              onAddFirst: () {
                HapticService.lightClick();
                GoRouter.of(
                  context,
                ).push('/group/$groupId/event/$eventId/ledger/add');
              },
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsetsDirectional.fromSTEB(0, 24, 0, 32),
          sliver: SliverToBoxAdapter(
            child: _RosterStrip(
              event: event,
              participantDisplayNames: participantDisplayNames,
              buckets: buckets,
              currentUid: currentUid,
              isEmpty: state == _HubState.empty,
              onPersonTap: (uid) {
                HapticService.lightClick();
                GoRouter.of(context).push(
                  '/group/$groupId/event/$eventId/ledger/settle-up'
                  '?memberId=$uid',
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────── State machine

enum _HubState { empty, settled, youOwed, youOwe, mixed }

/// Settled ⇔ EVERY currency bucket nets exactly zero. Deliberate threshold
/// change (#382 PR-5, L13): this replaces `UserBalance.isSettled`'s 0.001
/// tolerance with the helpers' exact-zero predicate — the hub's settled gate
/// TIGHTENS, so a sub-tolerance residual renders instead of silently reading
/// as settled (the calculator closes remainders, so one shouldn't exist).
/// Mixed signs across buckets have no honest single overline → [_HubState.mixed].
_HubState _resolveState({
  required bool hasExpenses,
  required List<({String currency, Decimal net})> lines,
}) {
  if (!hasExpenses) return _HubState.empty;
  if (lines.isEmpty) return _HubState.settled;
  if (lines.every((l) => l.net > Decimal.zero)) return _HubState.youOwed;
  if (lines.every((l) => l.net < Decimal.zero)) return _HubState.youOwe;
  return _HubState.mixed;
}

class _BreakdownEntry {
  const _BreakdownEntry({
    required this.otherUid,
    required this.otherName,
    required this.amount,
    required this.currency,
    required this.isOwed,
  });

  final String otherUid;
  final String otherName;
  final Decimal amount;
  final String currency;
  final bool isOwed;
}

List<_BreakdownEntry> _breakdownFor(
  String currentUid,
  Map<String, List<UserBalance>> buckets,
  Map<String, String> names,
  String fallbackName,
) {
  final entries = <_BreakdownEntry>[];
  // #382 PR-5: one optimizer pass per currency bucket, rows merged GCC-first —
  // currencies never net, so each bucket suggests its own transfers.
  for (final currency in sortedGccFirst(buckets.keys)) {
    final settlements = BalanceCalculator.calculateOptimalSettlements(
      balances: buckets[currency]!,
      userNames: names,
    );
    for (final s in settlements) {
      final from = s['fromUserId'] as String;
      final to = s['toUserId'] as String;
      final amount = s['amount'] as Decimal;
      if (to == currentUid) {
        entries.add(
          _BreakdownEntry(
            otherUid: from,
            otherName:
                (s['fromUserName'] as String?) ?? names[from] ?? fallbackName,
            amount: amount,
            currency: currency,
            isOwed: true,
          ),
        );
      } else if (from == currentUid) {
        entries.add(
          _BreakdownEntry(
            otherUid: to,
            otherName:
                (s['toUserName'] as String?) ?? names[to] ?? fallbackName,
            amount: amount,
            currency: currency,
            isOwed: false,
          ),
        );
      }
    }
  }
  return entries;
}

// ──────────────────────────── Balance hero

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({
    required this.state,
    required this.lines,
    required this.breakdown,
    required this.onAddExpense,
    required this.onSettleWith,
  });

  final _HubState state;
  final List<({String currency, Decimal net})> lines;
  final List<_BreakdownEntry> breakdown;
  final VoidCallback onAddExpense;
  final void Function(String otherUid) onSettleWith;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: EventKeys.spendingHero,
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(context.spacing.radiusCard),
        border: Border.all(color: colors.border),
        boxShadow: context.shadows.raised,
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state == _HubState.youOwed ||
              state == _HubState.youOwe ||
              state == _HubState.mixed)
            _BalanceWithBreakdown(
              state: state,
              lines: lines,
              breakdown: breakdown,
              onSettleWith: onSettleWith,
            )
          else
            _BalanceQuiet(isSettled: state == _HubState.settled),
          const SizedBox(height: 18),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              key: EventKeys.addExpenseChip,
              onPressed: onAddExpense,
              icon: const Icon(Iconsax.add, size: 18),
              label: Text(context.l10n.eventAddExpense),
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.textOnPrimary,
                textStyle: AppTypography.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.22,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceWithBreakdown extends StatelessWidget {
  const _BalanceWithBreakdown({
    required this.state,
    required this.lines,
    required this.breakdown,
    required this.onSettleWith,
  });

  final _HubState state;
  final List<({String currency, Decimal net})> lines;
  final List<_BreakdownEntry> breakdown;
  final void Function(String otherUid) onSettleWith;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isOwed = state == _HubState.youOwed;
    final isUniform = state != _HubState.mixed;
    // L7: the tri-state overline/accent only has an honest answer when every
    // line shares one sign; mixed → per-line tones self-explain.
    final accent = isUniform ? (isOwed ? colors.success : colors.error) : null;
    final accentText = isOwed ? colors.successText : colors.errorText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (isUniform)
              _Overline(
                label: isOwed
                    ? context.l10n.eventYouAreOwed
                    : context.l10n.eventYouOwe,
                color: accentText,
              ),
            _Overline(label: context.l10n.eventYourBalance),
          ],
        ),
        SizedBox(height: context.spacing.space8),
        if (lines.length == 1)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              RAmount(
                value: lines.first.net.abs(),
                currency: lines.first.currency,
                size: 40,
                weight: FontWeight.w800,
                sign: true,
                tone: isOwed ? AmountTone.sage : AmountTone.rust,
              ),
              const Spacer(),
              if (accent != null)
                Container(width: 56, height: 2, color: accent),
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < lines.length; i++)
                      Padding(
                        padding: EdgeInsetsDirectional.only(
                          top: i == 0 ? 0 : 4,
                        ),
                        child: RAmount(
                          value: lines[i].net,
                          currency: lines[i].currency,
                          size: 28,
                          weight: FontWeight.w800,
                          sign: true,
                          tone: lines[i].net > Decimal.zero
                              ? AmountTone.sage
                              : AmountTone.rust,
                        ),
                      ),
                  ],
                ),
              ),
              if (accent != null)
                Container(width: 56, height: 2, color: accent),
            ],
          ),
        if (breakdown.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.rule, width: 0.5)),
            ),
            padding: EdgeInsets.only(top: context.spacing.space4),
            child: Column(
              children: [
                for (final entry in breakdown)
                  _BreakdownRow(
                    entry: entry,
                    onTap: () => onSettleWith(entry.otherUid),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _BalanceQuiet extends StatelessWidget {
  const _BalanceQuiet({required this.isSettled});

  final bool isSettled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Overline(label: context.l10n.eventYourBalance),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                isSettled
                    ? context.l10n.eventAllSettled
                    : context.l10n.eventNothingToSettleYet,
                style: AppTypography.display(
                  fontSize: 28,
                  color: isSettled ? colors.successText : colors.textSecondary,
                  height: 1.05,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            if (isSettled)
              Container(width: 56, height: 2, color: colors.success),
          ],
        ),
        SizedBox(height: context.spacing.space8),
        Text(
          isSettled
              ? context.l10n.eventEveryoneSquare
              : context.l10n.eventAddFirstExpenseHint,
          style: AppTypography.sans(fontSize: 12, color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.entry, required this.onTap});

  final _BreakdownEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final verb = entry.isOwed
        ? context.l10n.eventBreakdownOwesYou
        : context.l10n.eventBreakdownYouOwe;
    // #289: keep the ` (#…)` discriminator alive through the first-name collapse.
    final firstName = MemberNameResolver.compactDisambiguated(entry.otherName);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.spacing.space12,
            vertical: 10,
          ),
          child: Row(
            children: [
              RAvatar(name: entry.otherName, size: 32),
              SizedBox(width: context.spacing.space12),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: AppTypography.sans(
                      fontSize: 13.5,
                      color: colors.textPrimary,
                      height: 1.3,
                    ),
                    children: [
                      TextSpan(
                        text: firstName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: ' · $verb',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              RAmount(
                value: entry.amount,
                currency: entry.currency,
                size: 14,
                weight: FontWeight.w700,
                tone: entry.isOwed ? AmountTone.sage : AmountTone.rust,
              ),
              const SizedBox(width: 2),
              Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left
                    : Icons.chevron_right,
                size: 18,
                // textMuted-decorative-justified: disclosure chevron is purely decorative affordance
                color: colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────── Ledger summary strip

class _LedgerSummaryStrip extends StatelessWidget {
  const _LedgerSummaryStrip({
    required this.totals,
    required this.count,
    required this.onTap,
  });

  /// Per-currency totals, pre-sorted by the caller (GCC-first, #382 PR-1).
  /// A single-currency event renders exactly as the old flat total did.
  final List<({String currency, Decimal total})> totals;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.cardSoft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: EventKeys.ledgerCard,
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.rule),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Overline(label: context.l10n.eventTripTotal),
                    SizedBox(height: context.spacing.space4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: context.spacing.space8,
                      runSpacing: 2,
                      children: [
                        for (final t in totals)
                          RAmount(
                            value: t.total,
                            currency: t.currency,
                            size: 20,
                            weight: FontWeight.w800,
                          ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            context.l10n.eventExpenseCountInline(count),
                            style: AppTypography.sans(
                              fontSize: 12,
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                context.l10n.eventLedgerLink,
                style: AppTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────── Recent expenses

class _RecentExpensesSection extends StatelessWidget {
  const _RecentExpensesSection({
    required this.expenses,
    required this.currentUid,
    required this.event,
    required this.groupMembers,
    required this.participantDisplayNames,
    required this.onSeeAll,
    required this.onAddFirst,
  });

  final List<Expense> expenses;
  final String? currentUid;
  final Event event;
  final List<GroupMember> groupMembers;
  final Map<String, String> participantDisplayNames;
  final VoidCallback onSeeAll;
  final VoidCallback onAddFirst;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isEmpty = expenses.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            _Overline(label: context.l10n.eventRecent),
            const Spacer(),
            if (!isEmpty)
              InkWell(
                onTap: onSeeAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    context.l10n.eventSeeAll,
                    style: AppTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (isEmpty)
          _AddFirstExpenseCard(onTap: onAddFirst)
        else
          _RecentList(
            expenses: expenses.take(3).toList(),
            currentUid: currentUid,
            event: event,
            groupMembers: groupMembers,
            participantDisplayNames: participantDisplayNames,
          ),
      ],
    );
  }
}

class _RecentList extends StatelessWidget {
  const _RecentList({
    required this.expenses,
    required this.currentUid,
    required this.event,
    required this.groupMembers,
    required this.participantDisplayNames,
  });

  final List<Expense> expenses;
  final String? currentUid;
  final Event event;
  final List<GroupMember> groupMembers;
  final Map<String, String> participantDisplayNames;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
        boxShadow: context.shadows.raised,
      ),
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space16),
      child: Column(
        children: [
          for (var i = 0; i < expenses.length; i++)
            _RecentRow(
              expense: expenses[i],
              currentUid: currentUid,
              event: event,
              groupMembers: groupMembers,
              participantDisplayNames: participantDisplayNames,
              divider: i < expenses.length - 1,
            ),
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.expense,
    required this.currentUid,
    required this.event,
    required this.groupMembers,
    required this.participantDisplayNames,
    required this.divider,
  });

  final Expense expense;
  final String? currentUid;
  final Event event;
  final List<GroupMember> groupMembers;
  // #289: disambiguated uid → name map shared across the hub.
  final Map<String, String> participantDisplayNames;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final payerName = expense.payerParticipantId == currentUid
        ? context.l10n.eventYouPaid
        : context.l10n.eventPaidByName(_compactPayerName());

    return Container(
      decoration: BoxDecoration(
        border: divider
            ? Border(bottom: BorderSide(color: colors.rule, width: 0.5))
            : null,
      ),
      padding: EdgeInsets.symmetric(vertical: context.spacing.space12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.cardSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.rule),
            ),
            child: Icon(
              Iconsax.wallet_3,
              size: 16,
              color: colors.textSecondary,
            ),
          ),
          SizedBox(width: context.spacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (expense.description?.isNotEmpty ?? false)
                      ? expense.description!
                      : (expense.categoryName ??
                            context.l10n.ledgerExpenseFallback),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$payerName · ${_relativeAge(context, expense.createdAt)}',
                  style: AppTypography.sans(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: context.spacing.space8),
          Text(
            AppFormatters.formatCurrency(expense.amount, expense.currency),
            style: AppTypography.mono(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  String _compactPayerName() {
    // #289: prefer the disambiguated hub map (live members, with ` (#…)` on a
    // name collision); fall back to the former-aware resolver for a departed
    // payer not in the live set, preserving the persisted payerName.
    final disambiguated = participantDisplayNames[expense.payerParticipantId];
    if (disambiguated != null) {
      return MemberNameResolver.compactDisambiguated(disambiguated);
    }
    final display = MemberNameResolver.resolveEventScoped(
      uid: expense.payerParticipantId,
      event: event,
      members: groupMembers,
      fallbackName: expense.payerName,
    );
    if (display.rawName == MemberNameResolver.formerMemberLiteral) {
      return display.rawName;
    }
    return MemberNameResolver.compactDisambiguated(
      MemberNameResolver.format(display),
    );
  }
}

class _AddFirstExpenseCard extends StatelessWidget {
  const _AddFirstExpenseCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.cardSurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: _DashedBorderBox(
          radius: 16,
          // textMuted-decorative-justified: dashed-border stroke is decorative, not text contrast
          color: colors.textMuted,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.selectionFill,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Iconsax.add, size: 18, color: colors.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.eventAddFirstExpenseTitle,
                        style: AppTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.eventAddFirstExpenseBody,
                        style: AppTypography.sans(
                          fontSize: 12,
                          color: colors.textSecondary,
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
    );
  }
}

class _DashedBorderBox extends StatelessWidget {
  const _DashedBorderBox({
    required this.child,
    required this.radius,
    required this.color,
  });

  final Widget child;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: color.withValues(alpha: 0.55),
        radius: radius,
      ),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rect);
    const dashWidth = 5.0;
    const dashGap = 4.0;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

// ──────────────────────────── Roster strip

class _RosterStrip extends StatelessWidget {
  const _RosterStrip({
    required this.event,
    required this.participantDisplayNames,
    required this.buckets,
    required this.currentUid,
    required this.isEmpty,
    required this.onPersonTap,
  });

  final Event event;
  final Map<String, String> participantDisplayNames;
  final Map<String, List<UserBalance>> buckets;
  final String? currentUid;
  final bool isEmpty;
  final void Function(String uid) onPersonTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final count = event.participantIds.length;
    // #630: one O(C×M) pivot for the whole strip; the itemBuilder indexes it in
    // O(1) instead of re-running a per-row O(C×M) myNetByCurrency pivot.
    final netsByUid = pivotNetsByParticipant(buckets);

    final othersCount =
        currentUid != null && event.participantIds.contains(currentUid)
        ? count - 1
        : count;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
          child: _Overline(label: context.l10n.eventPeopleOverline(count)),
        ),
        if (isEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
            child: RichText(
              text: TextSpan(
                style: AppTypography.sans(
                  fontSize: 13,
                  color: colors.textSecondary,
                ),
                children: [
                  TextSpan(
                    text: context.l10n.eventSplittingBetweenYouAndOthers(
                      othersCount,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          height: 124,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
            itemCount: event.participantIds.length,
            separatorBuilder: (_, _) => SizedBox(width: context.spacing.space8),
            itemBuilder: (context, i) {
              final uid = event.participantIds[i];
              final isMe = uid == currentUid;
              final name =
                  participantDisplayNames[uid] ?? context.l10n.activitySomeone;
              // #382 PR-5: dot iff ANY bucket nets non-zero for this person;
              // with several non-zero buckets the GCC-first one decides the
              // color — deterministic, aligned with the hero's line order.
              final lines = nonZeroNetsGccFirst(netsByUid[uid] ?? const {});
              return _RosterPersonCard(
                name: name,
                isMe: isMe,
                dotOwed: lines.isEmpty ? null : lines.first.net > Decimal.zero,
                showDot: !isMe && !isEmpty,
                onTap: () => onPersonTap(uid),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RosterPersonCard extends StatelessWidget {
  const _RosterPersonCard({
    required this.name,
    required this.isMe,
    required this.dotOwed,
    required this.showDot,
    required this.onTap,
  });

  final String name;
  final bool isMe;

  /// Direction of the person's GCC-first non-zero bucket: true = owed (sage),
  /// false = owes (rust), null = settled in every bucket (no dot).
  final bool? dotOwed;
  final bool showDot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // #289: keep the ` (#…)` discriminator alive through the first-name collapse.
    final short = MemberNameResolver.compactDisambiguated(name);
    final dotColor = switch (dotOwed) {
      true => colors.success,
      false => colors.error,
      null => null,
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 88,
        decoration: BoxDecoration(
          color: colors.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isMe ? colors.textPrimary : colors.border,
            width: isMe ? 1.5 : 1,
          ),
          boxShadow: context.shadows.raised,
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(8, 12, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RAvatar(name: name, size: 40),
            SizedBox(height: context.spacing.space8),
            Text(
              isMe ? context.l10n.eventYou : short,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.sans(
                fontSize: 12,
                fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
            SizedBox(height: context.spacing.space8),
            SizedBox(
              height: context.spacing.space8,
              child: showDot && dotColor != null
                  ? Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────── Overline helper

class _Overline extends StatelessWidget {
  const _Overline({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Text(
      label.toUpperCase(),
      style: AppTypography.sans(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: color ?? colors.textSecondary,
      ),
    );
  }
}

// ──────────────────────────── Cover header

class _CoverHeader extends StatelessWidget {
  const _CoverHeader({
    required this.event,
    required this.groupName,
    required this.onSettings,
    this.onRecap,
  });

  final Event event;
  final String? groupName;
  final VoidCallback onSettings;

  /// Recap entry (#202 Slice 1). Null ⇒ hidden (no expenses to wrap up yet).
  final VoidCallback? onRecap;

  @override
  Widget build(BuildContext context) {
    final statusBar = MediaQuery.of(context).padding.top;
    final dateRange = _formatDateRange(context, event.startDate, event.endDate);
    final dayBadge = _formatDayBadge(context, event.startDate, event.endDate);
    final captionParts = <String>[
      event.type.localizedShortLabel(context.l10n),
      ?dateRange,
      if (groupName != null && groupName!.isNotEmpty) groupName!,
    ];

    return SizedBox(
      height: 148 + statusBar,
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          // #626: cache the procedural cover raster — this header lives in a
          // SliverToBoxAdapter (no automatic per-child RepaintBoundary).
          RepaintBoundary(child: CoverArt.forEventType(event.type)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  context.colors.textPrimary.withValues(alpha: 0.55),
                ],
                stops: const [0.35, 1.0],
              ),
            ),
          ),
          Positioned.directional(
            textDirection: Directionality.of(context),
            top: statusBar + 8,
            start: 12,
            end: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                RIconButton(
                  icon: Directionality.of(context) == TextDirection.rtl
                      ? Iconsax.arrow_right
                      : Iconsax.arrow_left,
                  onTap: () {
                    HapticService.lightClick();
                    if (GoRouter.of(context).canPop()) {
                      GoRouter.of(context).pop();
                    }
                  },
                ),
                Row(
                  children: [
                    if (onRecap != null) ...[
                      RIconButton(
                        key: EventKeys.recapButton,
                        icon: Iconsax.cup,
                        tooltip: context.l10n.recapButtonTooltip,
                        onTap: () {
                          HapticService.lightClick();
                          onRecap!();
                        },
                      ),
                      const SizedBox(width: 6),
                    ],
                    RIconButton(
                      key: EventKeys.settingsButton,
                      icon: Iconsax.setting_2,
                      onTap: onSettings,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned.directional(
            textDirection: Directionality.of(context),
            start: 20,
            end: 20,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  captionParts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.mono(
                    fontSize: 9,
                    color: Colors.white.withValues(alpha: 0.85),
                    letterSpacing: 2,
                  ),
                ),
                SizedBox(height: context.spacing.space4),
                Text(
                  event.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.display(
                    fontSize: 26,
                    color: Colors.white,
                    height: 1.05,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
          if (dayBadge != null)
            Positioned.directional(
              key: EventKeys.dayBadge,
              textDirection: Directionality.of(context),
              end: 20,
              bottom: -16,
              child: _DayBadge(label: dayBadge),
            ),
        ],
      ),
    );
  }

  static String? _formatDateRange(
    BuildContext context,
    DateTime? start,
    DateTime? end,
  ) {
    if (start == null && end == null) return null;
    if (start == null) return formatShortMonthDay(context, end!);
    if (end == null) return formatShortMonthDay(context, start);
    return formatDateRangeShort(context, start, end);
  }

  static String? _formatDayBadge(
    BuildContext context,
    DateTime? start,
    DateTime? end,
  ) {
    if (start == null || end == null) return null;
    final startDay = DateUtils.dateOnly(start);
    final endDay = DateUtils.dateOnly(end);
    if (endDay.isBefore(startDay)) return null;

    final today = DateUtils.dateOnly(DateTime.now());
    if (today.isBefore(startDay) || today.isAfter(endDay)) {
      return null;
    }

    final currentDay = today.difference(startDay).inDays + 1;
    final totalDays = endDay.difference(startDay).inDays + 1;
    return context.l10n.eventDayOf(currentDay, totalDays);
  }
}

class _DayBadge extends StatelessWidget {
  const _DayBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(context.spacing.radiusMedium),
        border: Border.all(color: colors.rule, width: 0.5),
        boxShadow: context.shadows.raised,
      ),
      child: Text(
        label,
        style: AppTypography.sans(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}

// ──────────────────────────── Misc helpers

String _relativeAge(BuildContext context, DateTime when) =>
    formatRelativeShort(context, when);

// ──────────────────────────── States

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusBar = MediaQuery.of(context).padding.top;
    return Column(
      children: [
        SizedBox(
          height: 148 + statusBar,
          child: Container(color: colors.cardSoft),
        ),
        Expanded(child: SkeletonLoader.generic(count: 3)),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(context.spacing.space24),
          child: EmptyStateView(
            icon: Iconsax.warning_2,
            title: context.l10n.eventLoadFailedTitle,
            message: context.l10n.activityLoadFailedMessage,
            actionLabel: context.l10n.commonRetry,
            onAction: onRetry,
          ),
        ),
      ),
    );
  }
}

class _NotFoundState extends StatelessWidget {
  const _NotFoundState();
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(context.spacing.space24),
          child: EmptyStateView(
            icon: Iconsax.box_remove,
            title: context.l10n.eventNotFound,
            message: context.l10n.eventMissingMessage,
            actionLabel: context.l10n.commonGoHome,
            onAction: () => GoRouter.of(context).go('/home'),
          ),
        ),
      ),
    );
  }
}
