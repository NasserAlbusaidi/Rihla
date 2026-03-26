import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/group_provider.dart';

/// Screen for managing group settings — name (creator-only), currency, and
/// invite code display (D-15, D-16, D-22).
class GroupSettingsScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupSettingsScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupSettingsScreen> createState() =>
      _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends ConsumerState<GroupSettingsScreen> {
  final _nameController = TextEditingController();

  /// Whether the inline rename TextField is shown.
  bool _isEditing = false;

  /// Whether a save operation is in progress.
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

  /// Save the renamed group name to Firestore.
  ///
  /// Shows a SnackBar on success or error.
  Future<void> _saveGroupName(String groupId) async {
    final trimmed = _nameController.text.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Group name can't be empty."),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(groupServiceProvider)
          .updateGroup(groupId: groupId, name: trimmed);
      if (mounted) {
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

  /// Show a modal bottom sheet currency picker and persist the selection.
  Future<void> _showCurrencyPicker(BuildContext ctx, String groupId, String currentCurrency) async {
    await showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppColors.space24,
                AppColors.space24,
                AppColors.space24,
                AppColors.space8,
              ),
              child: Text(
                'Select Currency',
                style: Theme.of(sheetCtx).textTheme.titleMedium,
              ),
            ),
            ..._currencies.map(
              (c) => ListTile(
                title: Text(c),
                trailing: c == currentCurrency
                    ? const Icon(Iconsax.tick_circle, color: AppColors.primary)
                    : null,
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  try {
                    await ref.read(groupServiceProvider).updateGroup(
                          groupId: groupId,
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
            const SizedBox(height: AppColors.space8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));
    final currentUid = FirebaseConfig.currentUser?.uid;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Group Settings'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Iconsax.arrow_left),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: groupAsync.when(
        data: (group) {
          if (group == null) {
            return const Center(child: Text('Group not found'));
          }

          final isCreator = currentUid == group.createdBy;

          return ListView(
            children: [
              // ---- Group Name ----
              ListTile(
                title: Text(
                  'Group Name',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                subtitle: _isEditing
                    ? TextField(
                        controller: _nameController,
                        autofocus: true,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          filled: false,
                          suffixIcon: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(
                                    Iconsax.tick_circle,
                                    color: AppColors.primary,
                                  ),
                                  onPressed: () =>
                                      _saveGroupName(group.id),
                                ),
                        ),
                        onSubmitted: (_) => _saveGroupName(group.id),
                      )
                    : Text(
                        group.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                trailing: isCreator && !_isEditing
                    ? IconButton(
                        icon: const Icon(
                          Iconsax.edit_2,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () => setState(() {
                          _isEditing = true;
                          _nameController.text = group.name;
                        }),
                      )
                    : null,
              ),

              const Divider(color: AppColors.border, height: 1),

              // ---- Currency ----
              ListTile(
                title: Text(
                  'Currency',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                subtitle: Text(
                  group.currency,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                trailing: const Icon(
                  Iconsax.arrow_right_3,
                  color: AppColors.textMuted,
                ),
                onTap: () => _showCurrencyPicker(
                  context,
                  group.id,
                  group.currency,
                ),
              ),

              const Divider(color: AppColors.border, height: 1),

              // ---- Invite Code ----
              ListTile(
                title: Text(
                  'Invite Code',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                subtitle: Text(
                  group.inviteCode,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                    color: AppColors.textPrimary,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Iconsax.copy, color: AppColors.textSecondary),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: group.inviteCode));
                    HapticService.success();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Invite code copied'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => const Center(child: Text('Error loading settings')),
      ),
    );
  }
}
