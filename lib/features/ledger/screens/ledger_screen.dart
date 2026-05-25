import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/cover_art.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../events/models/event_model.dart';
import '../../events/providers/event_provider.dart';
import '../../groups/models/group_member_model.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../../groups/services/event_participant_resolver.dart';
import '../../groups/services/member_name_resolver.dart';
import '../keys/ledger_keys.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';
import '../providers/expense_provider.dart';
import '../utils/ledger_categories.dart';
import '../utils/ledger_timeline.dart';
import '../widgets/ledger_category_strip.dart';
import '../widgets/ledger_day_card.dart';
import '../widgets/ledger_hero_block.dart';
import '../widgets/ledger_roster_strip.dart';
import '../widgets/ledger_search_sheet.dart';
import '../widgets/ledger_sticky_cta.dart';

/// V5R ledger — saffron travel-journal direction.
///
/// Layout top to bottom:
///   1. 120px CoverArt cover header with floating paper buttons (back ·
///      search · settings) and bottom-aligned mono meta + italic title.
///   2. Italic statement hero ("You're up [+OMR 12.450] across 3 people.").
///   3. Mono trip-total caption ("TRIP TOTAL · OMR 142.350 · 6 expenses · 2 settled").
///   4. Horizontal roster strip — You anchor + per-person signed chips.
///   5. Category chip filter (cat-color dots, "All · N" first).
///   6. Day-grouped white cards with two-row italic day stamps. Distinct
///      settlement rows (dashed sage inset with sage-text overline).
///   7. Footer: mono "· END OF LEDGER ·".
///   8. Sticky bottom CTA bar — ink "Add expense" + ghost "Settle up"
///      (dimmed when settled).
class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key, required this.groupId, required this.eventId});

  final String groupId;
  final String eventId;

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  int? _categoryFilter;

  @override
  Widget build(BuildContext context) {
    final eventRef = (groupId: widget.groupId, eventId: widget.eventId);
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
              onRetry: () {
                ref.invalidate(eventExpensesProvider(eventRef));
                ref.invalidate(eventSettlementsProvider(eventRef));
              },
            );
          }
          final expenses = expensesAsync.valueOrNull ?? <Expense>[];
          final settlements = settlementsAsync.valueOrNull ?? <Settlement>[];
          final currentUserId = ref.watch(currentUserIdProvider);
          final groupMembers =
              ref.watch(groupMembersProvider(widget.groupId)).valueOrNull ??
              const <GroupMember>[];
          return _Body(
            groupId: widget.groupId,
            eventId: widget.eventId,
            event: event,
            expenses: expenses,
            settlements: settlements,
            groupMembers: groupMembers,
            currentUserId: currentUserId,
            categoryFilter: _categoryFilter,
            onCategoryFilter: (cat) => setState(() => _categoryFilter = cat),
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.groupId,
    required this.eventId,
    required this.event,
    required this.expenses,
    required this.settlements,
    required this.groupMembers,
    required this.currentUserId,
    required this.categoryFilter,
    required this.onCategoryFilter,
  });

  final String groupId;
  final String eventId;
  final Event event;
  final List<Expense> expenses;
  final List<Settlement> settlements;
  final List<GroupMember> groupMembers;
  final String? currentUserId;
  final int? categoryFilter;
  final ValueChanged<int?> onCategoryFilter;

  @override
  Widget build(BuildContext context) {
    // Union event roster with former financial actors (Fix [3]) so per-event
    // sum(netBalance) == 0 when a settlement involves a UID not in the event
    // roster. Helper handles split recipients, custom-split participants,
    // and fallback names harvested from expense/settlement payerName fields.
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
    final participants = resolution.participants;
    final currentPid = event.participantIds.contains(currentUserId)
        ? currentUserId
        : null;

    final balances = BalanceCalculator.calculateBalances(
      expenses: expenses,
      settlements: settlements,
      participants: participants,
    );
    final myBalance = _resolveMyBalance(
      balances,
      currentPid,
      context.l10n.ledgerYou,
    );
    final eventTotal = expenses.fold<Decimal>(
      Decimal.zero,
      (sum, e) => sum + e.amount,
    );

    // From the current user's perspective:
    //   negative net for someone else → they owe you (positive chip)
    //   positive net for someone else → you owe them (negative chip)
    final roster =
        balances
            .where((b) => b.participantId != currentPid)
            .map(
              (b) => LedgerRosterPerson(
                participantId: b.participantId,
                displayName: b.displayName ?? context.l10n.ledgerMemberFallback,
                signedAmount: -b.netBalance,
              ),
            )
            .toList()
          ..sort(
            (a, b) => b.signedAmount.abs().compareTo(a.signedAmount.abs()),
          );

    final hasExpenses = expenses.isNotEmpty;
    final isSettled = hasExpenses && myBalance.netBalance == Decimal.zero;
    final heroKind = !hasExpenses
        ? LedgerHeroKind.empty
        : isSettled
        ? LedgerHeroKind.settled
        : myBalance.netBalance > Decimal.zero
        ? LedgerHeroKind.positive
        : LedgerHeroKind.negative;
    final rosterState = !hasExpenses
        ? LedgerRosterState.empty
        : isSettled
        ? LedgerRosterState.settled
        : LedgerRosterState.live;
    final peopleCount = roster
        .where((p) => p.signedAmount != Decimal.zero)
        .length;

    final filteredExpenses = categoryFilter == null
        ? expenses
        : expenses
              .where(
                (e) => ledgerCategoryBucket(e.categoryName) == categoryFilter,
              )
              .toList();
    final filteredSettlements = categoryFilter == null
        ? settlements
        : <Settlement>[];
    final timeline = <LedgerTimelineItem>[
      ...filteredExpenses.map(LedgerExpenseItem.new),
      ...filteredSettlements.map(LedgerSettlementItem.new),
    ]..sort((a, b) => b.date.compareTo(a.date));
    final days = groupTimelineByDay(
      timeline,
      DateTime.now(),
      l10n: context.l10n,
    );
    final expensePayerDisplayNames = <String, String>{
      for (final expense in expenses)
        expense.id: MemberNameResolver.format(
          MemberNameResolver.resolveEventScoped(
            uid: expense.payerParticipantId,
            event: event,
            members: groupMembers,
            fallbackName: expense.payerName,
          ),
        ),
    };
    final settlementDisplayNames =
        <String, ({String payerName, String recipientName})>{
          for (final settlement in settlements)
            settlement.id: (
              payerName: settlement.payerParticipantId == null
                  ? settlement.payerName ?? context.l10n.ledgerSomeone
                  : MemberNameResolver.format(
                      MemberNameResolver.resolveEventScoped(
                        uid: settlement.payerParticipantId!,
                        event: event,
                        members: groupMembers,
                        fallbackName: settlement.payerName,
                      ),
                    ),
              recipientName: settlement.recipientParticipantId == null
                  ? settlement.recipientName ?? context.l10n.ledgerSomeoneLower
                  : MemberNameResolver.format(
                      MemberNameResolver.resolveEventScoped(
                        uid: settlement.recipientParticipantId!,
                        event: event,
                        members: groupMembers,
                        fallbackName: settlement.recipientName,
                      ),
                    ),
            ),
        };

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _CoverHeader(
                  event: event,
                  participantCount: participants.length,
                  onSettings: () => GoRouter.of(
                    context,
                  ).push('/group/$groupId/event/$eventId/settings'),
                  onSearch: () => showLedgerSearchSheet(
                    context,
                    expenses: expenses,
                    settlements: settlements,
                    expensePayerDisplayNames: expensePayerDisplayNames,
                    settlementDisplayNames: settlementDisplayNames,
                    groupId: groupId,
                    eventId: eventId,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: OfflineBanner()),
              SliverToBoxAdapter(
                child: LedgerHeroStatement(
                  kind: heroKind,
                  amount: myBalance.netBalance,
                  peopleCount: peopleCount,
                ),
              ),
              if (hasExpenses)
                SliverToBoxAdapter(
                  child: LedgerTripCaption(
                    total: eventTotal,
                    expenseCount: expenses.length,
                    settledCount: settlements.length,
                  ),
                ),
              SliverToBoxAdapter(
                child: LedgerRosterStrip(
                  state: rosterState,
                  others: roster,
                  currentUserDisplayName:
                      myBalance.displayName ?? context.l10n.ledgerYou,
                  onPersonTap: (p) => GoRouter.of(context).push(
                    '/group/$groupId/event/$eventId/ledger/'
                    'settle-up?memberId=${Uri.encodeComponent(p.participantId)}',
                  ),
                ),
              ),
              if (hasExpenses)
                SliverToBoxAdapter(
                  child: LedgerCategoryStrip(
                    expenses: expenses,
                    totalCount: expenses.length,
                    active: categoryFilter,
                    onChange: onCategoryFilter,
                  ),
                )
              else
                const SliverToBoxAdapter(child: LedgerCategoryStripEmpty()),
              const SliverToBoxAdapter(child: SizedBox(height: 6)),
              if (timeline.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: hasExpenses
                        ? EmptyStateView(
                            icon: Iconsax.receipt_item,
                            title: context.l10n.ledgerNothingInCategoryTitle,
                            message:
                                context.l10n.ledgerNothingInCategoryMessage,
                          )
                        : const _EmptyStateBody(),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final day = days[index];
                    return Padding(
                      padding: EdgeInsets.only(top: index == 0 ? 4 : 14),
                      child: LedgerDayCard(
                        dayLabel: day.label,
                        sub: null,
                        items: day.items,
                        currentParticipantId: currentPid,
                        participantCount: participants.length,
                        expensePayerDisplayNames: expensePayerDisplayNames,
                        settlementDisplayNames: settlementDisplayNames,
                        onExpenseTap: (expense) => GoRouter.of(context).push(
                          '/group/$groupId/event/$eventId/ledger/'
                          'edit/${expense.id}',
                        ),
                      ),
                    );
                  }, childCount: days.length),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      isSettled
                          ? '· ${context.l10n.ledgerEndOfLedger} · 0.000 ·'
                          : '· ${context.l10n.ledgerEndOfLedger} ·',
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
          ),
        ),
        LedgerStickyCta(
          settleEnabled: !isSettled && hasExpenses,
          onAddExpense: () => GoRouter.of(
            context,
          ).push('/group/$groupId/event/$eventId/ledger/add'),
          onSettleUp: () => GoRouter.of(
            context,
          ).push('/group/$groupId/event/$eventId/ledger/settle-up'),
        ),
      ],
    );
  }

  static UserBalance _resolveMyBalance(
    List<UserBalance> balances,
    String? currentPid,
    String fallbackDisplayName,
  ) {
    return balances.firstWhere(
      (b) => b.participantId == currentPid,
      orElse: () => UserBalance(
        participantId: currentPid ?? '',
        displayName: fallbackDisplayName,
        totalPaid: Decimal.zero,
        totalOwed: Decimal.zero,
        netBalance: Decimal.zero,
      ),
    );
  }
}

