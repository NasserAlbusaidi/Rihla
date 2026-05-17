import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/models/settlement_model.dart';
import '../services/member_name_resolver.dart';
import '../widgets/group_settlement_summary.dart';
import 'all_settled_state.dart';
import 'group_settlement_tile.dart';

/// Single-page body for the Settle-Up screens (group + event).
///
/// Wireframe (Hi_GroupSettle, screens-group.jsx) renders one scrollable view:
/// italic headline, two summary chips, optimized transfer cards, then
/// "Each person's net" and a small recorded-payment history.
class SettleUpPageBody extends StatelessWidget {
  /// Label shown after "Optimized to minimise the number of payments across …"
  /// — group name on the group screen, event name on the event screen.
  final String subjectName;
  final String currency;
  final List<Map<String, dynamic>> optimalSettlements;
  final List<UserBalance> balances;
  final Map<String, String> rawNames;
  final AsyncValue<List<Settlement>> settlementsAsync;
  final String? currentUid;
  final Map<int, GlobalKey> tileKeys;

  /// Pre-selected member to highlight (deep-link).
  final String? preSelectedMemberId;

  final void Function({
    required Map<String, dynamic> settlement,
    required String fromRawName,
    required String toRawName,
    required String fromUserId,
    required String toUserId,
    required Decimal suggestedAmount,
  })
  onRecord;

  /// Optional per-tile breakdown (e.g. group-level "per event" attribution).
  /// Return an empty map (or pass null) to hide the expand affordance.
  final Map<String, Decimal> Function(String fromUserId, String toUserId)?
  buildBreakdown;

  const SettleUpPageBody({
    super.key,
    required this.subjectName,
    required this.currency,
    required this.optimalSettlements,
    required this.balances,
    required this.rawNames,
    required this.settlementsAsync,
    required this.currentUid,
    required this.tileKeys,
    required this.onRecord,
    this.buildBreakdown,
    this.preSelectedMemberId,
  });

