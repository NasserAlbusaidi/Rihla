import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/cover_art.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../../events/models/event_model.dart';
import '../../events/providers/event_provider.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../trip/models/trip_model.dart';
import '../keys/ledger_keys.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';
import '../providers/expense_provider.dart';
import '../widgets/ledger_search_sheet.dart';

/// Sealed timeline-item type — merges expenses and settlements into one
/// chronological feed.
sealed class _TimelineItem {
  DateTime get date;
}

final class _ExpenseItem extends _TimelineItem {
  _ExpenseItem(this.expense);
  final Expense expense;
  @override
  DateTime get date => expense.createdAt;
}

final class _SettlementItem extends _TimelineItem {
  _SettlementItem(this.settlement);
  final Settlement settlement;
  @override
  DateTime get date => settlement.settledAt;
}

/// Ledger — the showpiece. Saffron travel-journal direction.
///
/// Wireframe ref: `Wireframes/Rihla/hifi/screens-ledger.jsx` → `Hi_Ledger()`.
/// Layout top to bottom:
///   1. Cover header (120px + status bar) — `CoverArt.forEventType`, dark
///      gradient overlay, floating paper-style back · search · settings
///      buttons, mono caption ("DATES · N PEOPLE") + italic event title.
///   2. Hero card lifted -22 over cover — italic "Your tally on this trip" +
///      mono "OMR" header, big sage `RAmount(sign, 48)`, caption with inline
///      trip-total `RAmount`, per-person sage/rust bars (top 3), then a
///      full-width CTA strip ("Add expense" ink-filled · "Settle up").
///   3. Category chip strip — All · N / category chips with colored dots.
///   4. Day-grouped timeline — italic 18 date headers, card-wrapped rows
///      (category icon · expense title · payer + split caption · `RAmount` +
///      sage/rust share preview).
///   5. Footer: mono "· END OF LEDGER ·".
class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key, required this.groupId, required this.eventId});

  final String groupId;
  final String eventId;

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  /// Category bucket filter, 1-6. Null = All.
  int? _categoryFilter;

  String get groupId => widget.groupId;
  String get eventId => widget.eventId;

  @override
  Widget build(BuildContext context) {
    final eventRef = (groupId: groupId, eventId: eventId);
    final eventAsync = ref.watch(eventDetailProvider(eventRef));
    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));

    return Scaffold(
      key: LedgerKeys.screen,
      backgroundColor: context.colors.scaffoldBackground,
      body: eventAsync.when(
        loading: () => const _LoadingState(),
        error: (_, _) => _ErrorState(
          onRetry: () => ref.invalidate(eventDetailProvider(eventRef)),
        ),
        data: (event) {
          if (event == null) return const _NotFoundState();
          if (expensesAsync.hasError || settlementsAsync.hasError) {
            return _DataErrorState(
              event: event,
              onRetry: () {
                ref.invalidate(eventExpensesProvider(eventRef));
                ref.invalidate(eventSettlementsProvider(eventRef));
              },
            );
          }
          final expenses = (expensesAsync.valueOrNull ?? []).map((e) {
            final name = event.participantNames[e.payerParticipantId];
            return name != null ? e.copyWith(payerName: name) : e;
          }).toList();
          final settlements = settlementsAsync.valueOrNull ?? [];
          final currentUserId = ref.watch(currentUserIdProvider);
          return _Body(
            groupId: groupId,
            eventId: eventId,
            event: event,
            expenses: expenses,
            settlements: settlements,
            currentUserId: currentUserId,
            categoryFilter: _categoryFilter,
            onCategoryFilter: (cat) => setState(() => _categoryFilter = cat),
          );
        },
      ),
    );
  }
}

// ──────────────────────────── Body

class _Body extends StatelessWidget {
  const _Body({
    required this.groupId,
    required this.eventId,
    required this.event,
    required this.expenses,
    required this.settlements,
    required this.currentUserId,
    required this.categoryFilter,
    required this.onCategoryFilter,
  });

  final String groupId;
  final String eventId;
  final Event event;
  final List<Expense> expenses;
  final List<Settlement> settlements;
  final String? currentUserId;
  final int? categoryFilter;
  final ValueChanged<int?> onCategoryFilter;

