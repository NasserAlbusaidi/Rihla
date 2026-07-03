import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/app_links.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/localized_dates.dart';
import '../../../core/utils/share_helper.dart';
import '../../home/widgets/group_glyph.dart';
import '../keys/group_keys.dart';
import '../models/group_model.dart';
import 'group_edit_sheet.dart';
import 'qr_invite_sheet.dart';
import 'settings_section_header.dart';

/// Wireframe identity and invite cards for GroupSettingsScreen.
///
/// The creator-only ✎ on the identity card opens [GroupEditSheet] (name +
/// trip-stamp in one atomic save). There is no inline name editor anymore —
/// editing lives entirely in the sheet.
class GroupInfoSection extends ConsumerWidget {
  const GroupInfoSection({
    super.key,
    required this.group,
    required this.isCreator,
  });

  final Group group;
  final bool isCreator;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      key: GroupKeys.infoSection,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildIdentityCard(context),
        const SizedBox(height: 10),
        SettingsSectionHeader(title: context.l10n.groupInvite),
        SizedBox(height: context.spacing.space8),
        _buildInviteCodeCard(context),
      ],
    );
  }

  Widget _buildIdentityCard(BuildContext context) {
    final spacing = context.spacing;
    return Container(
      key: GroupKeys.settingsGroupNameTile,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(spacing.radiusLarge),
        boxShadow: context.shadows.raised,
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              GroupGlyph(
                name: group.name,
                glyph: group.glyph,
                inkIndex: group.inkIndex,
                size: 44,
              ),
              if (isCreator)
                Positioned.directional(
                  textDirection: Directionality.of(context),
                  end: -4,
                  bottom: -4,
                  child: GestureDetector(
                    key: GroupKeys.groupNameEditIcon,
                    onTap: () {
                      HapticService.selection();
                      GroupEditSheet.show(context, group: group);
                    },
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: context.colors.textPrimary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.colors.cardSurface,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Iconsax.edit_2,
                        size: 10,
                        color: context.colors.cardSurface,
                        semanticLabel: context.l10n.groupEditNameSemantic,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(child: _buildIdentityText(context)),
        ],
      ),
    );
  }

  Widget _buildIdentityText(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          group.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.displayOf(
            context,
            fontSize: 22,
            color: context.colors.textPrimary,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          context.l10n.groupCreatedDateCurrency(
            _formatCreated(context, group.createdAt),
            group.currency,
          ),
          style: AppTypography.sans(
            fontSize: 12,
            color: context.colors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildInviteCodeCard(BuildContext context) {
    final spacing = context.spacing;
    return Container(
      key: GroupKeys.settingsInviteCodeTile,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(spacing.radiusLarge),
        boxShadow: context.shadows.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.groupAnyoneWithCodeCanJoin,
            style: AppTypography.sans(
              fontSize: 12,
              color: context.colors.textSecondary,
            ),
          ),
          SizedBox(height: context.spacing.space8),
          Row(
            children: [
              Expanded(
                child: Text(
                  group.inviteCode,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.mono(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 4,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              SizedBox(width: context.spacing.space12),
              _InviteIconButton(
                key: GroupKeys.inviteCodeCopyButton,
                icon: Iconsax.copy,
                semanticLabel: context.l10n.groupCopyInviteCodeSemantic,
                onTap: () {
                  Clipboard.setData(
                    ClipboardData(text: group.inviteCode),
                  );
                  HapticService.success();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.l10n.groupInviteCodeCopied),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
              const SizedBox(width: 6),
              _InviteIconButton(
                icon: Iconsax.scan_barcode,
                semanticLabel: context.l10n.groupShowQrCodeSemantic,
                onTap: () {
                  HapticService.selection();
                  showGroupInviteQrSheet(context, group: group);
                },
              ),
              const SizedBox(width: 6),
              _InviteIconButton(
                icon: Iconsax.send_2,
                semanticLabel: context.l10n.groupShareInviteSemantic,
                onTap: () {
                  HapticService.selection();
                  shareText(
                    context,
                    context.l10n.groupShareInviteMessage(
                      group.name,
                      AppLinks.inviteUrl(group.inviteCode).toString(),
                      group.inviteCode,
                    ),
                    subject: context.l10n.groupShareSubject(group.name),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatCreated(BuildContext context, DateTime createdAt) =>
      formatShortMonthDay(context, createdAt);
}

class _InviteIconButton extends StatelessWidget {
  const _InviteIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.cardSoft,
      shape: const CircleBorder(),
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: context.spacing.space32,
          height: context.spacing.space32,
          child: Icon(
            icon,
            size: 16,
            color: context.colors.textPrimary,
            semanticLabel: semanticLabel,
          ),
        ),
      ),
    );
  }
}
