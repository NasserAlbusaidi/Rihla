import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/services/notification_prompt.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/localized_name_validators.dart';
import '../../../shared/widgets/loading_button.dart';
import '../keys/group_keys.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_provider.dart';

/// Screen for joining a group via a 6-character invite code.
///
/// Auto-uppercases input (D-13), enforces 6-char limit (D-19), and
/// auto-submits when 6 characters are entered. Single step — no name
/// claiming after join (D-12).
///
/// Saffron sibling of [CreateGroupScreen]: warm-paper layout, italic mood
/// header, underlined inputs, primary CTA pinned to the bottom of the form.
class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key, this.initialInviteCode});

  final String? initialInviteCode;

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  bool _didInitName = false;

  @override
  void initState() {
    super.initState();
    final initialInviteCode = widget.initialInviteCode?.trim().toUpperCase();
    if (initialInviteCode == null || initialInviteCode.isEmpty) return;

    _codeController.value = TextEditingValue(
      text: initialInviteCode,
      selection: TextSelection.collapsed(offset: initialInviteCode.length),
    );
  }

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
    final nameError = validateDisplayNameLocalized(
      context,
      _nameController.text,
    );
    if (nameError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(nameError)));
      return;
    }

    ref.read(groupLoadingProvider.notifier).state = true;
    ref.read(groupErrorProvider.notifier).state = null;

    await ref.read(settingsProvider.notifier).setDeviceName(trimmedName);

    try {
      final group = await ref
          .read(groupServiceProvider)
          .joinGroup(inviteCode: _codeController.text.trim());
      ref.read(groupLoadingProvider.notifier).state = false;

      // Log member_joined activity (D-14) — fire-and-forget, no await
      try {
        final actorId = FirebaseConfig.currentUser?.uid ?? '';
        final actorName = ref.read(settingsProvider).deviceName.isNotEmpty
            ? ref.read(settingsProvider).deviceName
            : 'Someone';
        ref
            .read(groupActivityServiceProvider)
            .logGroupEvent(
              groupId: group.id,
              type: 'member_joined',
              actorId: actorId,
              actorName: actorName,
              description: 'joined the group',
              metadata: {'groupId': group.id},
            );
      } catch (_) {
        // Activity logging failure must never crash the join flow.
      }

      HapticService.success(); // D-02: double-tap "done" feel

      // First natural moment to ask for push permission (#288) — the joiner now
      // has a stake in a group. Fire-and-forget; the coordinator holds the
      // container ref, so it survives this screen's navigation.
      unawaited(ref.read(notificationPromptProvider).maybePrompt());

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
      return context.l10n.groupJoinInvalidCode;
    }
    if (error.contains('Already a member')) {
      return context.l10n.groupJoinAlreadyMember;
    }
    if (error.contains('Too many attempts')) {
      return context.l10n.groupJoinTooManyAttempts;
    }
    if (error.contains('Please sign in')) {
      return context.l10n.groupJoinPleaseSignIn;
    }
    return context.l10n.groupJoinFailed;
  }

  void _close() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      if (router.canPop()) {
        router.pop();
      } else {
        router.go('/home');
      }
      return;
    }

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(groupLoadingProvider);
    final deviceName = ref.watch(settingsProvider).deviceName;

    if (!_didInitName) {
      _nameController.text = deviceName;
      _didInitName = true;
    }

    final canJoin =
        _codeController.text.length == 6 &&
        _nameController.text.trim().isNotEmpty;

    return Scaffold(
      key: GroupKeys.joinScreen,
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            _JoinGroupTopBar(onClose: _close),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsetsDirectional.fromSTEB(context.spacing.space24, context.spacing.space8, context.spacing.space24, context.spacing.space24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _JoinMoodBlock(),
                    const SizedBox(height: 26),
                    _UnderlinedTextField(
                      label: context.l10n.groupYourName,
                      controller: _nameController,
                      hintText: context.l10n.groupJoinNameHint,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 22),
                    _InviteCodeField(
                      controller: _codeController,
                      onChanged: (value) {
                        setState(() {});
                        if (value.length == 6) _joinGroup();
                      },
                    ),
                    const SizedBox(height: 26),
                    const _JoinHintCard(),
                    const SizedBox(height: 28),
                    LoadingButton(
                      key: GroupKeys.joinGroupButton,
                      isLoading: isLoading,
                      onPressed: canJoin ? _joinGroup : null,
                      label: isLoading
                          ? context.l10n.groupJoining
                          : context.l10n.groupJoinCta,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinGroupTopBar extends StatelessWidget {
  const _JoinGroupTopBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space16, vertical: 10),
      child: SizedBox(
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: BackButton(
                onPressed: onClose,
                color: colors.textPrimary,
                style: IconButton.styleFrom(
                  minimumSize: const Size(40, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            Text(
              context.l10n.groupJoinTitle,
              style: AppTypography.display(
                fontSize: 19,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinMoodBlock extends StatelessWidget {
  const _JoinMoodBlock();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.groupJoinMoodTitle,
          style: AppTypography.display(
            fontSize: 30,
            color: colors.textPrimary,
            height: 1.05,
          ),
        ),
        SizedBox(height: context.spacing.space8),
        Text(
          context.l10n.groupJoinMoodBody,
          style: AppTypography.sans(
            fontSize: 13,
            color: colors.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _UnderlinedTextField extends StatelessWidget {
  const _UnderlinedTextField({
    required this.label,
    required this.controller,
    required this.hintText,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        TextFormField(
          controller: controller,
          textCapitalization: textCapitalization,
          cursorColor: colors.textPrimary,
          onChanged: onChanged,
          style: AppTypography.sans(
            fontSize: 17,
            color: colors.textPrimary,
            height: 1.2,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            filled: false,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: context.spacing.space12),
            border: _underline(colors.ink2),
            enabledBorder: _underline(colors.ink2),
            focusedBorder: _underline(colors.textPrimary, width: 1.5),
            // textMuted-decorative-justified: placeholder is non-functional guidance.
            hintStyle: AppTypography.sans(
              fontSize: 17,
              color: colors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _InviteCodeField extends StatelessWidget {
  const _InviteCodeField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(context.l10n.groupInviteCode),
        SizedBox(height: context.spacing.space4),
        Text(
          context.l10n.groupInviteCodeHelper,
          style: AppTypography.sans(
            fontSize: 12,
            color: colors.textSecondary,
            height: 1.4,
          ),
        ),
        SizedBox(height: context.spacing.space12),
        TextFormField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          cursorColor: colors.textPrimary,
          style: AppTypography.mono(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
            letterSpacing: 8,
          ),
          decoration: InputDecoration(
            hintText: 'ABC123',
            counterText: '',
            filled: true,
            fillColor: colors.selectionFill,
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
            border: _pillBorder(Colors.transparent),
            enabledBorder: _pillBorder(Colors.transparent),
            focusedBorder: _pillBorder(colors.textPrimary, width: 1.5),
            hintStyle: AppTypography.mono(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              // textMuted-decorative-justified: hint "ABC123" is placeholder text that disappears on input; never read as functional content.
              color: colors.textMuted,
              letterSpacing: 8,
            ),
          ),
          maxLength: 6,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            LengthLimitingTextInputFormatter(6),
            _UpperCaseTextFormatter(),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _JoinHintCard extends StatelessWidget {
  const _JoinHintCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.all(context.spacing.space16),
      decoration: BoxDecoration(
        color: colors.cardSoft,
        borderRadius: BorderRadius.circular(context.spacing.radiusCard),
        border: Border.all(color: colors.rule2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.groupJoinHintTitle,
            style: AppTypography.sans(
              fontSize: 12,
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          Text(
            context.l10n.groupJoinHintBody,
            style: AppTypography.sans(
              fontSize: 12,
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTypography.sans(
        fontSize: 11,
        color: context.colors.textSecondary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

UnderlineInputBorder _underline(Color color, {double width = 1}) {
  return UnderlineInputBorder(
    borderSide: BorderSide(color: color, width: width),
  );
}

OutlineInputBorder _pillBorder(Color color, {double width = 1}) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: color, width: width),
  );
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
