import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/utils/share_helper.dart';
import '../../../core/utils/whatsapp_share.dart';

import '../../../core/config/app_links.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../keys/group_keys.dart';
import '../models/group_model.dart';

/// T3.J — group invite QR sheet.
///
/// Encodes a `rihla-safar.web.app` universal link (the canonical Hosting
/// domain). Falls back gracefully to the 6-char code displayed in monospace
/// for manual entry.
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
        padding: EdgeInsetsDirectional.fromSTEB(
          context.spacing.space20,
          context.spacing.space12,
          context.spacing.space20,
          context.spacing.space20,
        ),
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
            SizedBox(height: context.spacing.space20),
            Text(
              context.l10n.groupScanToJoin,
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
            SizedBox(height: context.spacing.space24),
            _QrCard(
              uri: _inviteUri,
              semanticLabel: context.l10n.groupInviteQrCode,
            ),
            SizedBox(height: context.spacing.space20),
            Text(
              context.l10n.groupOrEnterCode,
              style: AppTypography.mono(
                fontSize: 10,
                letterSpacing: 1.5,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            _CodePill(code: group.inviteCode),
            SizedBox(height: context.spacing.space20),
            InviteActionRow(group: group),
          ],
        ),
      ),
    );
  }
}

/// Copy-link / WhatsApp / Share action row for a group invite.
///
/// Shared by the settings QR sheet and the post-create share prompt so both
/// surfaces offer the same channels — the post-create prompt used to offer
/// only copy + generic share, hiding WhatsApp/QR at the peak invite moment.
class InviteActionRow extends StatelessWidget {
  const InviteActionRow({super.key, required this.group});

  final Group group;

  Uri get _inviteUri => AppLinks.inviteUrl(group.inviteCode);

  String _inviteMessage(BuildContext context) =>
      context.l10n.groupShareInviteMessage(
        group.name,
        _inviteUri.toString(),
        group.inviteCode,
      );

  Future<void> _shareInvite(BuildContext context) {
    return shareText(
      context,
      _inviteMessage(context),
      subject: context.l10n.groupShareInviteSubject(group.name),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SheetButton(
            icon: Iconsax.copy,
            label: context.l10n.groupCopyLink,
            onTap: () async {
              HapticService.lightClick();
              await Clipboard.setData(
                ClipboardData(text: _inviteUri.toString()),
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.l10n.groupLinkCopied),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          // #354 — WhatsApp-direct invite (dominant GCC channel). Opens
          // WhatsApp prefilled with the same link-bearing message; falls
          // back to the OS share sheet when WhatsApp isn't installed.
          child: _SheetButton(
            key: GroupKeys.inviteWhatsAppButton,
            icon: Iconsax.message,
            label: context.l10n.groupShareViaWhatsApp,
            onTap: () {
              HapticService.lightClick();
              // The fallback runs after an async canLaunchUrl probe, so
              // the sheet may be gone by then — guard the context before
              // touching it (mirrors the Copy button above).
              shareInviteViaWhatsApp(
                _inviteMessage(context),
                fallback: () async {
                  if (!context.mounted) return;
                  await _shareInvite(context);
                },
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SheetButton(
            icon: Iconsax.send_2,
            label: context.l10n.groupShare,
            primary: true,
            onTap: () {
              HapticService.lightClick();
              _shareInvite(context);
            },
          ),
        ),
      ],
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
      padding: EdgeInsets.all(context.spacing.space16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(context.spacing.radiusCard),
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
      padding: EdgeInsets.symmetric(
        horizontal: context.spacing.space16,
        vertical: context.spacing.space8,
      ),
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(context.spacing.radiusPill),
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
    super.key,
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
          padding: EdgeInsets.symmetric(horizontal: context.spacing.space8),
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
