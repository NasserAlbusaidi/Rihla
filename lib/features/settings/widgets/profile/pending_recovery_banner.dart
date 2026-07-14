import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../../shared/widgets/directional_icon.dart';
import '../../../auth/providers/auth_email_link_bootstrap_provider.dart';
import '../../keys/profile_keys.dart';

/// Renders only when `pendingEmailLinkProvider` holds a magic-link URL the
/// bootstrap could not auto-complete (no pending email was primed — e.g. the
/// link was opened on a fresh install or different device). Routes to
/// `/recover` so the user can enter the email and finish the flow.
class PendingRecoveryBanner extends ConsumerWidget {
  const PendingRecoveryBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingLink = ref.watch(pendingEmailLinkProvider);
    if (pendingLink == null) return const SizedBox.shrink();

    final colors = context.colors;
    return Padding(
      key: ProfileKeys.pendingRecoveryBanner,
      padding: EdgeInsets.fromLTRB(
        context.spacing.space20,
        context.spacing.space12,
        context.spacing.space20,
        context.spacing.space4,
      ),
      child: Material(
        color: colors.cardSoft,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            HapticService.selection();
            context.push('/recover');
          },
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: context.spacing.space12,
            ),
            child: Row(
              children: [
                Icon(Iconsax.sms_tracking, size: 18, color: colors.textPrimary),
                SizedBox(width: context.spacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.profileFinishRecovery,
                        style: AppTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.profileRecoverySubtitle,
                        style: AppTypography.sans(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: context.spacing.space8),
                DirectionalIcon(
                  Iconsax.arrow_right_3,
                  size: 16,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
