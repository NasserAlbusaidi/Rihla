import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../shared/widgets/empty_state_view.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import 'group_settlement_tile.dart';

/// Presentational widget that renders a single tab of settlement tiles.
///
/// Displays a [ListView] of [GroupSettlementTile] widgets when
/// [settlements] is non-empty, or a themed empty-state otherwise.
///
/// Extracted from [GroupSettleUpScreen._buildSettlementTabContent]
/// (Phase 36 Plan 01). Pure presentational — does not read Riverpod.
class SettlementTabContent extends StatelessWidget {
  /// Optimal settlements to display in this tab.
  final List<Map<String, dynamic>> settlements;

  /// Whether the settlement belongs to the current user's action (You Owe tab).
  final bool isYourAction;

  /// Whether the current user is the creditor (Owed to You tab).
  final bool isCreditor;

  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final String currency;

  /// Per-tile GlobalKeys for auto-scroll targeting.
  final Map<int, GlobalKey> tileKeys;

  /// The pre-selected member ID, used for highlight logic.
  final String? preSelectedMemberId;

  /// Callback invoked when a tile's "Record Payment" is tapped.
  final void Function({
    required Map<String, dynamic> settlement,
    required String fromName,
    required String toName,
    required String fromUserId,
    required String toUserId,
    required Decimal suggestedAmount,
  }) onRecord;

  /// Builds the per-event breakdown for a settlement pair.
  final Map<String, Decimal> Function(String fromUserId, String toUserId)
      buildBreakdown;

  const SettlementTabContent({
    super.key,
    required this.settlements,
    required this.isYourAction,
    required this.isCreditor,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.currency,
    required this.tileKeys,
    required this.onRecord,
    required this.buildBreakdown,
    this.preSelectedMemberId,
  });

  @override
  Widget build(BuildContext context) {
    if (settlements.isEmpty) {
      return EmptyStateView(
        icon: emptyIcon,
        title: emptyTitle,
        message: emptyMessage,
        iconColor: AppColorTokens.light.textSecondary,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      physics: const BouncingScrollPhysics(),
      itemCount: settlements.length,
      itemBuilder: (context, index) {
        final settlement = settlements[index];
        final fromUserId = settlement['fromUserId'] as String;
        final toUserId = settlement['toUserId'] as String;
        final fromName = settlement['fromUserName'] as String;
        final toName = settlement['toUserName'] as String;
        final amount = settlement['amount'] as Decimal;
        final isHighlighted = preSelectedMemberId != null &&
            (fromUserId == preSelectedMemberId ||
                toUserId == preSelectedMemberId);

        final tileKey = GlobalKey();
        tileKeys[index] = tileKey;

        final breakdown = buildBreakdown(fromUserId, toUserId);

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
          onRecord: () => onRecord(
            settlement: settlement,
            fromName: fromName,
            toName: toName,
            fromUserId: fromUserId,
            toUserId: toUserId,
            suggestedAmount: amount,
          ),
        )
            .animate()
            .fadeIn(delay: Duration(milliseconds: index * 50))
            .slideY(begin: 0.1, curve: Curves.easeOutCubic);
      },
    );
  }
}
