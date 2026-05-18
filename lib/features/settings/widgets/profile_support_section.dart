import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_links.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../shared/widgets/directional_icon.dart';
import '../keys/profile_keys.dart';

/// Support section widget for ProfileScreen.
///
/// Displays a "Buy me a coffee" placeholder tile (SUPP-01) that shows a
/// "Coming soon" SnackBar on tap (D-12, D-13).
class ProfileSupportSection extends StatelessWidget {
  const ProfileSupportSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context),
        SizedBox(height: context.spacing.space8),
        Container(
          decoration: BoxDecoration(
            color: context.colors.cardSurface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: context.shadows.raised,
          ),
          child: _buildCoffeeTile(context),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context) {
    return Row(
      children: [
        Icon(
          Iconsax.heart,
          size: 16,
          color: context.colors.textSecondary,
        ),
        const SizedBox(width: 6),
        Text(
          context.l10n.profileSupportSectionLabel,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.colors.textSecondary,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildCoffeeTile(BuildContext context) {
    return GestureDetector(
      key: ProfileKeys.coffeeTile,
      onTap: () async {
        HapticService.lightClick();
        final messenger = ScaffoldMessenger.of(context);
        final paypalFailed = context.l10n.profileSupportPaypalFailed;
        final ok = await launchUrl(
          Uri.parse(AppLinks.paypalUrl),
          mode: LaunchMode.externalApplication,
        );
        if (!ok) {
          messenger.showSnackBar(
            SnackBar(content: Text(paypalFailed)),
          );
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space16,
          vertical: context.spacing.space8,
        ),
        child: Row(
          children: [
            // 36px icon container (D-03)
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: context.colors.inputFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  Iconsax.coffee,
                  size: 18,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
            SizedBox(width: context.spacing.space12),
            Expanded(
              child: Text(
                context.l10n.profileSupportCoffeeTile,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            DirectionalIcon(
              Iconsax.arrow_right_3,
              size: 16,
              color: context.colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
