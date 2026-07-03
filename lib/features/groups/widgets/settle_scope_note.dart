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
/// Since #752, a `scope:'group'` settlement DECOMPOSES into per-event
/// settlement writes wherever the payer/recipient pair shares attribution on
/// an event (`_recordDecomposedSettlement`), plus one residual group-level
/// settlement for whatever can't be attributed to a specific event; only a
/// departed-party/zero-attribution transfer still falls back to a single
/// group-level write. Nothing on either settle surface said what a recorded
/// payment actually covers, so this note names it up front. Display-only —
/// no balance math, no rules, no schema.
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
