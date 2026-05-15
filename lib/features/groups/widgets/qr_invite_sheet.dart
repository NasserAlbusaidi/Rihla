import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/app_links.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../keys/group_keys.dart';
import '../models/group_model.dart';

/// T3.J — group invite QR sheet.
///
/// Encodes a Firebase-hosted universal link until the custom `rihla.app`
/// domain is wired to Hosting. Falls back gracefully to the
/// 6-char code displayed in monospace for manual entry.
Future<void> showGroupInviteQrSheet(
  BuildContext context, {
  required Group group,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.scaffoldBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _QrInviteSheet(group: group),
  );
}

class _QrInviteSheet extends StatelessWidget {
  const _QrInviteSheet({required this.group});

  final Group group;

  Uri get _inviteUri => AppLinks.inviteUrl(group.inviteCode);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
              'Scan to join',
              style: AppTypography.display(
                fontSize: 22,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              group.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.sans(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            _QrCard(uri: _inviteUri, semanticLabel: 'Invite QR code'),
            const SizedBox(height: 20),
            Text(
              'OR ENTER CODE',
              style: AppTypography.mono(
                fontSize: 10,
                letterSpacing: 1.5,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            _CodePill(code: group.inviteCode),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _SheetButton(
                    icon: Iconsax.copy,
                    label: 'Copy link',
                    onTap: () async {
                      HapticService.lightClick();
                      await Clipboard.setData(
                        ClipboardData(text: _inviteUri.toString()),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Link copied'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SheetButton(
                    icon: Iconsax.send_2,
                    label: 'Share',
                    primary: true,
                    onTap: () {
                      HapticService.lightClick();
                      Share.share(
                        "Join '${group.name}' on Rihla: $_inviteUri "
                        '(code ${group.inviteCode})',
                        subject: "Join '${group.name}' on Rihla",
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.uri, required this.semanticLabel});

  final Uri uri;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: GroupKeys.inviteQrCard,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: context.shadows.raised,
      ),
      child: QrImageView(
        data: uri.toString(),
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
        semanticsLabel: semanticLabel,
      ),
    );
  }
}

class _CodePill extends StatelessWidget {
  const _CodePill({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: colors.rule, width: 0.5),
      ),
      child: Text(
        code,
        style: AppTypography.mono(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 4,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = primary ? colors.primary : colors.cardSurface;
    final fg = primary ? colors.textOnPrimary : colors.textPrimary;
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: fg),
        label: Text(
          label,
          style: AppTypography.sans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: primary
                ? BorderSide.none
                : BorderSide(color: colors.rule2, width: 0.5),
          ),
        ),
      ),
    );
  }
}
