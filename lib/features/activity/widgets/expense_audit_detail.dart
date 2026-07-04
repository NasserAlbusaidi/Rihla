import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/r_amount.dart';
import '../utils/expense_audit_diff.dart';

/// Renders the before/after field-change detail under an expense audit row
/// (#248 PR 3, narrowed by #490 D-g).
///
/// UPDATE with money-field changes: one `before → after` line per changed
/// field (description, amount, payer). Payer uids resolve to names via
/// [participantNames]; unknown ids fall back to the localized "Someone".
///
/// Every other case — CREATE, DELETE, and UPDATEs with no rendered-field
/// change — renders `SizedBox.shrink()`: those rows show their amount via
/// `ActivityRow.trailingAmount` instead, so rendering it here too would
/// duplicate it.
class ExpenseAuditDetail extends StatelessWidget {
  const ExpenseAuditDetail({
    super.key,
    required this.diff,
    required this.eventType,
    required this.participantNames,
  });

  final ExpenseAuditDiff diff;

  /// CREATE / UPDATE / DELETE (from `ActivityLog.eventType`).
  final String eventType;

  /// uid → display name, from the event's `participantNames` map.
  final Map<String, String> participantNames;

  static const double _textSize = 12;
  static const double _amountSize = 13;

  @override
  Widget build(BuildContext context) {
    if (eventType != 'UPDATE' || !diff.hasFieldChange) {
      return const SizedBox.shrink();
    }
    final before = diff.before!;
    final after = diff.after!;

    final lines = <Widget>[
      if (diff.descriptionChanged)
        _textChangeRow(context, before.description, after.description),
      if (diff.amountChanged) _amountChangeRow(context, before, after),
      if (diff.payerChanged)
        _payerChangeRow(
          context,
          before.payerParticipantId,
          after.payerParticipantId,
        ),
    ];

    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
              child: lines[i],
            ),
        ],
      ),
    );
  }

  // ── line builders ─────────────────────────────────────────────────────

  Widget _amountChangeRow(
    BuildContext context,
    ExpenseAuditSnap before,
    ExpenseAuditSnap after,
  ) {
    final sameCurrency = before.currency == after.currency;
    return Row(
      children: [
        _amount(context, before),
        _arrow(context),
        _amount(context, after, showCurrency: !sameCurrency),
      ],
    );
  }

  Widget _textChangeRow(BuildContext context, String? before, String? after) {
    return Row(
      children: [
        Flexible(
          child: Text(
            before ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _textStyle(context),
          ),
        ),
        _arrow(context),
        Flexible(
          child: Text(
            after ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _textStyle(context),
          ),
        ),
      ],
    );
  }

  Widget _payerChangeRow(BuildContext context, String? before, String? after) {
    final label = context.l10n.activityAuditPayerLabel;
    return Row(
      children: [
        Text('$label: ', style: _textStyle(context)),
        Flexible(
          child: Text(
            _name(context, before),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _textStyle(context),
          ),
        ),
        _arrow(context),
        Flexible(
          child: Text(
            _name(context, after),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _textStyle(context),
          ),
        ),
      ],
    );
  }

  // ── primitives ────────────────────────────────────────────────────────

  Widget _amount(
    BuildContext context,
    ExpenseAuditSnap snap, {
    bool showCurrency = true,
  }) {
    return RAmount(
      value: snap.amount,
      currency: snap.currency,
      showCurrency: showCurrency,
      size: _amountSize,
      tone: AmountTone.ink,
    );
  }

  Widget _arrow(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 6),
      child: Icon(
        rtl ? Iconsax.arrow_left : Iconsax.arrow_right,
        size: 12,
        color: context.colors.textSecondary,
      ),
    );
  }

  String _name(BuildContext context, String? uid) {
    if (uid == null) return context.l10n.activitySomeone;
    final name = participantNames[uid];
    return (name != null && name.isNotEmpty)
        ? name
        : context.l10n.activitySomeone;
  }

  TextStyle _textStyle(BuildContext context) => AppTypography.sans(
    fontSize: _textSize,
    color: context.colors.textSecondary,
  );
}
