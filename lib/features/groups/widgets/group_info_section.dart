import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/utils/share_helper.dart';

import '../../../core/config/app_links.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/localized_dates.dart';
import '../../home/widgets/group_glyph.dart';
import '../keys/group_keys.dart';
import '../models/group_model.dart';
import '../providers/group_provider.dart';
import 'qr_invite_sheet.dart';
import 'settings_section_header.dart';

/// Wireframe identity and invite cards for GroupSettingsScreen.
class GroupInfoSection extends ConsumerStatefulWidget {
  const GroupInfoSection({
    super.key,
    required this.group,
    required this.isCreator,
  });

  final Group group;
  final bool isCreator;

  @override
  ConsumerState<GroupInfoSection> createState() => _GroupInfoSectionState();
}

class _GroupInfoSectionState extends ConsumerState<GroupInfoSection> {
  final _nameController = TextEditingController();
  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveGroupName() async {
    final trimmed = _nameController.text.trim();
    if (trimmed.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.groupNameEmpty),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(groupServiceProvider)
          .updateGroup(groupId: widget.group.id, name: trimmed);
      if (mounted) {
        HapticService.success();
        setState(() {
          _isEditing = false;
          _isSaving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.groupUpdateNameFailed(e.toString())),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: GroupKeys.infoSection,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildIdentityCard(),
        const SizedBox(height: 10),
        SettingsSectionHeader(title: context.l10n.groupInvite),
        SizedBox(height: context.spacing.space8),
        _buildInviteCodeCard(),
      ],
    );
  }

  Widget _buildIdentityCard() {
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
              GroupGlyph(name: widget.group.name, size: 44),
              if (widget.isCreator)
                Positioned.directional(
                  textDirection: Directionality.of(context),
                  end: -4,
                  bottom: -4,
                  child: GestureDetector(
                    key: GroupKeys.groupNameEditIcon,
                    onTap: () {
                      HapticService.selection();
                      setState(() {
                        _isEditing = true;
                        _nameController.text = widget.group.name;
                      });
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
          Expanded(
            child: _isEditing ? _buildNameEditor() : _buildIdentityText(),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityText() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.group.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.display(
            fontSize: 22,
            color: context.colors.textPrimary,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          context.l10n.groupCreatedDateCurrency(
            _formatCreated(context, widget.group.createdAt),
            widget.group.currency,
          ),
          style: AppTypography.sans(
            fontSize: 12,
            color: context.colors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildNameEditor() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _nameController,
            autofocus: true,
            style: AppTypography.sans(
              fontSize: 14,
              color: context.colors.textPrimary,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              filled: false,
            ),
            onSubmitted: (_) => _saveGroupName(),
          ),
        ),
        _isSaving
            ? SizedBox(
                width: context.spacing.space20,
                height: context.spacing.space20,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                icon: Icon(Iconsax.tick_circle, color: context.colors.primary),
                onPressed: _saveGroupName,
              ),
      ],
    );
  }

  Widget _buildInviteCodeCard() {
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
                  widget.group.inviteCode,
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
                    ClipboardData(text: widget.group.inviteCode),
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
                  showGroupInviteQrSheet(context, group: widget.group);
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
                      widget.group.name,
                      AppLinks.inviteUrl(widget.group.inviteCode).toString(),
                      widget.group.inviteCode,
                    ),
                    subject: context.l10n.groupShareSubject(widget.group.name),
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
