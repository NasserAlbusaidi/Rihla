import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../keys/group_keys.dart';
import '../models/group_model.dart';
import '../providers/group_provider.dart';
import '../widgets/invite_code_display.dart';

/// Screen for creating a new group.
///
/// Wireframe ref: `Wireframes/Rihla/hifi/screens-group.jsx` →
/// `Hi_CreateGroup()`.
///
/// Shows a warm-paper creation form with a mood header, glyph row, underlined
/// inputs, and a compact top-bar create action. On success, presents a share
/// prompt with the invite code (D-11, D-22).
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
          .createGroup(name: _nameController.text.trim(), currency: 'OMR')
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
          child: Column(
            children: [
              _CreateGroupTopBar(
                isLoading: isLoading,
                onClose: () => Navigator.of(context).pop(),
                onCreate: _createGroup,
              ),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _MoodBlock(),
                      const SizedBox(height: 22),
                      const _GlyphRow(),
                      const SizedBox(height: 26),
                      _WireframeTextField(
                        key: GroupKeys.groupNameInput,
                        label: 'Group Name',
                        controller: _nameController,
                        hintText: 'e.g. Family trip',
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? "Group name can't be empty."
                            : null,
                      ),
                      const SizedBox(height: 18),
                      _WireframeTextField(
                        key: GroupKeys.deviceNameInput,
                        label: 'Your name in this group',
                        controller: _displayNameController,
                        hintText: 'how friends will see you',
                        helperText:
                            'You can use a different name in each group.',
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Enter your name so others know who you are.'
                            : null,
                      ),
                      const SizedBox(height: 18),
                      const _ReadOnlyCurrencyField(),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SizedBox(
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: CloseButton(
                onPressed: onClose,
                color: colors.textPrimary,
                style: IconButton.styleFrom(
                  minimumSize: const Size(40, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            Text(
              'New group',
              style: AppTypography.display(
                fontSize: 19,
                color: colors.textPrimary,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                height: 34,
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
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: const StadiumBorder(),
                    textStyle: AppTypography.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
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
                      : const Text('Create'),
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
          "Who's coming along?",
          style: AppTypography.display(
            fontSize: 30,
            color: colors.textPrimary,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'A group is a circle of people you share expenses with — a household, a travel crew, a project team.',
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

class _GlyphRow extends StatelessWidget {
  const _GlyphRow();

  static const _glyphs = ['⛺', '⌂', '↗', '✦', '◐', '⌘'];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final palette = [
      _GlyphColor(colors.saffronSoft, colors.primaryDark),
      _GlyphColor(colors.success.withValues(alpha: 0.18), colors.success),
      _GlyphColor(colors.cat2.withValues(alpha: 0.16), colors.cat2),
      _GlyphColor(colors.cat5.withValues(alpha: 0.15), colors.cat5),
      _GlyphColor(colors.cat3.withValues(alpha: 0.18), colors.cat3),
      _GlyphColor(colors.cat4.withValues(alpha: 0.18), colors.cat4),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Group glyph'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var index = 0; index < _glyphs.length; index++)
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette[index].background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: index == 0 ? colors.textPrimary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Text(
                  _glyphs[index],
                  style: AppTypography.display(
                    fontSize: 24,
                    color: palette[index].foreground,
                    height: 1,
                  ),
                ),
              ),
          ],
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
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
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

class _ReadOnlyCurrencyField extends StatelessWidget {
  const _ReadOnlyCurrencyField();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Default currency'),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.ink2)),
          ),
          child: Text(
            'OMR · ر.ع.',
            style: AppTypography.sans(
              fontSize: 17,
              color: colors.textPrimary,
              height: 1.2,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.rule2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "You're the creator.",
            style: AppTypography.sans(
              fontSize: 12,
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          Text(
            'Once created, share an invite code to bring others in.',
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

class _GlyphColor {
  const _GlyphColor(this.background, this.foreground);

  final Color background;
  final Color foreground;
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
    final colors = context.colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
            const SizedBox(height: 8),
            Text(
              'Share this code with your group',
              style: AppTypography.sans(
                fontSize: 13,
                color: colors.textSecondary,
                height: 1.5,
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
