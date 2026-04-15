import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../shared/widgets/loading_button.dart';
import '../keys/group_keys.dart';
import '../models/group_model.dart';
import '../providers/group_provider.dart';
import '../widgets/invite_code_display.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';

/// Screen for creating a new group.
///
/// Shows a form with group name, currency selector, and the user's device
/// name (read-only, per D-06 and D-08). On success, presents a share prompt
/// with the invite code (D-11, D-22).
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _displayNameController = TextEditingController();
  String _selectedCurrency = 'OMR';
  bool _didInitName = false;

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
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;

    ref.read(groupLoadingProvider.notifier).state = true;
    ref.read(groupErrorProvider.notifier).state = null;

    // Save display name to settings so GroupService picks it up
    final trimmedName = _displayNameController.text.trim();
    await ref.read(settingsProvider.notifier).setDeviceName(trimmedName);

    try {
      final group = await ref
          .read(groupServiceProvider)
          .createGroup(
            name: _nameController.text.trim(),
            currency: _selectedCurrency,
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      ref.read(groupLoadingProvider.notifier).state = false;
      await _showSharePrompt(context, group);
    } catch (e) {
      if (!mounted) return;
      ref.read(groupLoadingProvider.notifier).state = false;
      ref.read(groupErrorProvider.notifier).state = e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _showSharePrompt(BuildContext context, Group group) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColorTokens.light.cardSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => _SharePrompt(
        group: group,
        onNavigate: () {
          Navigator.pop(sheetContext);
          if (mounted) {
            context.pushReplacement('/group/${group.id}');
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(groupLoadingProvider);
    final deviceName = ref.watch(settingsProvider).deviceName;

    // Seed display name controller once from settings
    if (!_didInitName) {
      _displayNameController.text = deviceName;
      _didInitName = true;
    }

    return Scaffold(
      key: GroupKeys.createScreen,
      appBar: AppBar(
        title: const Text('New Group'),
        leading: CloseButton(
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Form fields card
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColorTokens.light.cardSurface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: AppShadowTokens.standard.raised,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Group Name label
                    Text(
                      'Group Name',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),

                    // Group Name input
                    TextFormField(
                      key: GroupKeys.groupNameInput,
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Enter group name',
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty
                              ? "Group name can't be empty."
                              : null,
                    ),
                    const SizedBox(height: 24),

                    // Currency label
                    Text(
                      'Currency',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),

                    // Currency selector
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCurrency,
                      decoration: const InputDecoration(),
                      items: _currencies
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedCurrency = v);
                      },
                    ),
                    const SizedBox(height: 24),

                    // Your name label
                    Text(
                      'Your name in this group',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),

                    // Editable display name — saved to settings on group creation
                    TextFormField(
                      controller: _displayNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Enter your name',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Enter your name so others know who you are.'
                          : null,
                    ),
                  ],
                ),
              ),

              // Submit button
              LoadingButton(
                key: GroupKeys.createGroupButton,
                isLoading: isLoading,
                onPressed: _createGroup,
                label: isLoading ? 'Creating\u2026' : 'Create Group',
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

/// Post-creation share prompt presented as a bottom sheet.
///
/// Shows the invite code via [InviteCodeDisplay] with copy and share actions.
class _SharePrompt extends StatelessWidget {
  final Group group;
  final VoidCallback onNavigate;

  const _SharePrompt({
    required this.group,
    required this.onNavigate,
  });

  void _copyCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: group.inviteCode));
    HapticService.success();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Invite code copied'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _shareCode() {
    Share.share(
      'Join my group on Rihla! Use code ${group.inviteCode} to join.',
      subject: 'Join ${group.name}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              group.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Share this code with your group',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColorTokens.light.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),

            // Invite code pill (no inline buttons — buttons are below)
            InviteCodeDisplay(code: group.inviteCode),

            const SizedBox(height: 24),

            // Copy and Share buttons
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => _copyCode(context),
                      child: const Text('Copy Code'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _shareCode,
                      child: const Text('Share'),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            Center(
              child: TextButton(
                onPressed: onNavigate,
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
