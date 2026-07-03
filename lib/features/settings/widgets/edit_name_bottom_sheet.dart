import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/name_validators.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../keys/profile_keys.dart';

/// Bottom sheet for editing the user's display name.
///
/// Aligned with the Hi_Sheet_EditName wireframe (tier 6 · sheets & pickers):
/// italic display title, prompt copy, text field, a static identity preview,
/// and a Cancel + Save action row. The preview is non-interactive — it
/// renders the real [RAvatar] derivation live from the typed text so it
/// never lies about what will be saved (#818 Wave 4).
class EditNameBottomSheet extends ConsumerStatefulWidget {
  const EditNameBottomSheet({
    super.key,
    required this.currentName,
    required this.onSave,
  });

  final String currentName;
  final Future<void> Function(String name) onSave;

  @override
  ConsumerState<EditNameBottomSheet> createState() =>
      _EditNameBottomSheetState();
}

class _EditNameBottomSheetState extends ConsumerState<EditNameBottomSheet> {
  late final TextEditingController _controller;
  bool _isSaving = false;
  bool _showCheck = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final error = validateDisplayName(_controller.text);
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    final displayName = normalizeDisplayName(_controller.text);

    setState(() => _isSaving = true);
    HapticService.medium();

    final stopwatch = Stopwatch()..start();
    try {
      await widget.onSave(displayName);
    } on DisplayNameTakenException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = context.l10n.displayNameTakenInGroup(e.groupName);
      });
      return;
    }
    final elapsed = stopwatch.elapsedMilliseconds;

    if (elapsed < 600) {
      await Future<void>.delayed(Duration(milliseconds: 600 - elapsed));
    }

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _showCheck = true;
    });
    HapticService.lightClick();

    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = _controller.text.trim();
    final isButtonEnabled = trimmed.isNotEmpty && !_isSaving && !_showCheck;
    final colors = context.colors;
    final spacing = context.spacing;
    final l10n = context.l10n;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: spacing.space12),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.rule2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(height: spacing.space12),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.space24,
            ).copyWith(bottom: spacing.space24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.editNameTitle,
                  style: AppTypography.display(
                    fontSize: 26,
                    color: colors.textPrimary,
                    height: 1.15,
                  ),
                ),
                SizedBox(height: context.spacing.space4),
                Text(
                  l10n.editNameHelper,
                  style: AppTypography.sans(
                    fontSize: 13,
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: spacing.space20),
                TextField(
                  key: ProfileKeys.nameTextField,
                  controller: _controller,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() => _errorText = null),
                  style: AppTypography.sans(
                    fontSize: 15,
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.editNameFieldLabel,
                    hintText: l10n.editNameFieldHint,
                    errorText: _errorText,
                    filled: true,
                    fillColor: colors.inputFillWarm,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.borderWarm),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: colors.focusBorderWarm,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: spacing.space20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.cardSoft,
                    borderRadius: BorderRadius.circular(spacing.radiusInput),
                    border: Border.all(color: colors.rule),
                  ),
                  child: Row(
                    children: [
                      RAvatar(name: trimmed, size: 44),
                      SizedBox(width: spacing.space12),
                      Expanded(
                        child: Text(
                          l10n.editNamePreviewCaption,
                          style: AppTypography.sans(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: spacing.space24),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _isSaving || _showCheck
                              ? null
                              : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: colors.rule2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            l10n.commonCancel,
                            style: AppTypography.sans(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          key: ProfileKeys.saveNameButton,
                          onPressed: isButtonEnabled ? _handleSave : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isButtonEnabled
                                ? colors.primary
                                : colors.primary.withValues(alpha: 0.5),
                            foregroundColor: colors.textOnPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: _buildButtonChild(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtonChild(BuildContext context) {
    final colors = context.colors;
    if (_showCheck) {
      return Icon(Icons.check_rounded, size: 20, color: colors.textOnPrimary);
    }
    if (_isSaving) {
      return SizedBox(
        width: context.spacing.space20,
        height: context.spacing.space20,
        child: CircularProgressIndicator(
          color: colors.textOnPrimary,
          strokeWidth: 2,
        ),
      );
    }
    return Text(
      context.l10n.commonSave,
      style: AppTypography.sans(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: colors.textOnPrimary,
      ),
    );
  }
}
