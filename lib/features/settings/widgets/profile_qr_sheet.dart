import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../keys/profile_keys.dart';

/// T3.K — profile handle QR sheet.
///
/// Encodes `https://rihla.app/u/<handle>` for in-person handle exchange.
/// No inbound routing today — handles aren't claimable yet — so the QR
/// is a visual artifact. Wires alongside the group invite QR (T3.J) so
/// the qr_flutter integration is amortised across both surfaces.
Future<void> showProfileQrSheet(
  BuildContext context, {
  required String displayName,
  required String handle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.scaffoldBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _ProfileQrSheet(
      displayName: displayName,
      handle: handle,
    ),
  );
}

class _ProfileQrSheet extends StatelessWidget {
  const _ProfileQrSheet({required this.displayName, required this.handle});

  final String displayName;
  final String handle;

  String get _handleSlug =>
      handle.startsWith('@') ? handle.substring(1) : handle;
  Uri get _profileUri => Uri.parse('https://rihla.app/u/$_handleSlug');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.rule2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.qrSheetTitle,
              style: AppTypography.display(
                fontSize: 22,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.sans(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              key: ProfileKeys.qrCard,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: context.shadows.raised,
              ),
              child: QrImageView(
                data: _profileUri.toString(),
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
                eyeStyle: QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: colors.textPrimary,
                ),
                dataModuleStyle: QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: colors.textPrimary,
                ),
                semanticsLabel: l10n.qrSemanticsLabel,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              handle,
              style: AppTypography.mono(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  HapticService.lightClick();
                  final messenger = ScaffoldMessenger.of(context);
                  final handleCopied = l10n.qrHandleCopied;
                  await Clipboard.setData(ClipboardData(text: handle));
                  if (!context.mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(handleCopied),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                icon: Icon(Iconsax.copy, size: 16, color: colors.textPrimary),
                label: Text(
                  l10n.qrCopyHandle,
                  style: AppTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.cardSurface,
                  foregroundColor: colors.textPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: colors.rule2, width: 0.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
