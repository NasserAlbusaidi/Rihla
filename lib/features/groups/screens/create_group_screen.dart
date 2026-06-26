import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/utils/error_message_translator.dart';
import '../../../core/utils/share_helper.dart';
import '../../../core/utils/write_ack.dart';

import '../../../core/config/app_links.dart';
import '../../../core/constants/supported_currencies.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/services/notification_prompt.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/localized_name_validators.dart';
import '../../../core/utils/name_validators.dart';
import '../../../shared/widgets/r_icon_button.dart';
import '../../auth/providers/durable_credential_gate_provider.dart';
import '../../auth/services/durable_credential_exception.dart';
import '../../auth/services/pending_gate_intent.dart';
import '../keys/group_keys.dart';
import '../models/group_model.dart';
import '../providers/group_provider.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../widgets/currency_picker_sheet.dart';
import '../widgets/group_stamp_picker.dart';
import '../widgets/invite_code_display.dart';
import '../widgets/shadow_member_chips_field.dart';

/// Screen for creating a new group.
///
/// Wireframe ref: `Wireframes/Rihla/hifi/screens-group.jsx` →
/// `Hi_CreateGroup()`.
///
/// Shows a warm-paper creation form with a mood header, trip-stamp picker,
/// underlined inputs, and a compact top-bar create action. On success, presents
/// a share prompt with the invite code (D-11, D-22).
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _didInitName = false;

  /// #261: the group's currency, chosen at create time and immutable after
  /// (Model A). Local state only — NOT persisted to AppSettings.
  String _selectedCurrency = 'OMR';

  /// #287/trip-stamps: the chosen stamp identity. Both start null = defaulted
  /// (monogram glyph + name-derived ink); a non-null value is an explicit pick
  /// passed to stageGroup and persisted. NOT carried by PendingGateIntent — on
  /// the rare #441 gate-restart path the picks fall back to the monogram.
  String? _selectedGlyph;
  int? _selectedInkIndex;

  /// #278: placeholder ("shadow") member names seeded at create time. Local UI
  /// state until Create, then fanned out to the addShadowMember callable once
  /// the group doc is acked. Entry-ordered; de-duplicated case-insensitively.
  final List<String> _shadowNames = [];

  @override
  void initState() {
    super.initState();
    _consumePendingGateIntent();
  }

  /// One-shot prefill from a gate-conflict restart marker (#428). The
  /// marker's displayName wins over the settings seed in build(); an off-list
  /// currency code keeps the OMR default. A join-type marker is left
  /// untouched for its screen.
  void _consumePendingGateIntent() {
    final prefs = ref.read(sharedPreferencesProvider);
    final intent = PendingGateIntent.read(prefs);
    if (intent == null || intent.type != PendingGateIntent.typeCreate) return;

    final groupName = intent.groupName?.trim() ?? '';
    if (groupName.isNotEmpty) {
      _nameController.text = groupName;
    }
    final name = intent.displayName?.trim() ?? '';
    if (name.isNotEmpty) {
      _displayNameController.text = name;
      _didInitName = true;
    }
    final currency = intent.currencyCode;
    if (currency != null && kSupportedCurrencies.contains(currency)) {
      _selectedCurrency = currency;
    }
    unawaited(PendingGateIntent.clear(prefs));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  /// #278: add a placeholder name, de-duplicated case-insensitively against the
  /// creator's own name and existing chips (the server enforces the real guard;
  /// this keeps the local list clean).
  void _addShadowName(String name) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return;
    final selfName = _displayNameController.text.trim().toLowerCase();
    if (key == selfName) return;
    if (_shadowNames.any((n) => n.toLowerCase() == key)) return;
    setState(() => _shadowNames.add(name));
  }

  void _removeShadowName(String name) {
    setState(() => _shadowNames.remove(name));
  }

  Future<void> _pickCurrency() async {
    final picked = await CurrencyPickerSheet.show(
      context,
      selected: _selectedCurrency,
    );
    if (picked != null && mounted) {
      setState(() => _selectedCurrency = picked);
    }
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;

    // #441: first valuable write — an anonymous user must link Google first.
    // The intent carries the typed form across the gate-conflict
    // discard-shell restart (#428).
    final gateOk = await ref
        .read(durableCredentialGateProvider)
        .ensure(
          context,
          intent: PendingGateIntent.create(
            groupName: _nameController.text.trim(),
            displayName: _displayNameController.text.trim(),
            currencyCode: _selectedCurrency,
          ),
        );
    if (!gateOk || !mounted) return;

    ref.read(groupLoadingProvider.notifier).state = true;
    ref.read(groupErrorProvider.notifier).state = null;

    // Save display name to settings so GroupService picks it up
    final trimmedName = _displayNameController.text.trim();
    try {
      await ref.read(settingsProvider.notifier).setDeviceName(trimmedName);
    } on DisplayNameTakenException catch (e) {
      // #390: the chosen name collides with another live member in one of the
      // user's EXISTING groups; reject before creating.
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

    // #412/#520: a Firestore write acks only on SERVER confirmation — offline
    // it stays pending. Capture connectivity to short-circuit the ack wait.
    final connectivity = ref.read(connectivityProvider.notifier);
    final connectivityStatus = ref.read(connectivityProvider);
    try {
      // stageGroup applies the write to the local cache and returns the local
      // Group immediately + the server-ack future. Race the ack instead of
      // awaiting it raw (the old createGroup().timeout(15s) falsely reported
      // "couldn't create group" offline for a group that WAS created and will
      // sync). stageGroup runs the auth/anonymous guards synchronously, so its
      // DurableCredentialRequiredException is caught below — it MUST stay
      // inside this try.
      final staged = ref
          .read(groupServiceProvider)
          .stageGroup(
            name: _nameController.text.trim(),
            currency: _selectedCurrency,
            glyph: _selectedGlyph,
            inkIndex: _selectedInkIndex,
          );
      final outcome = await awaitServerAck(
        staged.ack,
        skipWait: connectivityStatus != ConnectivityStatus.online,
      );
      if (!mounted) return;
      ref.read(groupLoadingProvider.notifier).state = false;
      if (outcome == WriteAck.acked) {
        connectivity.noteLocalWrite(); // #357: stale-offline correction (no-op online)
        // #278: the group doc is acked, so its id exists server-side — fan out
        // one addShadowMember callable per seeded name. Runs only on a real
        // server ack (the callable has no offline replay); offline the chips
        // field is disabled so _shadowNames is empty regardless.
        await _seedShadowMembers(staged.group.id);
        if (!mounted) return;
      } else {
        connectivity.noteQueuedWrite(); // #412: queued — force "will sync"
        // Shown BEFORE awaiting the share sheet so it is visible; the sheet is
        // a modal (not a route replacement), so the local messenger is valid.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.groupCreatedWillSync),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      // Capture before the share sheet (which may navigate away and unmount
      // this screen) so the post-sheet prompt reads from the container ref.
      final notificationPrompt = ref.read(notificationPromptProvider);
      await _showSharePrompt(context, staged.group);
      // First natural moment to ask for push permission (#288) — the owner now
      // has a group to be notified about. Fires after the sheet so it doesn't
      // fight the modal.
      unawaited(notificationPrompt.maybePrompt());
    } on DurableCredentialRequiredException {
      // Defense path (#441): the service refused an anonymous write the UI
      // gate didn't catch (e.g. auth state changed mid-flow).
      if (!mounted) return;
      ref.read(groupLoadingProvider.notifier).state = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.durableCredentialRequired)),
      );
    } catch (e, st) {
      if (!mounted) return;
      ref.read(groupLoadingProvider.notifier).state = false;
      ref.read(groupErrorProvider.notifier).state = e.toString();
      unawaited(Sentry.captureException(e, stackTrace: st));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.groupCreateError(friendlyMessageFor(context, e)),
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  /// #278: seed each entered placeholder name via the addShadowMember callable.
  /// The group already exists, so a per-chip failure never aborts the others —
  /// `already-exists` names are collected and surfaced together; any other
  /// failure is swallowed quietly (the creator can re-add from the group later).
  Future<void> _seedShadowMembers(String groupId) async {
    if (_shadowNames.isEmpty) return;
    final service = ref.read(groupServiceProvider);
    final taken = <String>[];
    for (final name in List<String>.from(_shadowNames)) {
      try {
        await service.addShadowMember(groupId: groupId, displayName: name);
      } on ShadowMemberNameTakenException {
        taken.add(name);
      } catch (e, st) {
        unawaited(Sentry.captureException(e, stackTrace: st));
      }
    }
    if (!mounted || taken.isEmpty) return;
    // Plain (no-action) snackbar per taken name, so it auto-dismisses without
    // the Flutter ≥3.41 persist trap (#411). floating is set explicitly so dark
    // mode doesn't render it full-width (darkTheme has no snackBarTheme).
    final messenger = ScaffoldMessenger.of(context);
    for (final name in taken) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.l10n.createGroupShadowNameTaken(name)),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _showSharePrompt(BuildContext context, Group group) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.cardSurface,
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

    // Seed display name controller once from settings
    if (!_didInitName) {
      _displayNameController.text = deviceName;
      _didInitName = true;
    }

    return Scaffold(
      key: GroupKeys.createScreen,
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: Form(
          key: _formKey,
          // #680: re-validate each field as the user edits it so a stale
          // "Name can't be empty." clears the moment a valid name is typed,
          // instead of lingering until the next Create tap.
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            children: [
              _CreateGroupTopBar(
                isLoading: isLoading,
                onClose: _close,
                onCreate: _createGroup,
              ),
              const OfflineBanner(),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _MoodBlock(),
                      const SizedBox(height: 22),
                      // #287: live trip-stamp picker. Wrapped in a
                      // ListenableBuilder so the hero monogram tracks the name
                      // as the user types (the screen doesn't rebuild on
                      // keystroke). Stays inside the SingleChildScrollView so the
                      // picker's shrinkWrap GridView is height-bounded.
                      ListenableBuilder(
                        listenable: _nameController,
                        builder: (context, _) => GroupStampPicker(
                          name: _nameController.text,
                          value: (
                            glyph: _selectedGlyph,
                            inkIndex: _selectedInkIndex,
                          ),
                          onChanged: (sel) => setState(() {
                            _selectedGlyph = sel.glyph;
                            _selectedInkIndex = sel.inkIndex;
                          }),
                        ),
                      ),
                      const SizedBox(height: 26),
                      _WireframeTextField(
                        key: GroupKeys.groupNameInput,
                        label: context.l10n.groupNameLabel,
                        controller: _nameController,
                        hintText: context.l10n.groupNameHint,
                        textCapitalization: TextCapitalization.words,
                        validator: (value) =>
                            validateDisplayNameLocalized(context, value),
                      ),
                      const SizedBox(height: 18),
                      _WireframeTextField(
                        key: GroupKeys.deviceNameInput,
                        label: context.l10n.groupYourNameInGroupLabel,
                        controller: _displayNameController,
                        hintText: context.l10n.groupYourNameHint,
                        helperText: context.l10n.groupDifferentNameHelper,
                        textCapitalization: TextCapitalization.words,
                        validator: (value) =>
                            validateDisplayNameLocalized(context, value),
                      ),
                      const SizedBox(height: 18),
                      ShadowMemberChipsField(
                        names: _shadowNames,
                        enabled:
                            ref.watch(connectivityProvider) ==
                            ConnectivityStatus.online,
                        onAdd: _addShadowName,
                        onRemove: _removeShadowName,
                      ),
                      const SizedBox(height: 18),
                      _CurrencyField(
                        value: _selectedCurrency,
                        onTap: _pickCurrency,
                      ),
                      const SizedBox(height: 26),
                      const _CreatorPreviewCard(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateGroupTopBar extends StatelessWidget {
  const _CreateGroupTopBar({
    required this.isLoading,
    required this.onClose,
    required this.onCreate,
  });

  final bool isLoading;
  final VoidCallback onClose;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: context.spacing.space16,
        vertical: 10,
      ),
      child: SizedBox(
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: RIconButton(
                variant: RIconButtonVariant.ghost,
                icon: Iconsax.close_square,
                tooltip: context.l10n.commonClose,
                onTap: onClose,
              ),
            ),
            Text(
              context.l10n.groupNew,
              style: AppTypography.display(
                fontSize: 19,
                color: colors.textPrimary,
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: SizedBox(
                height: 40,
                child: ElevatedButton(
                  key: GroupKeys.createGroupButton,
                  onPressed: isLoading ? null : onCreate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.textPrimary,
                    foregroundColor: colors.scaffoldBackground,
                    disabledBackgroundColor: colors.textPrimary.withValues(
                      alpha: 0.72,
                    ),
                    disabledForegroundColor: colors.scaffoldBackground,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      14,
                      9,
                      14,
                      11,
                    ),
                    shape: const StadiumBorder(),
                    textStyle:
                        AppTypography.sans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                          height: 1.22,
                        ).copyWith(
                          leadingDistribution: TextLeadingDistribution.even,
                        ),
                  ),
                  child: isLoading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: colors.scaffoldBackground,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(context.l10n.groupCreate),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoodBlock extends StatelessWidget {
  const _MoodBlock();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.groupMoodTitle,
          style: AppTypography.display(
            fontSize: 30,
            color: colors.textPrimary,
            height: 1.05,
          ),
        ),
        SizedBox(height: context.spacing.space8),
        Text(
          context.l10n.groupMoodBody,
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

class _WireframeTextField extends StatelessWidget {
  const _WireframeTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.hintText,
    this.helperText,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final String? helperText;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;

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
          style: AppTypography.sans(
            fontSize: 17,
            color: colors.textPrimary,
            height: 1.2,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            helperText: helperText,
            filled: false,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
              vertical: context.spacing.space12,
            ),
            border: _inputBorder(colors.ink2),
            enabledBorder: _inputBorder(colors.ink2),
            focusedBorder: _inputBorder(colors.textPrimary, width: 1.5),
            errorBorder: _inputBorder(colors.error, width: 1.2),
            focusedErrorBorder: _inputBorder(colors.error, width: 1.5),
            helperStyle: AppTypography.sans(
              fontSize: 11,
              color: colors.textSecondary,
              height: 1.3,
            ),
            errorStyle: AppTypography.sans(
              fontSize: 11,
              color: colors.errorText,
              height: 1.3,
            ),
            // textMuted-decorative-justified: placeholder copy is non-functional guidance;
            // field labels and validation errors carry the required meaning.
            hintStyle: AppTypography.sans(
              fontSize: 17,
              color: colors.textMuted,
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }
}

class _CurrencyField extends StatelessWidget {
  const _CurrencyField({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(context.l10n.groupDefaultCurrency),
        InkWell(
          key: GroupKeys.currencyField,
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(vertical: context.spacing.space12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.ink2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: AppTypography.sans(
                      fontSize: 17,
                      color: colors.textPrimary,
                      height: 1.2,
                    ),
                  ),
                ),
                Icon(Icons.expand_more, size: 20, color: colors.textSecondary),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CreatorPreviewCard extends StatelessWidget {
  const _CreatorPreviewCard();

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
            context.l10n.groupCreatorTitle,
            style: AppTypography.sans(
              fontSize: 12,
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          Text(
            context.l10n.groupCreatorBody,
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

UnderlineInputBorder _inputBorder(Color color, {double width = 1}) {
  return UnderlineInputBorder(
    borderSide: BorderSide(color: color, width: width),
  );
}

/// Post-creation share prompt presented as a bottom sheet.
///
/// Shows the invite code via [InviteCodeDisplay] with copy and share actions.
class _SharePrompt extends StatelessWidget {
  final Group group;
  final VoidCallback onNavigate;

  const _SharePrompt({required this.group, required this.onNavigate});

  void _copyCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: group.inviteCode));
    HapticService.success();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.groupInviteCodeCopied),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _shareCode(BuildContext context) {
    shareText(
      context,
      context.l10n.groupShareInviteMessage(
        group.name,
        AppLinks.inviteUrl(group.inviteCode).toString(),
        group.inviteCode,
      ),
      subject: context.l10n.groupShareSubject(group.name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(context.spacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              group.name,
              style: AppTypography.display(
                fontSize: 26,
                color: colors.textPrimary,
                height: 1.1,
              ),
            ),
            SizedBox(height: context.spacing.space8),
            Text(
              context.l10n.groupShareCodeWithGroup,
              style: AppTypography.sans(
                fontSize: 13,
                color: colors.textSecondary,
                height: 1.5,
              ),
            ),
            SizedBox(height: context.spacing.space24),

            // Invite code pill (no inline buttons — buttons are below)
            InviteCodeDisplay(code: group.inviteCode),

            SizedBox(height: context.spacing.space24),

            // Copy and Share buttons
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => _copyCode(context),
                      child: Text(context.l10n.groupCopyCode),
                    ),
                  ),
                ),
                SizedBox(width: context.spacing.space12),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () => _shareCode(context),
                      child: Text(context.l10n.groupShare),
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: context.spacing.space16),

            Center(
              child: TextButton(
                onPressed: onNavigate,
                child: Text(context.l10n.commonDone),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
