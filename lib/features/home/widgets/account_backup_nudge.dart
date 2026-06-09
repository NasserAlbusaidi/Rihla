import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../auth/providers/auth_provider.dart';
import '../keys/home_keys.dart';

/// One-time, non-blocking home nudge to back up an anonymous account by linking
/// an email (#285).
///
/// Identity is a device-bound anonymous Firebase UID, so reinstall / new phone
/// / clear-data silently orphans every group and expense unless an email was
/// linked beforehand. This card surfaces that risk in plain terms the first
/// time a user has data to lose (it only mounts inside the loaded dashboard,
/// which renders once the user has ≥1 group).
///
/// It renders only while the user is purely anonymous and has not dismissed it;
/// linking an email flips [linkedEmailProvider] non-null and hides it for good,
/// independent of the dismiss flag.
class AccountBackupNudge extends ConsumerWidget {
  const AccountBackupNudge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAnonymous = ref.watch(linkedEmailProvider) == null;
    final dismissed = ref.watch(
      settingsProvider.select((s) => s.emailLinkNudgeSeen),
    );
    if (!isAnonymous || dismissed) return const SizedBox.shrink();

    final colors = context.colors;
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        spacing.space20,
        0,
        spacing.space20,
        spacing.space16,
      ),
      child: Container(
        key: HomeKeys.accountBackupNudge,
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
                    Iconsax.shield_tick,
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
                        context.l10n.homeBackupNudgeTitle,
                        style: AppTypography.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      SizedBox(height: spacing.space4),
                      Text(
                        context.l10n.homeBackupNudgeBody,
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
            SizedBox(height: spacing.space16),
            // Full-width stacked buttons (the home empty-state convention) so a
            // long localized label wraps inside the bounded width instead of
            // overflowing a horizontal row — the Arabic CTA is wide (#285).
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: HomeKeys.accountBackupNudgeCta,
                onPressed: () {
                  HapticService.lightClick();
                  context.push(AppRoutes.linkEmail);
                },
                child: Text(
                  context.l10n.homeBackupNudgeCta,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            SizedBox(height: spacing.space8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                key: HomeKeys.accountBackupNudgeDismiss,
                onPressed: () {
                  HapticService.lightClick();
                  ref
                      .read(settingsProvider.notifier)
                      .setEmailLinkNudgeSeen(true);
                },
                child: Text(
                  context.l10n.homeBackupNudgeDismiss,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