// ──────────────────────────── Cover header

class _CoverHeader extends StatelessWidget {
  const _CoverHeader({
    required this.event,
    required this.participantCount,
    required this.onSettings,
    required this.onSearch,
  });

  final Event event;
  final int participantCount;
  final VoidCallback onSettings;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusBar = MediaQuery.of(context).padding.top;
    final dateRange = formatEventDateRange(
      event.startDate,
      event.endDate,
      l10n: context.l10n,
    );
    final captionParts = <String>[
      ?dateRange,
      context.l10n.ledgerPeopleCount(participantCount),
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
                  colors.textPrimary.withValues(alpha: 0.55),
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
                  tooltip: context.l10n.ledgerBackTooltip,
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
                      tooltip: context.l10n.ledgerSearchExpensesTooltip,
                      onTap: () {
                        HapticService.lightClick();
                        onSearch();
                      },
                    ),
                    const SizedBox(width: 6),
                    _PaperIconButton(
                      icon: Iconsax.setting_2,
                      tooltip: context.l10n.ledgerEventSettingsTooltip,
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

// ──────────────────────────── Empty-state body

class _EmptyStateBody extends StatelessWidget {
  const _EmptyStateBody();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 8),
      child: Column(
        children: [
          CustomPaint(
            size: const Size(120, 116),
            painter: _JournalPagePainter(colors: colors),
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.ledgerEmptyStateTitle,
            textAlign: TextAlign.center,
            style: AppTypography.display(
              fontSize: 22,
              color: colors.textPrimary,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.ledgerEmptyStateFirstExpenseBody,
            textAlign: TextAlign.center,
            style: AppTypography.sans(
              fontSize: 13,
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sketched journal-page illustration for the empty state — rounded
/// rectangle outline, dashed ruled lines, and a saffron plus-circle in
/// the top-right corner. Lightweight Flutter mirror of the V5R SVG.
class _JournalPagePainter extends CustomPainter {
  _JournalPagePainter({required this.colors});
  final AppColorTokens colors;

  @override
  void paint(Canvas canvas, Size size) {
    final pagePaint = Paint()
      ..color = colors.cardSurface
      ..style = PaintingStyle.fill;
    final pageStroke = Paint()
      ..color = colors.textSecondary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final ruleStroke = Paint()
      ..color = colors.rule2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final pageRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(18, 14, 84, 92),
      const Radius.circular(6),
    );
    canvas.drawRRect(pageRect, pagePaint);
    canvas.drawRRect(pageRect, pageStroke);

    final lines = <(double, double, double)>[
      (30, 36, 90),
      (30, 50, 90),
      (30, 64, 70),
      (30, 78, 84),
      (30, 92, 62),
    ];
    for (final (sx, y, ex) in lines) {
      _dashedHLine(canvas, sx, ex, y, ruleStroke, dash: 2, gap: 4);
    }

    final saffronTintPaint = Paint()..color = colors.saffronTint;
    final saffronStroke = Paint()
      ..color = colors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawCircle(const Offset(98, 14), 14, saffronTintPaint);
    canvas.drawCircle(const Offset(98, 14), 14, saffronStroke);
    final plusPaint = Paint()
      ..color = colors.primaryDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(92, 14), const Offset(104, 14), plusPaint);
    canvas.drawLine(const Offset(98, 8), const Offset(98, 20), plusPaint);
  }

  void _dashedHLine(
    Canvas canvas,
    double x0,
    double x1,
    double y,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    var x = x0;
    final step = dash + gap;
    while (x < x1) {
      final next = (x + dash).clamp(x0, x1);
      canvas.drawLine(Offset(x, y), Offset(next, y), paint);
      x += step;
    }
  }

  @override
  bool shouldRepaint(covariant _JournalPagePainter old) => old.colors != colors;
}

// ──────────────────────────── State views

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
            title: context.l10n.ledgerCouldNotLoadEventTitle,
            message: context.l10n.ledgerConnectionRetryMessage,
            actionLabel: context.l10n.commonRetry,
            onAction: onRetry,
          ),
        ),
      ),
    );
  }
}

class _DataErrorState extends StatelessWidget {
  const _DataErrorState({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: EmptyStateView(
            icon: Iconsax.warning_2,
            title: context.l10n.ledgerCouldNotLoadLedgerTitle,
            message: context.l10n.ledgerConnectionRetryMessage,
            actionLabel: context.l10n.ledgerReload,
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
            title: context.l10n.ledgerEventNotFoundTitle,
            message: context.l10n.ledgerEventNotFoundMessage,
            actionLabel: context.l10n.commonGoHome,
            onAction: () => GoRouter.of(context).go('/home'),
          ),
        ),
      ),
    );
  }
}
