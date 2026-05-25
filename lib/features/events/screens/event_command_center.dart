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
import '../../../shared/widgets/r_avatar.dart';
import '../../groups/models/group_member_model.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../../groups/services/event_participant_resolver.dart';
import '../../groups/services/member_name_resolver.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/models/settlement_model.dart';
import '../../ledger/providers/expense_provider.dart';
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
    final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));
    final balancesAsync = ref.watch(
      eventBalancesProvider((eventRef: eventRef, event: event)),
    );
    final groupMembers =
        ref.watch(groupMembersProvider(groupId)).valueOrNull ?? [];

    final expenses = expensesAsync.valueOrNull ?? const <Expense>[];
    final settlements =
        settlementsAsync.valueOrNull ?? const <Settlement>[];
    final balances = balancesAsync.valueOrNull ?? const <UserBalance>[];

    // Fix [3]: union event roster with former financial actors so the roster
    // strip and display-name map include UIDs that show up only in
    // expenses/settlements. Without this, a former-member settlement payer
    // is invisible in the strip even though the post-fix `balances` includes
    // their row.
    final resolution = buildEventParticipants(
      event: event,
      expenses: expenses,
      settlements: settlements,
      resolveDisplay: (uid, {String? fallbackName}) =>
          MemberNameResolver.resolveEventScoped(
            uid: uid,
            event: event,
            members: groupMembers,
            fallbackName: fallbackName,
          ),
    );
    final participantDisplayNames = <String, String>{
      for (final entry in resolution.displays.entries)
        entry.key: MemberNameResolver.format(entry.value),
    };
    final rosterUids = resolution.participants
        .map((p) => p.id)
        .toList(growable: false);

    final total = expenses.fold<Decimal>(
      Decimal.zero,
      (sum, e) => sum + e.amount,
    );

    final UserBalance? userBalance = currentUid == null
        ? null
        : balances.where((b) => b.participantId == currentUid).firstOrNull;

    final state = _resolveState(
      hasExpenses: expenses.isNotEmpty,
      userBalance: userBalance,
    );

    final breakdown = (state == _HubState.youOwed || state == _HubState.youOwe)
        ? _breakdownFor(
            currentUid!,
            balances,
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
          ),
        ),
        const SliverToBoxAdapter(child: OfflineBanner()),
        SliverPadding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 28, 20, 0),
          sliver: SliverToBoxAdapter(
            child: _BalanceHero(
              state: state,
              amount: userBalance?.netBalance.abs(),
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
                total: total,
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
              rosterUids: rosterUids,
              participantDisplayNames: participantDisplayNames,
              balances: balances,
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

enum _HubState { empty, settled, youOwed, youOwe }

_HubState _resolveState({
  required bool hasExpenses,
  required UserBalance? userBalance,
}) {
  if (!hasExpenses) return _HubState.empty;
  if (userBalance == null || userBalance.isSettled) return _HubState.settled;
  return userBalance.isOwedMoney ? _HubState.youOwed : _HubState.youOwe;
}

class _BreakdownEntry {
  const _BreakdownEntry({
    required this.otherUid,
    required this.otherName,
    required this.amount,
  });

  final String otherUid;
  final String otherName;
  final Decimal amount;
}

List<_BreakdownEntry> _breakdownFor(
  String currentUid,
  List<UserBalance> balances,
  Map<String, String> names,
  String fallbackName,
) {
  final settlements = BalanceCalculator.calculateOptimalSettlements(
    balances: balances,
    userNames: names,
  );
  final entries = <_BreakdownEntry>[];
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
        ),
      );
    } else if (from == currentUid) {
      entries.add(
        _BreakdownEntry(
          otherUid: to,
          otherName: (s['toUserName'] as String?) ?? names[to] ?? fallbackName,
          amount: amount,
        ),
      );
    }
  }
  return entries;
}

