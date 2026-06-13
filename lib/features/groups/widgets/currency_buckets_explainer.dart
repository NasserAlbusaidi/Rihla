import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../keys/group_keys.dart';

/// One-time, inline explainer shown in the settle-up body when a group has
/// balances in two or more currency buckets (#382 PR-5).
///
/// Each currency settles on its own — Rihla never invents an exchange rate, so
/// e.g. OMR can't cancel out AED, and the optimizer plans one payment per
/// currency. That can read as "simplify is broken" the first time a user sees
/// it, so this card says why up front.
///
/// Inline-and-always-presentable (the #285 [AccountBackupNudge] pattern, not
/// the #352 modal tri-state): no null-gate is needed because a widget in the
/// tree always renders. The seen flag is burned ONLY on an explicit "Got it"
/// tap, so closing the screen never silently consumes the one-time card.
class CurrencyBucketsExplainer extends ConsumerWidget {
  const CurrencyBucketsExplainer({super.key, required this.bucketCount});

  /// Number of currency buckets in the current settle-up view. The card shows
  /// only when this is ≥2 (a single-currency group never sees it).
  final int bucketCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = ref.watch(
      settingsProvider.select((s) => s.currencyExplainerSeen),
    );
    if (bucketCount < 2 || seen) return const SizedBox.shrink();

    final colors = context.colors;
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsetsDirectional.only(top: spacing.space16),
      child: Container(
        key: GroupKeys.currencyExplainerCard,
        padding: EdgeInsets.all(spacing.space16),
        decoration: BoxDecoration(
          color: colors.cardSoft,
          borderRadius: BorderRadius.circular(spacing.radiusCard),
          border: Border.all(
            color: colors.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.all(spacing.space8),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(spacing.radiusInput),
                  ),
                  child: Icon(
                    Iconsax.info_circle,
                    size: 20,
                    color: colors.primary,
                  ),
                ),
                SizedBox(width: spacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.currencyExplainerTitle,
                        style: AppTypography.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      SizedBox(height: spacing.space4),
                      Text(
                        context.l10n.currencyExplainerBody,
                        style: AppTypography.sans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: colors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.space12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: GroupKeys.currencyExplainerGotIt,
                onPressed: () {
                  HapticService.lightClick();
                  ref
                      .read(settingsProvider.notifier)
                      .setCurrencyExplainerSeen(true);
                },
                child: Text(context.l10n.currencyExplainerGotIt),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
