import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/balance_aggregate_freshness_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/firebase_functions_service.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/services/notification_prompt.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/localized_name_validators.dart';
import '../../../core/utils/name_validators.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/r_icon_button.dart';
import '../keys/group_keys.dart';
import '../models/claim_models.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_provider.dart';
import '../widgets/claim_join_views.dart';

/// #278 PR9 — the join screen's three steps. `form` is the code+name entry;
/// after a valid code reveals unclaimed shadows it switches to `picker`; after a
/// claim request is sent it switches to `waiting`.
enum _JoinStep { form, picker, waiting }

/// Screen for joining a group via a 6-character invite code.
///
/// Auto-uppercases input (D-13), enforces 6-char limit (D-19), restricts to the
/// invite alphabet (#293 — no ambiguous I/O/0/1), and auto-submits ONCE on the
/// first complete code (#293 — corrections then need a deliberate Join tap so a
/// stream of mistypes can't burn the server's 5/hr lockout). Single step — no
/// name claiming after join (D-12).
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

  // #293: the invite code auto-submits once on first completion. After that —
  // e.g. while correcting a mistyped hand-relayed code — further completions
  // require a deliberate Join tap, so a stream of corrections can't burn the
  // server's 5/hr join lockout one silent auto-fire at a time.
  bool _autoSubmitted = false;

  // #278 PR9 — claim flow state.
  _JoinStep _step = _JoinStep.form;
  bool _claimBusy = false;
  List<UnclaimedShadow> _shadows = const [];
  String _waitShadowName = '';
  String _waitShadowMemberId = '';
  String _waitGroupId = '';

  @override
  void initState() {
    super.initState();
    final initialInviteCode = widget.initialInviteCode?.trim().toUpperCase();
    if (initialInviteCode != null && initialInviteCode.isNotEmpty) {
      _codeController.value = TextEditingValue(
        text: initialInviteCode,
        selection: TextSelection.collapsed(offset: initialInviteCode.length),
      );
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    if (ref.read(groupLoadingProvider) || _claimBusy) return;

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

    // #648/#818: no durable credential is required to join or create.
    // Anonymous users may own groups and expenses; cross-UID restore/switch
    // paths must prove the outgoing shell empty before discarding it.

    // #278 PR9: pre-join discovery. Best-effort — any failure (anon, offline,
    // bad code, no-Firebase-in-test) falls through to the normal join, which
    // surfaces the real error. A non-empty list reveals the claim picker.
    setState(() => _claimBusy = true);
    List<UnclaimedShadow> shadows = const [];
    try {
      shadows = await ref
          .read(firebaseFunctionsServiceProvider)
          .listUnclaimedShadows(inviteCode: _codeController.text.trim());
    } catch (_) {
      shadows = const [];
    }
    if (!mounted) return;
    if (shadows.isNotEmpty) {
      setState(() {
        _claimBusy = false;
        _shadows = shadows;
        _step = _JoinStep.picker;
      });
      return;
    }
    setState(() => _claimBusy = false);
    await _doJoin(preferClaimHint: false);
  }

  /// Execute a plain join (name validation already ran in [_onSubmit]; there is
  /// no durable credential requirement on join since #648). Used by the
  /// no-shadow path and the "I'm new" fallback.
  Future<void> _doJoin({required bool preferClaimHint}) async {
    if (ref.read(groupLoadingProvider)) return;
    ref.read(groupLoadingProvider.notifier).state = true;
    ref.read(groupErrorProvider.notifier).state = null;

    final trimmedName = _nameController.text.trim();
    try {
      await ref.read(settingsProvider.notifier).setDeviceName(trimmedName);
    } on DisplayNameTakenException catch (e) {
      // #390: the chosen name collides with another live member in one of the
      // user's EXISTING groups; reject before attempting the join.
      ref.read(groupLoadingProvider.notifier).state = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.displayNameTakenInGroup(e.groupName)),
          ),
        );
      }
      return;
    }

    try {
      final group = await ref
          .read(groupServiceProvider)
          .joinGroup(inviteCode: _codeController.text.trim());
      ref
          .read(balanceAggregateFreshnessProvider.notifier)
          .markGroupDirty(group.id);
      ref.read(groupLoadingProvider.notifier).state = false;
      _logJoined(group.id);
      HapticService.success(); // D-02: double-tap "done" feel
      // First natural moment to ask for push permission (#288).
      unawaited(ref.read(notificationPromptProvider).maybePrompt());
      if (mounted) {
        context.pushReplacement('/group/${group.id}');
      }
    } catch (e) {
      ref.read(groupLoadingProvider.notifier).state = false;
      ref.read(groupErrorProvider.notifier).state = e.toString();
      if (!mounted) return;
      // #278 PR9: an "I'm new" name that collides with a shadow gets the
      // actionable claim-instead hint and returns to the picker.
      final isCollision = e.toString().contains('already taken in this group');
      final message = (preferClaimHint && isCollision)
          ? context.l10n.groupClaimNameTakenClaimInstead
          : _errorMessage(e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
      if (preferClaimHint && isCollision && _shadows.isNotEmpty) {
        setState(() => _step = _JoinStep.picker);
      }
    }
  }

  void _logJoined(String groupId) {
    // Log member_joined activity (D-14) — fire-and-forget; failure must never
    // crash the join flow (FirebaseConfig.currentUser throws without Firebase).
    try {
      final actorId = FirebaseConfig.currentUser?.uid ?? '';
      final actorName = ref.read(settingsProvider).deviceName.isNotEmpty
          ? ref.read(settingsProvider).deviceName
          : 'Someone';
      ref
          .read(groupActivityServiceProvider)
          .logGroupEvent(
            groupId: groupId,
            type: 'member_joined',
            actorId: actorId,
            actorName: actorName,
            description: 'joined the group',
            metadata: {'groupId': groupId},
          );
    } catch (_) {
      // Activity logging failure must never crash the join flow.
    }
  }

  /// #278 PR9: the user picked a shadow — show the hard permanent confirmation
  /// (D3); only an affirmative tap opens the claim request.
  Future<void> _onPickShadow(UnclaimedShadow shadow) async {
    if (_claimBusy) return;
    final confirmed = await showClaimConfirmSheet(
      context,
      name: shadow.displayName,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _claimBusy = true);
    try {
      final res = await ref
          .read(firebaseFunctionsServiceProvider)
          .requestClaimShadow(
            inviteCode: _codeController.text.trim(),
            shadowMemberId: shadow.shadowMemberId,
            displayName: _nameController.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _claimBusy = false;
        _waitShadowName = shadow.displayName;
        _waitShadowMemberId = shadow.shadowMemberId;
        _waitGroupId = res.groupId;
        _step = _JoinStep.waiting;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _claimBusy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorMessage(e.toString()))));
    }
  }

  /// "No, I'm new" — fall back to a normal join with the typed name.
  Future<void> _onImNew() => _doJoin(preferClaimHint: true);

  /// Re-poll whether the creator approved the pending claim (manual — P9-2).
  Future<void> _onCheckStatus() async {
    if (_claimBusy) return;
    setState(() => _claimBusy = true);
    List<MyClaimRequest> requests = const [];
    try {
      requests = await ref
          .read(firebaseFunctionsServiceProvider)
          .listMyClaimRequests(inviteCode: _codeController.text.trim());
    } catch (e) {
      if (!mounted) return;
      setState(() => _claimBusy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorMessage(e.toString()))));
      return;
    }
    if (!mounted) return;
    setState(() => _claimBusy = false);

    var status = 'pending';
    for (final r in requests) {
      if (r.shadowMemberId == _waitShadowMemberId) status = r.status;
    }
    if (status == 'claimed') {
      // The engine made the requester a member; navigate into the group.
      context.pushReplacement('/group/$_waitGroupId');
    } else if (status == 'declined') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.groupClaimDeclinedBody)),
      );
      setState(() => _step = _JoinStep.form);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.groupClaimStillPending)),
      );
    }
  }

  /// Step-aware back: a picker/waiting step returns to the form; the form closes.
  void _onBack() {
    if (_step != _JoinStep.form) {
      setState(() => _step = _JoinStep.form);
      return;
    }
    _close();
  }

  String _errorMessage(String error) {
    if (error.contains('Invalid invite code')) {
      return context.l10n.groupJoinInvalidCode;
    }
    if (error.contains('Already a member')) {
      return context.l10n.groupJoinAlreadyMember;
    }
    if (error.contains('already taken in this group')) {
      return context.l10n.groupJoinNameTaken;
    }
    if (error.contains('Too many attempts')) {
      return context.l10n.groupJoinTooManyAttempts;
    }
    if (error.contains('Could not verify this device')) {
      return context.l10n.groupJoinDeviceVerificationFailed;
    }
    if (error.contains('Please sign in')) {
      return context.l10n.groupJoinPleaseSignIn;
    }
    // #648/#818: join/create no longer require durable-credential gating, so
    // there's no 'linked account' branch.
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

    // #293: do NOT pre-fill the name from the device-wide deviceName — a casual
    // nickname from one group would silently load into another group's ledger.
    // Joining is an explicit identity choice; the field starts blank.

    return Scaffold(
      key: GroupKeys.joinScreen,
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            _JoinGroupTopBar(onClose: _onBack),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsetsDirectional.fromSTEB(
                  context.spacing.space24,
                  context.spacing.space8,
                  context.spacing.space24,
                  context.spacing.space24,
                ),
                child: switch (_step) {
                  _JoinStep.picker => ClaimPickerView(
                    shadows: _shadows,
                    busy: _claimBusy,
                    onPick: _onPickShadow,
                    onImNew: _onImNew,
                  ),
                  _JoinStep.waiting => ClaimWaitingView(
                    shadowName: _waitShadowName,
                    busy: _claimBusy,
                    onCheckAgain: _onCheckStatus,
                  ),
                  _JoinStep.form => _buildForm(isLoading),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(bool isLoading) {
    final canJoin =
        _codeController.text.length == 6 &&
        _nameController.text.trim().isNotEmpty;
    return Column(
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
            if (value.length == 6 && !_autoSubmitted) {
              _autoSubmitted = true;
              _onSubmit();
            }
          },
        ),
        const SizedBox(height: 26),
        const _JoinHintCard(),
        const SizedBox(height: 28),
        LoadingButton(
          key: GroupKeys.joinGroupButton,
          isLoading: isLoading || _claimBusy,
          onPressed: (canJoin && !_claimBusy) ? _onSubmit : null,
          label: isLoading
              ? context.l10n.groupJoining
              : context.l10n.groupJoinCta,
        ),
      ],
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
      padding: EdgeInsets.symmetric(
        horizontal: context.spacing.space16,
        vertical: 10,
      ),
      child: SizedBox(
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: RIconButton(
                variant: RIconButtonVariant.ghost,
                icon: Directionality.of(context) == TextDirection.rtl
                    ? Iconsax.arrow_right
                    : Iconsax.arrow_left,
                tooltip: context.l10n.commonBack,
                onTap: onClose,
              ),
            ),
            Text(
              context.l10n.groupJoinTitle,
              style: AppTypography.displayOf(
                context,
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
          style: AppTypography.displayOf(
            context,
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
            contentPadding: EdgeInsets.symmetric(
              vertical: context.spacing.space12,
            ),
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
            // #293: example uses only invite-alphabet chars (no I/O/0/1).
            hintText: 'ABC234',
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
              // textMuted-decorative-justified: hint "ABC234" is placeholder text that disappears on input; never read as functional content.
              color: colors.textMuted,
              letterSpacing: 8,
            ),
          ),
          maxLength: 6,
          inputFormatters: [
            // #293: restrict to the invite alphabet — exclude the ambiguous
            // I, O, 0 and 1 that group_provider._generateInviteCode never emits.
            // A glyph-confusion mistype then can't be entered, so it can't
            // auto-submit a guaranteed-invalid code that burns the 5/hr lockout.
            FilteringTextInputFormatter.allow(
              RegExp(r'[A-HJ-NP-Za-hj-np-z2-9]'),
            ),
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
