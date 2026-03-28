import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/loading_button.dart';
import '../keys/group_keys.dart';
import '../providers/group_provider.dart';

/// Screen for joining a group via a 6-character invite code.
///
/// Auto-uppercases input (D-13), enforces 6-char limit (D-19), and
/// auto-submits when 6 characters are entered. Single step — no name
/// claiming after join (D-12).
class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  bool _didInitName = false;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _joinGroup() async {
    final isLoading = ref.read(groupLoadingProvider);
    if (isLoading) return;

    final trimmedName = _nameController.text.trim();
    if (trimmedName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your name first.')),
      );
      return;
    }

    ref.read(groupLoadingProvider.notifier).state = true;
    ref.read(groupErrorProvider.notifier).state = null;

    // Save name to settings so GroupService picks it up
    await ref.read(settingsProvider.notifier).setDeviceName(trimmedName);

    try {
      final group = await ref.read(groupServiceProvider).joinGroup(
            inviteCode: _codeController.text.trim(),
          );
      ref.read(groupLoadingProvider.notifier).state = false;
      await HapticFeedback.mediumImpact();
      if (mounted) {
        context.pushReplacement('/group/${group.id}');
      }
    } catch (e) {
      ref.read(groupLoadingProvider.notifier).state = false;
      ref.read(groupErrorProvider.notifier).state = e.toString();
      if (mounted) {
        final message = _errorMessage(e.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  String _errorMessage(String error) {
    if (error.contains('Invalid invite code')) {
      return "That code doesn't match any group. Check the code and try again.";
    }
    if (error.contains('Already a member')) {
      return "You're already in this group.";
    }
    debugPrint('JoinGroup error: $error');
    return "Couldn't join the group. Check your connection and try again.";
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(groupLoadingProvider);
    final deviceName = ref.watch(settingsProvider).deviceName;

    if (!_didInitName) {
      _nameController.text = deviceName;
      _didInitName = true;
    }

    return Scaffold(
      key: GroupKeys.joinScreen,
      appBar: AppBar(
        title: const Text('Join a Group'),
        leading: const BackButton(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppColors.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppColors.space32),

            // Your name
            Text(
              'Your name',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppColors.space8),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Enter your name',
              ),
            ),
            const SizedBox(height: AppColors.space24),

            Text(
              'Invite code',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppColors.space8),
            Text(
              'Ask a group member for their 6-character code',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: AppColors.space16),

            // Invite code input — uppercase, max 6 chars, spaced display
            TextFormField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: const TextStyle(
                letterSpacing: 8,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                hintText: 'ABC123',
                counterText: '',
              ),
              maxLength: 6,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(6),
                _UpperCaseTextFormatter(),
              ],
              onChanged: (value) {
                setState(() {}); // rebuild to enable/disable button
                if (value.length == 6) _joinGroup();
              },
            ),

            const SizedBox(height: 48),

            LoadingButton(
              key: GroupKeys.joinGroupButton,
              isLoading: isLoading,
              onPressed: _codeController.text.length == 6 ? _joinGroup : null,
              label: isLoading ? 'Joining\u2026' : 'Join Group',
            ),

            const SizedBox(height: AppColors.space32),
          ],
        ),
      ),
    );
  }
}

/// Text input formatter that converts all input to uppercase.
class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
