import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/haptic_service.dart';
import '../keys/group_keys.dart';
import '../models/group_model.dart';
import '../providers/group_provider.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// Group info section widget for GroupSettingsScreen.
///
/// Shows two tiles: group name (creator-only edit) and invite code (with copy).
/// Follows the ProfileAboutSection card pattern.
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
            color: context.colors.cardSurface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: context.shadows.raised,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildGroupNameTile(),
              Divider(height: 1, color: context.colors.inputFill),
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
          color: context.colors.textSecondary,
        ),
        const SizedBox(width: 6),
        Text(
          'GROUP',
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
                  color: context.colors.inputFill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(
                    Iconsax.text,
                    size: 18,
                    color: context.colors.textSecondary,
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
                        color: context.colors.primary,
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
                color: context.colors.inputFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  Iconsax.text,
                  size: 18,
                  color: context.colors.textSecondary,
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
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.group.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: context.colors.textPrimary,
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
                  color: context.colors.textSecondary,
                  semanticLabel: 'Edit group name',
                ),
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
              color: context.colors.inputFill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Icon(
                Iconsax.link,
                size: 18,
                color: context.colors.textSecondary,
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
                    color: context.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.group.inviteCode,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 4,
                    color: context.colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: GroupKeys.inviteCodeCopyButton,
            icon: Icon(
              Iconsax.copy,
              color: context.colors.textSecondary,
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
