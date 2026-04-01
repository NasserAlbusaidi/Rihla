import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_metadata.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';
import '../keys/profile_keys.dart';

/// About section widget for ProfileScreen.
///
/// Displays three tiles: app version (INFO-01), send feedback (INFO-02),
/// and open-source licenses (INFO-03).
class ProfileAboutSection extends ConsumerWidget {
  const ProfileAboutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metadataAsync = ref.watch(appMetadataProvider);
    final metadata = metadataAsync.valueOrNull;

    final versionText = metadataAsync.when(
      data: (m) => 'v${m.version}',
      loading: () => '...',
      error: (err, st) => '...',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColorTokens.light.cardSurface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppShadowTokens.standard.raised,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Version tile — non-tappable (D-09)
              _buildTile(
                tileKey: ProfileKeys.versionTile,
                icon: Iconsax.code,
                title: 'Version',
                trailing: Text(
                  versionText,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColorTokens.light.textSecondary,
                  ),
                ),
                onTap: null,
              ),
              Divider(height: 1, color: AppColorTokens.light.inputFill),
              // Send Feedback tile (D-10)
              _buildTile(
                tileKey: ProfileKeys.feedbackTile,
                icon: Iconsax.message_question,
                title: 'Send Feedback',
                trailing: Icon(
                  Iconsax.arrow_right_3,
                  size: 16,
                  color: AppColorTokens.light.textSecondary,
                ),
                onTap: () => _launchFeedback(context, ref, metadata),
              ),
              Divider(height: 1, color: AppColorTokens.light.inputFill),
              // Open-source Licenses tile (D-11)
              _buildTile(
                tileKey: ProfileKeys.licensesTile,
                icon: Iconsax.document_text,
                title: 'Open-source Licenses',
                trailing: Icon(
                  Iconsax.arrow_right_3,
                  size: 16,
                  color: AppColorTokens.light.textSecondary,
                ),
                onTap: () => _showLicenses(context, metadata),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader() {
    return Row(
      children: [
        Icon(
          Iconsax.info_circle,
          size: 16,
          color: AppColorTokens.light.textSecondary,
        ),
        const SizedBox(width: 6),
        Text(
          'ABOUT',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColorTokens.light.textSecondary,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildTile({
    required Key tileKey,
    required IconData icon,
    required String title,
    required Widget trailing,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      key: tileKey,
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // 36px icon container (D-03)
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColorTokens.light.inputFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 18,
                  color: AppColorTokens.light.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColorTokens.light.textPrimary,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  Future<void> _launchFeedback(
    BuildContext context,
    WidgetRef ref,
    AppMetadata? metadata,
  ) async {
    final resolvedMetadata =
        metadata ?? ref.read(appMetadataProvider).valueOrNull ?? AppMetadata.fallback();

    final uri = Uri(
      scheme: 'mailto',
      path: 'feedback@rihla.app',
      query: _encodeQueryParameters({
        'subject': 'Rihla Feedback (v${resolvedMetadata.version})',
      }),
    );

    final canLaunch = await canLaunchUrl(uri);
    if (canLaunch) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email: feedback@rihla.app')),
      );
    }
  }

  void _showLicenses(BuildContext context, AppMetadata? metadata) {
    showLicensePage(
      context: context,
      applicationName: 'Rihla',
      applicationVersion: metadata?.version ?? '',
      applicationLegalese: '(c) 2026 Rihla',
    );
  }

  String _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');
  }
}