  @override
  Widget build(BuildContext context) {
    final participants = event.participantIds
        .map(
          (id) => Participant(
            id: id,
            tripId: event.id,
            role: ParticipantRole.member,
            joinedAt: event.createdAt,
            displayName: event.participantNames[id],
          ),
        )
        .toList();
    final currentPid = event.participantIds.contains(currentUserId)
        ? currentUserId
        : null;

    final balances = BalanceCalculator.calculateBalances(
      expenses: expenses,
      settlements: settlements,
      participants: participants,
    );
    final myBalance = balances.firstWhere(
      (b) => b.participantId == currentPid,
      orElse: () => UserBalance(
        participantId: currentPid ?? '',
        displayName: 'You',
        totalPaid: Decimal.zero,
        totalOwed: Decimal.zero,
        netBalance: Decimal.zero,
      ),
    );
    final otherBalances =
        balances.where((b) => b.participantId != currentPid).toList()
          ..sort((a, b) => b.netBalance.abs().compareTo(a.netBalance.abs()));

    final eventTotal = expenses.fold<Decimal>(
      Decimal.zero,
      (sum, e) => sum + e.amount,
    );

    final filteredExpenses = categoryFilter == null
        ? expenses
        : expenses
              .where((e) => _categoryBucket(e.categoryName) == categoryFilter)
              .toList();
    // Settlements only appear in the "All" view since they don't have categories.
    final filteredSettlements = categoryFilter == null
        ? settlements
        : <Settlement>[];
    final timeline = <_TimelineItem>[
      ...filteredExpenses.map(_ExpenseItem.new),
      ...filteredSettlements.map(_SettlementItem.new),
    ]..sort((a, b) => b.date.compareTo(a.date));
    final days = _groupByDay(timeline, DateTime.now());

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _CoverHeader(
            event: event,
            participants: participants,
            onSettings: () => GoRouter.of(
              context,
            ).push('/group/$groupId/event/$eventId/settings'),
            onSearch: () => showLedgerSearchSheet(
              context,
              expenses: expenses,
              settlements: settlements,
              groupId: groupId,
              eventId: eventId,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: OfflineBanner()),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -22),
              child: _HeroCard(
                netBalance: myBalance.netBalance,
                eventTotal: eventTotal,
                otherBalances: otherBalances,
                currentPid: currentPid,
                participants: participants,
                onAddExpense: () {
                  HapticService.medium();
                  GoRouter.of(
                    context,
                  ).push('/group/$groupId/event/$eventId/ledger/add');
                },
                onSettleUp: () {
                  HapticService.lightClick();
                  GoRouter.of(
                    context,
                  ).push('/group/$groupId/event/$eventId/ledger/settle-up');
                },
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _CategoryStrip(
            total: expenses.length,
            active: categoryFilter,
            onChange: onCategoryFilter,
            expenses: expenses,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 6)),
        if (timeline.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            sliver: SliverToBoxAdapter(
              child: EmptyStateView(
                icon: Iconsax.receipt_item,
                title: categoryFilter == null
                    ? 'No expenses yet'
                    : 'Nothing in this category',
                message: categoryFilter == null
                    ? 'Add your first expense to start tracking who paid what.'
                    : 'Try a different category, or switch back to All.',
                actionLabel: categoryFilter == null ? 'Add Expense' : null,
                onAction: categoryFilter == null
                    ? () => GoRouter.of(
                        context,
                      ).push('/group/$groupId/event/$eventId/ledger/add')
                    : null,
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final day = days[index];
              return Padding(
                padding: EdgeInsets.fromLTRB(20, index == 0 ? 8 : 18, 20, 0),
                child: _DaySection(
                  label: day.label,
                  items: day.items,
                  participants: participants,
                  currentPid: currentPid,
                  onExpenseTap: (expense) => GoRouter.of(context).push(
                    '/group/$groupId/event/$eventId/ledger/edit/${expense.id}',
                  ),
                ),
              );
            }, childCount: days.length),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                '· END OF LEDGER ·',
                style: AppTypography.mono(
                  fontSize: 9,
                  color: context.colors.textSecondary,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────── Cover header

class _CoverHeader extends StatelessWidget {
  const _CoverHeader({
    required this.event,
    required this.participants,
    required this.onSettings,
    required this.onSearch,
  });

  final Event event;
  final List<Participant> participants;
  final VoidCallback onSettings;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final statusBar = MediaQuery.of(context).padding.top;
    final dateRange = _formatDateRange(event.startDate, event.endDate);
    final captionParts = <String>[
      ?dateRange,
      '${participants.length} '
          'PEOPLE',
    ];

    return SizedBox(
      height: 120 + statusBar,
      child: Stack(
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
                stops: const [0.3, 1.0],
              ),
            ),
          ),
          Positioned(
            top: statusBar + 8,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _PaperIconButton(
                  icon: Iconsax.arrow_left,
                  tooltip: 'Back',
                  onTap: () {
                    HapticService.lightClick();
                    if (GoRouter.of(context).canPop()) {
                      GoRouter.of(context).pop();
                    }
                  },
                ),
                Row(
                  children: [
                    _PaperIconButton(
                      icon: Iconsax.search_normal,
                      tooltip: 'Search expenses',
                      onTap: () {
                        HapticService.lightClick();
                        onSearch();
                      },
                    ),
                    const SizedBox(width: 6),
                    _PaperIconButton(
                      icon: Iconsax.setting_2,
                      tooltip: 'Event settings',
                      onTap: () {
                        HapticService.lightClick();
                        onSettings();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  captionParts.join(' · ').toUpperCase(),
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
                    height: 1.1,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String? _formatDateRange(DateTime? start, DateTime? end) {
    if (start == null && end == null) return null;
    String fmt(DateTime d) => '${_months[d.month - 1]} ${d.day}';
    if (start == null) return fmt(end!);
    if (end == null) return fmt(start);
    return '${fmt(start)} — ${fmt(end)}';
  }
}

class _PaperIconButton extends StatelessWidget {
  const _PaperIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final button = Material(
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
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

// ──────────────────────────── Hero card

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.netBalance,
    required this.eventTotal,
    required this.otherBalances,
    required this.currentPid,
    required this.participants,
    required this.onAddExpense,
    required this.onSettleUp,
  });

  final Decimal netBalance;
  final Decimal eventTotal;
  final List<UserBalance> otherBalances;
  final String? currentPid;
  final List<Participant> participants;
  final VoidCallback onAddExpense;
  final VoidCallback onSettleUp;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isPositive = netBalance > Decimal.zero;
    final isNegative = netBalance < Decimal.zero;
    final tone = isPositive
        ? AmountTone.sage
        : isNegative
        ? AmountTone.rust
        : AmountTone.ink;

    final othersOwed = otherBalances
        .where((b) => b.netBalance < Decimal.zero)
        .length;
    final caption = isPositive
        ? 'Net — $othersOwed friend${othersOwed == 1 ? '' : 's'} owe you · trip total'
        : isNegative
        ? 'Net — you owe · trip total'
        : 'All settled · trip total';

    final topBars = otherBalances.take(3).toList();
    final maxAbs = topBars.fold<Decimal>(
      Decimal.zero,
      (m, b) => b.netBalance.abs() > m ? b.netBalance.abs() : m,
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: context.shadows.raised,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        'Your tally on this trip',
                        style: AppTypography.display(
                          fontSize: 14,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      'OMR',
                      style: AppTypography.mono(
                        fontSize: 9,
                        color: colors.textSecondary,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                RAmount(
                  value: netBalance,
                  size: 48,
                  sign: netBalance != Decimal.zero,
                  tone: tone,
                  weight: FontWeight.w500,
                  showCurrency: false,
                ),
                const SizedBox(height: 6),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    Text(
                      caption,
                      style: AppTypography.sans(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                    RAmount(
                      value: eventTotal,
                      size: 13,
                      weight: FontWeight.w600,
                      tone: AmountTone.ink,
                      showCurrency: false,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (topBars.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
              child: Column(
                children: [
                  for (final b in topBars)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PersonBar(
                        name: b.displayName ?? 'Member',
                        balance: b.netBalance,
                        maxAbs: maxAbs,
                      ),
                    ),
                ],
              ),
            ),
          // CTA strip
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.rule, width: 1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Material(
                    color: colors.textPrimary,
                    child: InkWell(
                      onTap: onAddExpense,
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Iconsax.add,
                              size: 16,
                              color: colors.scaffoldBackground,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Add expense',
                              style: AppTypography.sans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colors.scaffoldBackground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Container(width: 1, height: 48, color: colors.rule),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onSettleUp,
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        child: Text(
                          'Settle up',
                          style: AppTypography.sans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonBar extends StatelessWidget {
  const _PersonBar({
    required this.name,
    required this.balance,
    required this.maxAbs,
  });

  final String name;
  final Decimal balance;
  final Decimal maxAbs;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Wireframe shows "they owe you" perspective — invert sign for display so
    // a positive bar = they owe the user.
    final showSign = -balance;
    final isPositive = showSign > Decimal.zero;
    final magnitude = showSign.abs();
    final fraction = maxAbs == Decimal.zero
        ? 0.0
        : (magnitude.toDouble() / maxAbs.toDouble()).clamp(0.0, 1.0);

    return Row(
      children: [
        RAvatar(name: name, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 4,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.rule,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isPositive ? colors.success : colors.error,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        RAmount(
          value: showSign,
          size: 12,
          sign: showSign != Decimal.zero,
          weight: FontWeight.w500,
          showCurrency: false,
        ),
      ],
    );
  }
}

// ──────────────────────────── Category strip

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.total,
    required this.active,
    required this.onChange,
    required this.expenses,
  });

  final int total;
  final int? active;
  final ValueChanged<int?> onChange;
  final List<Expense> expenses;

  @override
  Widget build(BuildContext context) {
    final present = <int>{};
    for (final e in expenses) {
      present.add(_categoryBucket(e.categoryName));
    }
    // Stable display order matching the wireframe's chip set.
    const order = [1, 2, 3, 4, 5, 6];
    final available = order.where(present.contains).toList(growable: false);

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
        children: [
          _Chip(
            label: 'All · $total',
            active: active == null,
            dot: null,
            onTap: () => onChange(null),
          ),
          const SizedBox(width: 8),
          for (final cat in available) ...[
            _Chip(
              label: _categoryName(cat),
              active: active == cat,
              dot: _categoryColor(context.colors, cat),
              onTap: () => onChange(cat),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
    this.dot,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: () {
        HapticService.selection();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? colors.textPrimary : colors.cardSoft,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(
            color: active ? colors.textPrimary : colors.rule,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppTypography.sans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? colors.scaffoldBackground : colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────── Day section

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.label,
    required this.items,
    required this.participants,
    required this.currentPid,
    required this.onExpenseTap,
  });

  final String label;
  final List<_TimelineItem> items;
  final List<Participant> participants;
  final String? currentPid;
  final ValueChanged<Expense> onExpenseTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            label,
            style: AppTypography.display(
              fontSize: 18,
              color: colors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: colors.cardSurface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: context.shadows.raised,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++)
                _buildRow(context, items[i], i < items.length - 1),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRow(BuildContext context, _TimelineItem item, bool divider) {
    return switch (item) {
      _ExpenseItem(:final expense) => _ExpenseRow(
        key: LedgerKeys.expenseCard(expense.id),
        expense: expense,
        divider: divider,
        participants: participants,
        currentPid: currentPid,
        onTap: () => onExpenseTap(expense),
      ),
      _SettlementItem(:final settlement) => _SettlementRow(
        settlement: settlement,
        divider: divider,
      ),
    };
  }
}

// ──────────────────────────── Expense row

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({
    super.key,
    required this.expense,
    required this.divider,
    required this.participants,
    required this.currentPid,
    required this.onTap,
  });

  final Expense expense;
  final bool divider;
  final List<Participant> participants;
  final String? currentPid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bucket = _categoryBucket(expense.categoryName);
    final isPayer = expense.payerParticipantId == currentPid;
    final payerName = isPayer
        ? 'You'
        : expense.payerName ??
              participants
                  .where((p) => p.id == expense.payerParticipantId)
                  .map((p) => p.displayName ?? 'Member')
                  .firstOrNull ??
              'Member';
    final splitIds = expense.customSplitParticipants;
    final splitCount = splitIds != null ? splitIds.length : participants.length;
    final share = _userShare(expense);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _CategoryIcon(bucket: bucket),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        expense.description ?? 'Expense',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$payerName paid · split $splitCount way${splitCount == 1 ? '' : 's'}',
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
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RAmount(
                      value: expense.amount,
                      size: 14,
                      showCurrency: false,
                    ),
                    if (share != Decimal.zero) ...[
                      const SizedBox(height: 2),
                      RAmount(
                        value: share,
                        size: 11,
                        sign: true,
                        weight: FontWeight.w500,
                        showCurrency: false,
                      ),
                    ],
                  ],
                ),
              ],
            ),
            if (divider) ...[
              const SizedBox(height: 12),
              Container(height: 0.5, color: colors.rule),
            ],
          ],
        ),
      ),
    );
  }

  Decimal _userShare(Expense expense) {
    final count = participants.length;
    if (count == 0 || currentPid == null) return Decimal.zero;
    final isPayer = expense.payerParticipantId == currentPid;
    final splitIds = expense.customSplitParticipants;
    final isInSplit = splitIds != null ? splitIds.contains(currentPid) : true;
    final splitCount = splitIds != null ? splitIds.length : count;
    if (splitCount == 0) return Decimal.zero;
    final share = (expense.amount / Decimal.fromInt(splitCount)).toDecimal(
      scaleOnInfinitePrecision: 3,
    );
    if (isPayer && isInSplit) return expense.amount - share;
    if (isPayer && !isInSplit) return expense.amount;
    if (!isPayer && isInSplit) return -share;
    return Decimal.zero;
  }
}

class _SettlementRow extends StatelessWidget {
  const _SettlementRow({required this.settlement, required this.divider});
  final Settlement settlement;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final payer = settlement.payerName ?? 'Someone';
    final recipient = settlement.recipientName ?? 'someone';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.cardSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.rule, width: 0.5),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Iconsax.arrow_right_3,
                  size: 18,
                  color: colors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: payer,
                        style: AppTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      TextSpan(
                        text: ' paid ',
                        style: AppTypography.sans(
                          fontSize: 14,
                          color: colors.textSecondary,
                        ),
                      ),
                      TextSpan(
                        text: recipient,
                        style: AppTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              RAmount(value: settlement.amount, size: 14, showCurrency: false),
            ],
          ),
          if (divider) ...[
            const SizedBox(height: 12),
            Container(height: 0.5, color: colors.rule),
          ],
        ],
      ),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.bucket});
  final int bucket;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = _categoryColor(colors, bucket);
    final icon = switch (bucket) {
      1 => Iconsax.coffee,
      2 => Iconsax.house_2,
      3 => Iconsax.car,
      4 => Iconsax.shopping_cart,
      5 => Iconsax.star,
      _ => Iconsax.box,
    };
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colors.cardSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.rule, width: 0.5),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: fg),
    );
  }
}

