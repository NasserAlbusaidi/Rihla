import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../keys/profile_keys.dart';

/// Bottom sheet for editing the user's display name.
///
/// Presents a text field pre-filled with [currentName] and a Save button
/// that drives a spinner → checkmark → auto-close flow.
///
/// Caller is responsible for the actual save operation via [onSave].
class EditNameBottomSheet extends ConsumerStatefulWidget {
  const EditNameBottomSheet({
    super.key,
    required this.currentName,
    required this.onSave,
  });

  /// The name to pre-fill the text field with.
  final String currentName;

  /// Called with the trimmed new name when the user taps Save.
  /// Should complete the Firestore + SharedPreferences write.
  final Future<void> Function(String name) onSave;

  @override
  ConsumerState<EditNameBottomSheet> createState() =>
      _EditNameBottomSheetState();
}

class _EditNameBottomSheetState extends ConsumerState<EditNameBottomSheet> {
  late final TextEditingController _controller;
  bool _isSaving = false;
  bool _showCheck = false;

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

    // Ensure spinner is visible for at least 600ms for UX smoothness
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
    final isButtonEnabled = _controller.text.trim().isNotEmpty &&
        !_isSaving &&
        !_showCheck;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: context.spacing.space12),
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(height: context.spacing.space20),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.spacing.space24)
                .copyWith(bottom: context.spacing.space24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Edit Name',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                  ),
                ),
                SizedBox(height: context.spacing.space16),
                TextField(
                  key: ProfileKeys.nameTextField,
                  controller: _controller,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Display name',
                    hintText: 'e.g. Nasser',
                    filled: true,
                    fillColor: context.colors.inputFillWarm,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: context.colors.borderWarm,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: context.colors.focusBorderWarm,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: context.spacing.space24),
                // Save button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    key: ProfileKeys.saveNameButton,
                    onPressed: isButtonEnabled ? _handleSave : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isButtonEnabled
                          ? context.colors.primary
                          : context.colors.primary.withValues(alpha: 0.5),
                      foregroundColor: context.colors.textOnPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _buildButtonChild(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtonChild(BuildContext context) {
    if (_showCheck) {
      return Icon(
        Icons.check_rounded,
        size: 20,
        color: context.colors.textOnPrimary,
      );
    }
    if (_isSaving) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          color: context.colors.textOnPrimary,
          strokeWidth: 2,
        ),
      );
    }
    return Text(
      'Save Name',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: context.colors.textOnPrimary,
      ),
    );
  }
}
