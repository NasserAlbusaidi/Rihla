import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/color_tokens.dart';
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
          const SizedBox(height: 12),
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColorTokens.light.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 24).copyWith(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Edit Name',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColorTokens.light.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: ProfileKeys.nameTextField,
                  controller: _controller,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Display name',
                    hintText: 'e.g. Nasser',
                    filled: true,
                    fillColor: AppColorTokens.light.inputFillWarm,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppColorTokens.light.borderWarm,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppColorTokens.light.focusBorderWarm,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Save button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    key: ProfileKeys.saveNameButton,
                    onPressed: isButtonEnabled ? _handleSave : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isButtonEnabled
                          ? AppColorTokens.light.primary
                          : AppColorTokens.light.primary.withValues(alpha: 0.5),
                      foregroundColor: AppColorTokens.light.textOnPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _buildButtonChild(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtonChild() {
    if (_showCheck) {
      return Icon(
        Icons.check_rounded,
        size: 20,
        color: AppColorTokens.light.textOnPrimary,
      );
    }
    if (_isSaving) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          color: AppColorTokens.light.textOnPrimary,
          strokeWidth: 2,
        ),
      );
    }
    return Text(
      'Save Name',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColorTokens.light.textOnPrimary,
      ),
    );
  }
}