// ──────────────────────────── Day grouping

class _DayGroup {
  const _DayGroup({required this.label, required this.items});
  final String label;
  final List<_TimelineItem> items;
}

List<_DayGroup> _groupByDay(List<_TimelineItem> items, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final groups = <String, List<_TimelineItem>>{};
  final order = <String>[];
  for (final item in items) {
    final ts = item.date;
    final day = DateTime(ts.year, ts.month, ts.day);
    final diff = today.difference(day).inDays;
    final label = diff == 0
        ? 'Today · ${_monthShort(ts.month)} ${ts.day}'
        : diff == 1
        ? 'Yesterday · ${_monthShort(ts.month)} ${ts.day}'
        : '${_monthShort(ts.month)} ${ts.day}';
    if (!groups.containsKey(label)) {
      groups[label] = [];
      order.add(label);
    }
    groups[label]!.add(item);
  }
  return [
    for (final label in order) _DayGroup(label: label, items: groups[label]!),
  ];
}

// ──────────────────────────── Helpers

int _categoryBucket(String? name) {
  if (name == null) return 6;
  final lower = name.toLowerCase();
  bool any(List<String> needles) => needles.any(lower.contains);
  if (any(const ['food', 'rest', 'din', 'meal'])) return 1;
  if (any(const ['lodg', 'hotel', 'accom', 'stay'])) return 2;
  if (any(const ['trans', 'taxi', 'flight', 'uber', 'train'])) return 3;
  if (any(const ['groc', 'supermark'])) return 4;
  if (any(const ['activ', 'entertain', 'tour', 'ticket'])) return 5;
  return 6;
}

String _categoryName(int bucket) {
  return switch (bucket) {
    1 => 'Food',
    2 => 'Lodging',
    3 => 'Transit',
    4 => 'Groceries',
    5 => 'Activities',
    _ => 'Other',
  };
}

Color _categoryColor(AppColorTokens colors, int bucket) {
  return switch (bucket) {
    1 => colors.cat1,
    2 => colors.cat2,
    3 => colors.cat3,
    4 => colors.cat4,
    5 => colors.cat5,
    _ => colors.cat6,
  };
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
String _monthShort(int m) => _months[m - 1];

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
          height: 120 + statusBar,
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
            title: 'Could not load event',
            message: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: onRetry,
          ),
        ),
      ),
    );
  }
}

class _DataErrorState extends StatelessWidget {
  const _DataErrorState({required this.event, required this.onRetry});
  final Event event;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: EmptyStateView(
            icon: Iconsax.warning_2,
            title: "Couldn't load ledger",
            message: 'Check your connection and try again.',
            actionLabel: 'Reload',
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
            title: 'Event not found',
            message: 'It may have been deleted, or the link is incorrect.',
            actionLabel: 'Go Home',
            onAction: () => GoRouter.of(context).go('/home'),
          ),
        ),
      ),
    );
  }
}
