import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../keys/profile_keys.dart';

/// Bottom sheet for editing the user's display name.
///
/// Aligned with the Hi_Sheet_EditName wireframe (tier 6 · sheets & pickers):
/// italic display title, prompt copy, text field, initials selector, and a
/// Cancel + Save action row. The initials selector is presentation only —
/// the saved value remains the trimmed display name; initials are derived
/// elsewhere via [InitialsCircle].
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
  int _selectedInitialsStyle = 0;

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
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return;

    setState(() => _isSaving = true);
    HapticService.medium();

    final stopwatch = Stopwatch()..start();
    await widget.onSave(trimmed);
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

  List<String> _initialsOptions(String trimmed) {
    if (trimmed.isEmpty) return ['—', '—', '—'];
    final parts =
        trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final first = parts.first;
    final twoLetter = parts.length >= 2
        ? '${first[0]}${parts[1][0]}'.toUpperCase()
        : first.length >= 2
            ? first.substring(0, 2).toUpperCase()
            : first[0].toUpperCase();
    final oneLetter = first[0].toUpperCase();
    final triplet = first.length >= 3
        ? '${first[0].toUpperCase()}${first.substring(1, 3).toLowerCase()}'
        : first[0].toUpperCase();
    return [twoLetter, oneLetter, triplet];
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = _controller.text.trim();
    final isButtonEnabled = trimmed.isNotEmpty && !_isSaving && !_showCheck;
    final colors = context.colors;
    final spacing = context.spacing;
    final initials = _initialsOptions(trimmed);

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
            padding: EdgeInsets.symmetric(horizontal: spacing.space24)
                .copyWith(bottom: spacing.space24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'What should we call you?',
                  style: AppTypography.display(
                    fontSize: 26,
                    color: colors.textPrimary,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This is how friends will see you in groups.',
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
                  onChanged: (_) => setState(() {}),
                  style: AppTypography.sans(
                    fontSize: 15,
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Display name',
                    hintText: 'Your name',
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
                Text(
                  'INITIALS SHOWN WHEN NO PHOTO',
                  style: AppTypography.sans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0; i < initials.length; i++) ...[
                      Expanded(
                        child: _InitialsOption(
                          label: initials[i],
                          selected: _selectedInitialsStyle == i,
                          onTap: () {
                            HapticService.lightClick();
                            setState(() => _selectedInitialsStyle = i);
                          },
                        ),
                      ),
                      if (i < initials.length - 1) const SizedBox(width: 8),
                    ],
                  ],
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
                            'Cancel',
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
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          color: colors.textOnPrimary,
          strokeWidth: 2,
        ),
      );
    }
    return Text(
      'Save',
      style: AppTypography.sans(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: colors.textOnPrimary,
      ),
    );
  }
}

class _InitialsOption extends StatelessWidget {
  const _InitialsOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.inputFillWarm : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? colors.textPrimary : colors.rule2,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.mono(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
      ),
    );
  }
}