// ──────────────────────────── Balance hero

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({
    required this.state,
    required this.amount,
    required this.breakdown,
    required this.onAddExpense,
    required this.onSettleWith,
  });

  final _HubState state;
  final Decimal? amount;
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
        boxShadow: context.shadows.raised,
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state == _HubState.youOwed || state == _HubState.youOwe)
            _BalanceWithBreakdown(
              isOwed: state == _HubState.youOwed,
              amount: amount!,
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
    required this.isOwed,
    required this.amount,
    required this.breakdown,
    required this.onSettleWith,
  });

  final bool isOwed;
  final Decimal amount;
  final List<_BreakdownEntry> breakdown;
  final void Function(String otherUid) onSettleWith;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = isOwed ? colors.success : colors.error;
    final accentText = isOwed ? colors.successText : colors.errorText;
    final overlineLabel = isOwed
        ? context.l10n.eventYouAreOwed
        : context.l10n.eventYouOwe;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Overline(label: overlineLabel, color: accentText),
            _Overline(label: context.l10n.eventYourBalance),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            RAmount(
              value: amount,
              size: 40,
              weight: FontWeight.w800,
              sign: true,
              tone: isOwed ? AmountTone.sage : AmountTone.rust,
            ),
            const Spacer(),
            Container(width: 56, height: 2, color: accent),
          ],
        ),
        if (breakdown.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.rule, width: 0.5)),
            ),
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              children: [
                for (final entry in breakdown)
                  _BreakdownRow(
                    entry: entry,
                    isOwed: isOwed,
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
        const SizedBox(height: 8),
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
  const _BreakdownRow({
    required this.entry,
    required this.isOwed,
    required this.onTap,
  });

  final _BreakdownEntry entry;
  final bool isOwed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final verb = isOwed
        ? context.l10n.eventBreakdownOwesYou
        : context.l10n.eventBreakdownYouOwe;
    final firstName = entry.otherName.split(' ').first;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              RAvatar(name: entry.otherName, size: 32),
              const SizedBox(width: 12),
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
                size: 14,
                weight: FontWeight.w700,
                tone: isOwed ? AmountTone.sage : AmountTone.rust,
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
    required this.total,
    required this.count,
    required this.onTap,
  });

  final Decimal total;
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
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        RAmount(
                          value: total,
                          size: 20,
                          weight: FontWeight.w800,
                        ),
                        const SizedBox(width: 8),
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
    required this.onSeeAll,
    required this.onAddFirst,
  });

  final List<Expense> expenses;
  final String? currentUid;
  final Event event;
  final List<GroupMember> groupMembers;
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
  });

  final List<Expense> expenses;
  final String? currentUid;
  final Event event;
  final List<GroupMember> groupMembers;

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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (var i = 0; i < expenses.length; i++)
            _RecentRow(
              expense: expenses[i],
              currentUid: currentUid,
              event: event,
              groupMembers: groupMembers,
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
    required this.divider,
  });

  final Expense expense;
  final String? currentUid;
  final Event event;
  final List<GroupMember> groupMembers;
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
      padding: const EdgeInsets.symmetric(vertical: 12),
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
          const SizedBox(width: 12),
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
          const SizedBox(width: 8),
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
    final display = MemberNameResolver.resolveEventScoped(
      uid: expense.payerParticipantId,
      event: event,
      members: groupMembers,
      fallbackName: expense.payerName,
    );
    if (display.rawName == MemberNameResolver.formerMemberLiteral) {
      return display.rawName;
    }
    return display.rawName.split(' ').first;
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
    required this.rosterUids,
    required this.participantDisplayNames,
    required this.balances,
    required this.currentUid,
    required this.isEmpty,
    required this.onPersonTap,
  });

  /// Union of `event.participantIds` and former financial actors (Fix [3]).
  /// Drives count, others-count, and per-card iteration so former actors
  /// render alongside current participants.
  final List<String> rosterUids;
  final Map<String, String> participantDisplayNames;
  final List<UserBalance> balances;
  final String? currentUid;
  final bool isEmpty;
  final void Function(String uid) onPersonTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final count = rosterUids.length;
    final balanceByUid = {for (final b in balances) b.participantId: b};

    final othersCount = currentUid != null && rosterUids.contains(currentUid)
        ? count - 1
        : count;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _Overline(label: context.l10n.eventPeopleOverline(count)),
        ),
        if (isEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
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
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: rosterUids.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final uid = rosterUids[i];
              final isMe = uid == currentUid;
              final name =
                  participantDisplayNames[uid] ?? context.l10n.activitySomeone;
              final balance = balanceByUid[uid];
              return _RosterPersonCard(
                name: name,
                isMe: isMe,
                balance: balance,
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
    required this.balance,
    required this.showDot,
    required this.onTap,
  });

  final String name;
  final bool isMe;
  final UserBalance? balance;
  final bool showDot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final short = name.split(' ').first;
    final isOwed = balance != null && balance!.isOwedMoney;
    final owes = balance != null && balance!.owesMoney;
    final dotColor = isOwed
        ? colors.success
        : owes
        ? colors.error
        : null;

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
            const SizedBox(height: 8),
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
            const SizedBox(height: 8),
            SizedBox(
              height: 8,
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
  });

  final Event event;
  final String? groupName;
  final VoidCallback onSettings;

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
          CoverArt.forEventType(event.type),
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
                _PaperIconButton(
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
                _PaperIconButton(
                  key: EventKeys.settingsButton,
                  icon: Iconsax.setting_2,
                  onTap: onSettings,
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
                const SizedBox(height: 4),
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

class _PaperIconButton extends StatelessWidget {
  const _PaperIconButton({super.key, required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.cardSurface.withValues(alpha: 0.94),
      shape: const CircleBorder(),
      elevation: 1,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: colors.textPrimary),
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
        const Spacer(),
        CircularProgressIndicator(color: colors.primary),
        const Spacer(flex: 3),
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
          padding: const EdgeInsets.all(24),
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
          padding: const EdgeInsets.all(24),
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
