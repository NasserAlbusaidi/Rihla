import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

/// Sticky bottom bar with ink-primary "Add expense" and ghost "Settle up".
///
/// Settle button dims to 0.4 opacity when [settleEnabled] is false (zero balance).
class LedgerStickyCta extends StatelessWidget {
  const LedgerStickyCta({
    super.key,
    required this.onAddExpense,
    required this.onSettleUp,
    required this.settleEnabled,
  });

  final VoidCallback onAddExpense;
  final VoidCallback onSettleUp;
  final bool settleEnabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.scaffoldBackground,
        border: Border(top: BorderSide(color: colors.rule, width: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        14 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: _PrimaryCta(
                onTap: () {
                  HapticService.medium();
                  onAddExpense();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SecondaryCta(
                enabled: settleEnabled,
                onTap: () {
                  if (!settleEnabled) return;
                  HapticService.lightClick();
                  onSettleUp();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryCta extends StatelessWidget {
  const _PrimaryCta({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.textPrimary,
      borderRadius: BorderRadius.circular(9999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9999),
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Iconsax.add, size: 16, color: colors.scaffoldBackground),
              const SizedBox(width: 8),
              Text(
                context.l10n.ledgerAddExpense,
                style: AppTypography.sans(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: colors.scaffoldBackground,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryCta extends StatelessWidget {
  const _SecondaryCta({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9999),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(9999),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: colors.textPrimary, width: 1),
              borderRadius: BorderRadius.circular(9999),
            ),
            child: Text(
              context.l10n.ledgerSettleUp,
              style: AppTypography.sans(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