  @override
  Widget build(BuildContext context) {
    Decimal totalPending = Decimal.zero;
    for (final s in optimalSettlements) {
      totalPending += (s['amount'] as Decimal);
    }

    final history = settlementsAsync.valueOrNull ?? const <Settlement>[];
    final allSettled = optimalSettlements.isEmpty && history.isEmpty;
    final displayNames = <String, String>{
      for (final balance in balances)
        if (balance.displayName != null)
          balance.participantId: balance.displayName!,
    };

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettlementIntro(
            transferCount: optimalSettlements.length,
            subjectName: subjectName,
          ),
          const SizedBox(height: 18),
          GroupSettlementSummaryCard(
            totalPending: totalPending,
            currency: currency,
            transferCount: optimalSettlements.length,
          ),
          if (allSettled) ...[
            const SizedBox(height: 32),
            const AllSettledState(),
          ],
          if (optimalSettlements.isNotEmpty) ...[
            const SizedBox(height: 18),
            for (var i = 0; i < optimalSettlements.length; i++)
              _buildTile(context, optimalSettlements[i], i),
          ],
          if (balances.isNotEmpty) ...[
            const SizedBox(height: 24),
            _NetBalancesSection(balances: balances, currency: currency),
          ],
          if (history.isNotEmpty) ...[
            const SizedBox(height: 24),
            _PaymentHistorySection(
              settlements: history,
              currency: currency,
              displayNames: displayNames,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTile(
    BuildContext context,
    Map<String, dynamic> settlement,
    int index,
  ) {
    final fromUserId = settlement['fromUserId'] as String;
    final toUserId = settlement['toUserId'] as String;
    final fromName = settlement['fromUserName'] as String;
    final toName = settlement['toUserName'] as String;
    final amount = settlement['amount'] as Decimal;

    final isYourAction = currentUid != null && fromUserId == currentUid;
    final isCreditor = currentUid != null && toUserId == currentUid;
    final isHighlighted =
        preSelectedMemberId != null &&
        (fromUserId == preSelectedMemberId || toUserId == preSelectedMemberId);

    final tileKey = GlobalKey();
    tileKeys[index] = tileKey;

    final breakdown =
        buildBreakdown?.call(fromUserId, toUserId) ?? const <String, Decimal>{};

    return GroupSettlementTile(
          fromName: fromName,
          toName: toName,
          amount: amount,
          currency: currency,
          breakdown: breakdown,
          isYourAction: isYourAction,
          isCreditor: isCreditor,
          isHighlighted: isHighlighted,
          tileKey: tileKey,
          onRecord: isYourAction
              ? () {
                  assert(
                    rawNames.containsKey(fromUserId),
                    'rawNames must include every settlement participant',
                  );
                  assert(
                    rawNames.containsKey(toUserId),
                    'rawNames must include every settlement participant',
                  );
                  onRecord(
                    settlement: settlement,
                    fromRawName:
                        rawNames[fromUserId] ??
                        MemberNameResolver.stripFormerSuffix(fromName),
                    toRawName:
                        rawNames[toUserId] ??
                        MemberNameResolver.stripFormerSuffix(toName),
                    fromUserId: fromUserId,
                    toUserId: toUserId,
                    suggestedAmount: amount,
                  );
                }
              : null,
        )
        .animate()
        .fadeIn(delay: Duration(milliseconds: index * 50))
        .slideY(begin: 0.1, curve: Curves.easeOutCubic);
  }
}

class _SettlementIntro extends StatelessWidget {
  const _SettlementIntro({
    required this.transferCount,
    required this.subjectName,
  });

  final int transferCount;
  final String subjectName;

  @override
  Widget build(BuildContext context) {
    final headline = transferCount == 0
        ? "Everyone's even."
        : "$_countWord transfers,\neveryone's even.";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          headline,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 28,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w400,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            text: transferCount == 0
                ? 'No optimized payments are needed across '
                : 'Optimized to minimise the number of payments across ',
            children: [
              TextSpan(
                text: subjectName,
                style: TextStyle(
                  color: context.colors.ink2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const TextSpan(text: '.'),
            ],
          ),
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 13,
            height: 1.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String get _countWord {
    const words = {
      1: 'One',
      2: 'Two',
      3: 'Three',
      4: 'Four',
      5: 'Five',
      6: 'Six',
      7: 'Seven',
      8: 'Eight',
      9: 'Nine',
      10: 'Ten',
    };
    return words[transferCount] ?? transferCount.toString();
  }
}

class _NetBalancesSection extends StatelessWidget {
  const _NetBalancesSection({required this.balances, required this.currency});

  final List<UserBalance> balances;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(label: "Each person's net"),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: context.colors.cardSurface,
            borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
            border: Border.all(color: context.colors.rule),
            boxShadow: context.shadows.raised,
          ),
          child: Column(
            children: [
              for (var i = 0; i < balances.length; i++)
                _NetBalanceRow(
                  balance: balances[i],
                  currency: currency,
                  showDivider: i < balances.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NetBalanceRow extends StatelessWidget {
  const _NetBalanceRow({
    required this.balance,
    required this.currency,
    required this.showDivider,
  });

  final UserBalance balance;
  final String currency;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final name = balance.displayName ?? 'Unknown';
    final amountColor = balance.netBalance > Decimal.zero
        ? context.colors.successText
        : balance.netBalance < Decimal.zero
        ? context.colors.errorText
        : context.colors.textSecondary;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: showDivider
              ? BorderSide(color: context.colors.rule)
              : BorderSide.none,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _MiniAvatar(name: name),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            AppFormatters.formatCurrency(balance.netBalance, currency),
            style: TextStyle(
              color: amountColor,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: context.colors.saffronTint,
        shape: BoxShape.circle,
        border: Border.all(color: context.colors.rule2),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: context.colors.ink2,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: TextStyle(
          color: context.colors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Inline list of past recorded payments shown beneath net balances.
///
/// Wireframe omits this — kept as a low-emphasis footer so the feature
/// stays accessible without a dedicated tab or route.
class _PaymentHistorySection extends StatelessWidget {
  const _PaymentHistorySection({
    required this.settlements,
    required this.currency,
    required this.displayNames,
  });

  final List<Settlement> settlements;
  final String currency;
  final Map<String, String> displayNames;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(label: 'Payment history'),
        const SizedBox(height: 10),
        for (var i = 0; i < settlements.length; i++)
          _HistoryTile(
            settlement: settlements[i],
            currency: currency,
            displayNames: displayNames,
            index: i,
          ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.settlement,
    required this.currency,
    required this.displayNames,
    required this.index,
  });

  final Settlement settlement;
  final String currency;
  final Map<String, String> displayNames;
  final int index;

  @override
  Widget build(BuildContext context) {
    const spacing = AppSpacingTokens.standard;
    final payerId = settlement.payerParticipantId;
    final recipientId = settlement.recipientParticipantId;
    final payerName =
        (payerId == null ? null : displayNames[payerId]) ??
        settlement.payerName ??
        'Unknown';
    final recipientName =
        (recipientId == null ? null : displayNames[recipientId]) ??
        settlement.recipientName ??
        'Unknown';
    final dateStr = DateFormat('MMM d').format(settlement.settledAt);

    return Container(
          margin: EdgeInsets.only(bottom: spacing.space8),
          decoration: BoxDecoration(
            color: context.colors.cardSurface,
            borderRadius: BorderRadius.circular(spacing.radiusMedium),
            border: Border.all(color: context.colors.rule),
            boxShadow: context.shadows.raised,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: spacing.space16,
            vertical: spacing.space12,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: context.colors.success.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Iconsax.tick_circle,
                  size: 16,
                  color: context.colors.success,
                ),
              ),
              SizedBox(width: spacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 13,
                          color: context.colors.textPrimary,
                        ),
                        children: [
                          TextSpan(
                            text: payerName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const TextSpan(text: ' paid '),
                          TextSpan(
                            text: recipientName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                AppFormatters.formatCurrency(settlement.amount, currency),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: context.colors.textPrimary,
                ),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(delay: Duration(milliseconds: index * 40))
        .slideY(begin: 0.08, curve: Curves.easeOutCubic);
  }
}
