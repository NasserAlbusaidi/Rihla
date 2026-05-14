import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_links.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

/// Bottom sheet exposing Terms of Service and Privacy Policy links.
///
/// Each row opens its target URL via [launchUrl] in an external browser. URLs
/// live in [AppLinks].
class LegalLinksSheet extends StatelessWidget {
  const LegalLinksSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const LegalLinksSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return SafeArea(
      child: Container(
        margin: EdgeInsets.fromLTRB(
          spacing.space16,
          0,
          spacing.space16,
          spacing.space16,
        ),
        decoration: BoxDecoration(
          color: colors.cardSurface,
          borderRadius: BorderRadius.circular(spacing.radiusLarge),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: spacing.space12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(height: spacing.space16),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.space20),
              child: Row(
                children: [
                  Text(
                    'Legal',
                    style: AppTypography.sans(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.space8),
            const _LegalRow(
              icon: Iconsax.document_text,
              label: 'Terms of service',
              url: AppLinks.termsUrl,
            ),
            Divider(height: 1, color: colors.rule),
            const _LegalRow(
              icon: Iconsax.shield_tick,
              label: 'Privacy policy',
              url: AppLinks.privacyUrl,
            ),
            Divider(height: 1, color: colors.rule),
            const _LegalRow(
              icon: Iconsax.trash,
              label: 'Delete my data',
              url: AppLinks.deleteDataUrl,
            ),
            SizedBox(height: spacing.space8),
          ],
        ),
      ),
    );
  }
}

class _LegalRow extends StatelessWidget {
  const _LegalRow({
    required this.icon,
    required this.label,
    required this.url,
  });

  final IconData icon;
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return InkWell(
      onTap: () async {
        HapticService.lightClick();
        final messenger = ScaffoldMessenger.of(context);
        final navigator = Navigator.of(context);
        final ok = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        if (!ok) {
          messenger.showSnackBar(
            const SnackBar(content: Text("Couldn't open link")),
          );
        }
        if (navigator.canPop()) navigator.pop();
      },
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.space20,
          vertical: spacing.space16,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colors.textSecondary),
            SizedBox(width: spacing.space12),
            Expanded(
              child: Text(
                label,
                style: AppTypography.sans(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: colors.textPrimary,
                ),
              ),
            ),
            Icon(
              Iconsax.export_3,
              size: 16,
              color: colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
