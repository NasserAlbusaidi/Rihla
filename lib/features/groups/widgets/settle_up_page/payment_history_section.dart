import 'package:flutter/material.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../ledger/models/settlement_model.dart';
import '../../../ledger/utils/settlement_correction_affordance.dart';
import '../settle_up_page_body.dart';
import 'history_tile.dart';
import 'section_label.dart';

/// Inline list of past recorded payments shown beneath net balances.
///
/// Wireframe omits this — kept as a low-emphasis footer so the feature
/// stays accessible without a dedicated tab or route.
class PaymentHistorySection extends StatelessWidget {
  const PaymentHistorySection({
    required this.settlements,
    required this.displayNames,
    required this.subjectName,
    this.currentUid,
    this.groupCreatorId,
    this.currentMemberIds,
    this.onCorrect,
    this.onCorrectLogical,
  });

  final List<Settlement> settlements;
  final Map<String, String> displayNames;

  /// Group/event name folded into the shareable receipt (#359).
  final String subjectName;

  /// Actor policy inputs — see [SettleUpPageBody.groupCreatorId].
  final String? currentUid;
  final String? groupCreatorId;

  /// #283: hands a recorded payment back for an offsetting correction.
  final void Function(Settlement settlement)? onCorrect;

  /// #753: hands a `groupSettleUpId` back for an atomic logical correction.
  /// Non-null ONLY on the group screen — it also switches on the regroup.
  final void Function(String groupSettleUpId)? onCorrectLogical;

  /// #1149 party gate — see [SettleUpPageBody.currentMemberIds]. Null fails
  /// open; otherwise mirrors the callables' failed-precondition check
  /// (correctSettlement.ts / correctLogicalSettleUp.ts: both parties must be
  /// in FULL memberIds — ghosts stay correctable). Orthogonal to
  /// [_canCorrect], which is ACTOR eligibility.
  final Set<String>? currentMemberIds;

  bool _canCorrect(Settlement settlement) {
    if (groupCreatorId == null) return true;
    if (currentUid == null) return false;
    return currentUid == groupCreatorId ||
        settlement.payerParticipantId == currentUid ||
        settlement.recipientParticipantId == currentUid;
  }

  bool _partiesCurrent(Settlement settlement) {
    final ids = currentMemberIds;
    // Empty = malformed data, not "everyone departed" — fail open like null
    // (same reasoning as filterDepartedSuggestions).
    if (ids == null || ids.isEmpty) return true;
    return settlementPartiesAreCurrentMembers(settlement, ids);
  }

  @override
  Widget build(BuildContext context) {
    // #753: regroup tagged settle-ups into one logical row ONLY on the group
    // screen (where onCorrectLogical is wired). The event screen keeps the PR1
    // per-doc rendering (its settlements are one-event-only; a regrouped "total"
    // would be a misleading partial).
    final children = <Widget>[
      SectionLabel(label: context.l10n.settleUpPaymentHistory),
      const SizedBox(height: 10),
    ];

    if (onCorrectLogical == null) {
      for (var i = 0; i < settlements.length; i++) {
        final settlement = settlements[i];
        children.add(
          HistoryTile(
            settlement: settlement,
            displayNames: displayNames,
            subjectName: subjectName,
            index: i,
            onCorrect: (_canCorrect(settlement) && _partiesCurrent(settlement))
                ? onCorrect
                : null,
            soloCorrectionHidden: isSoloCorrectionHidden(
              settlement,
              settlements,
            ),
          ),
        );
      }
    } else {
      final rows = groupSettlementHistory(settlements);
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        switch (row) {
          case SoloHistoryRow(:final settlement):
            children.add(
              HistoryTile(
                settlement: settlement,
                displayNames: displayNames,
                subjectName: subjectName,
                index: i,
                onCorrect:
                    (_canCorrect(settlement) && _partiesCurrent(settlement))
                    ? onCorrect
                    : null,
                soloCorrectionHidden: isSoloCorrectionHidden(
                  settlement,
                  settlements,
                ),
              ),
            );
          case LogicalHistoryRow():
            children.add(
              HistoryTile(
                settlement: row.representative,
                displayNames: displayNames,
                subjectName: subjectName,
                index: i,
                overrideAmount: row.totalAmount,
                isCorrectedLogical: row.isCorrected,
                // Every leg of a decomposed settle-up shares one
                // payer→recipient pair, so the representative stands in for
                // the whole set; the server still checks EVERY original.
                onCorrectLogical:
                    (row.affordanceCorrected ||
                        !_canCorrect(row.representative) ||
                        !_partiesCurrent(row.representative))
                    ? null
                    : () => onCorrectLogical!(row.groupSettleUpId),
              ),
            );
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
