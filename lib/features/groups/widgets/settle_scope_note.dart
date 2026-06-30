import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../keys/group_keys.dart';

/// Which ledger a settle-up surface acts on. Drives the scope note copy.
enum SettleScope { event, group }

/// Persistent, non-dismissible scope note pinned under the settle-up headline
/// (#717).
///
/// A `scope:'group'` settlement clears someone's *whole-group* net across every
/// event, but each event's own ledger keeps showing the full owe (the per-event
/// drill-down is `participantIds`-only by design). Nothing on either settle
/// surface said so, so users couldn't tell what a recorded payment actually
/// covered — settle the group, then the single-event ledger still reads "you
/// owe". This note names that up front. Display-only — no balance math, no
/// rules, no schema.
///
/// Unlike [CurrencyBucketsExplainer] it never burns a seen-flag: scope is
/// context that matters on every visit, not a one-time lesson, so it stays
/// pinned with no dismiss affordance.
class SettleScopeNote extends StatelessWidget {
  const SettleScopeNote({
    super.key,
    required this.scope,
    required this.subjectName,
  });

  final SettleScope scope;

  /// Event name on the event surface; group name on the group surface. Only the
  /// event copy interpolates it.
  final String subjectName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final text = switch (scope) {
      SettleScope.event => context.l10n.settleScopeNoteEvent(subjectName),
      SettleScope.group => context.l10n.settleScopeNoteGroup,
    };

    return Padding(
      padding: EdgeInsetsDirectional.only(top: spacing.space16),
      child: Container(
        key: GroupKeys.settleScopeNote,
        padding: EdgeInsets.all(spacing.space12),
        decoration: BoxDecoration(
          color: colors.cardSoft,
          borderRadius: BorderRadius.circular(spacing.radiusCard),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Iconsax.info_circle, size: 18, color: colors.primary),
            SizedBox(width: spacing.space12),
            Expanded(
              child: Text(
                text,
                style: AppTypography.sans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
