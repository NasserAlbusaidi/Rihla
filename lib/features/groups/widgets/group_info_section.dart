import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';
import '../keys/group_keys.dart';
import '../models/group_model.dart';
import '../providers/group_provider.dart';

/// Group info section widget for GroupSettingsScreen.
///
/// Shows three tiles: group name (creator-only edit), currency (with picker),
/// and invite code (with copy). Follows the ProfileAboutSection card pattern.
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

  static const _currencies = [
    'OMR',
    'USD',
    'EUR',
    'GBP',
    'SAR',
    'AED',
    'KWD',
    'BHD',
    'QAR',
  ];

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
          const SnackBar(
            content: Text("Group name can't be empty."),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(groupServiceProvider).updateGroup(
            groupId: widget.group.id,
            name: trimmed,
          );
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
            content: Text('Failed to update name: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _showCurrencyPicker(BuildContext ctx) async {
    await showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: AppColorTokens.light.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                'Select Currency',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColorTokens.light.textPrimary,
                ),
              ),
            ),
            ..._currencies.map(
              (c) => ListTile(
                title: Text(c),
                trailing: c == widget.group.currency
                    ? Icon(Iconsax.tick_circle, color: AppColorTokens.light.primary)
                    : null,
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  try {
                    await ref.read(groupServiceProvider).updateGroup(
                          groupId: widget.group.id,
                          currency: c,
                        );
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to update currency: $e'),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: GroupKeys.infoSection,
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
              _buildGroupNameTile(),
              Divider(height: 1, color: AppColorTokens.light.inputFill),
              _buildCurrencyTile(),
              Divider(height: 1, color: AppColorTokens.light.inputFill),
              _buildInviteCodeTile(),
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
          Iconsax.setting_2,
          size: 16,
          color: AppColorTokens.light.textSecondary,
        ),
        const SizedBox(width: 6),
        Text(
          'GROUP',
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

  Widget _buildGroupNameTile() {
    if (_isEditing) {
      return GestureDetector(
        key: GroupKeys.settingsGroupNameTile,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColorTokens.light.inputFill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(
                    Iconsax.text,
                    size: 18,
                    color: AppColorTokens.light.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _nameController,
                  autofocus: true,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppColorTokens.light.textPrimary,
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
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: Padding(
                        padding: EdgeInsets.all(2),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: Icon(
                        Iconsax.tick_circle,
                        color: AppColorTokens.light.primary,
                      ),
                      onPressed: _saveGroupName,
                    ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      key: GroupKeys.settingsGroupNameTile,
      onTap: null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColorTokens.light.inputFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  Iconsax.text,
                  size: 18,
                  color: AppColorTokens.light.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Group Name',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColorTokens.light.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.group.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColorTokens.light.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.isCreator)
              GestureDetector(
                key: GroupKeys.groupNameEditIcon,
                onTap: () {
                  HapticService.selection();
                  setState(() {
                    _isEditing = true;
                    _nameController.text = widget.group.name;
                  });
                },
                child: Icon(
                  Iconsax.edit_2,
                  size: 18,
                  color: AppColorTokens.light.textSecondary,
                  semanticLabel: 'Edit group name',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrencyTile() {
    return GestureDetector(
      key: GroupKeys.settingsCurrencyTile,
      onTap: () {
        HapticService.selection();
        _showCurrencyPicker(context);
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColorTokens.light.inputFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  Iconsax.money_4,
                  size: 18,
                  color: AppColorTokens.light.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Currency',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColorTokens.light.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.group.currency,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColorTokens.light.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Iconsax.arrow_right_3,
              size: 16,
              color: AppColorTokens.light.textSecondary,
              semanticLabel: 'Change currency',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteCodeTile() {
    return Padding(
      key: GroupKeys.settingsInviteCodeTile,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColorTokens.light.inputFill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Icon(
                Iconsax.link,
                size: 18,
                color: AppColorTokens.light.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Invite Code',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColorTokens.light.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.group.inviteCode,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 4,
                    color: AppColorTokens.light.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: GroupKeys.inviteCodeCopyButton,
            icon: Icon(
              Iconsax.copy,
              color: AppColorTokens.light.textSecondary,
              semanticLabel: 'Copy invite code',
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.group.inviteCode));
              HapticService.success();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Invite code copied'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
