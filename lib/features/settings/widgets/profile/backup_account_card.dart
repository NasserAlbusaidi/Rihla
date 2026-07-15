import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../../shared/widgets/directional_icon.dart';
import '../../../auth/widgets/durable_credential_sheet.dart';
import '../../keys/profile_keys.dart';

/// Anonymous-only card that names the stakes of not being backed up and routes
/// to the durable-credential (Google/email) flow (#487). Hidden once durable.
class BackupAccountCard extends StatelessWidget {
  const BackupAccountCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
      child: GestureDetector(
        onTap: () {
          HapticService.selection();
          showDurableCredentialSheet(context);
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          key: ProfileKeys.backupAccountCard,
          padding: EdgeInsets.all(context.spacing.space16),
          decoration: BoxDecoration(
            color: colors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
            border: Border.all(
              color: colors.warning.withValues(alpha: 0.35),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.warning.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(Iconsax.warning_2, size: 20, color: colors.warning),
              ),
              SizedBox(width: context.spacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.profileBackupCardTitle,
                      style: AppTypography.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    SizedBox(height: context.spacing.space4),
                    Text(
                      // #1256 Task 9b: the sheet offers Apple + Google on
                      // iOS — provider-neutral copy there; Android unchanged.
                      defaultTargetPlatform == TargetPlatform.iOS
                          ? l10n.profileBackupCardBodyIos
                          : l10n.profileBackupCardBody,
                      style: AppTypography.sans(
                        fontSize: 12,
                        color: colors.textSecondary,
                        height: 1.35,
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
    );
  }
}
