import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/error_message_translator.dart';
import '../../../core/utils/localized_name_validators.dart';
import '../../home/widgets/group_glyph.dart';
import '../keys/group_keys.dart';
import '../models/group_model.dart';
import '../providers/group_provider.dart';
import 'group_stamp_picker.dart';

/// Bottom sheet where a group creator edits the group's display name + trip
/// stamp (symbol glyph + ink) in ONE atomic save. Reuses the exact
/// [GroupStampPicker] built for Create — here with `showHero: false` because
/// the sheet renders its own hero above the name field (vertical order:
/// hero → name → ink → symbol).
///
/// Creator-only is enforced by the rules (`isCreator()`); this surface is only
/// opened from the creator-gated ✎ entry. Design: PR-3 mockup Phone B
/// (`docs/design/mockups/trip-stamps-edit-group.html`).
class GroupEditSheet extends ConsumerStatefulWidget {
  const GroupEditSheet({super.key, required this.group});

  final Group group;

  /// Present the sheet as a scrollable modal over the current screen.
  static Future<void> show(BuildContext context, {required Group group}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => GroupEditSheet(group: group),
    );
  }

  @override
  ConsumerState<GroupEditSheet> createState() => _GroupEditSheetState();
}

class _GroupEditSheetState extends ConsumerState<GroupEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late String? _glyph;
  late int? _inkIndex;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group.name);
    _glyph = widget.group.glyph;
    _inkIndex = widget.group.inkIndex;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(groupServiceProvider)
          .updateGroupIdentity(
            groupId: widget.group.id,
            name: _nameController.text.trim(),
            glyph: _glyph,
            inkIndex: _inkIndex,
          );
      HapticService.success();
      if (mounted) Navigator.pop(context);
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _saving = false);
      unawaited(Sentry.captureException(e, stackTrace: st));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.groupUpdateNameFailed(friendlyMessageFor(context, e)),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return SafeArea(
      key: GroupKeys.editGroupSheet,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: spacing.space24,
          end: spacing.space24,
          top: spacing.space12,
          // Lift the sheet above the keyboard when the name field has focus.
          bottom: spacing.space24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header: Cancel · (spacer) · Save ──────────────────────────
              Row(
                children: [
                  TextButton(
                    key: GroupKeys.editGroupCancelButton,
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: Text(context.l10n.commonCancel),
                  ),
                  const Spacer(),
                  _saving
                      ? Padding(
                          padding: EdgeInsetsDirectional.only(
                            end: spacing.space12,
                          ),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.primary,
                            ),
                          ),
                        )
                      : TextButton(
                          key: GroupKeys.editGroupSaveButton,
                          onPressed: _save,
                          child: Text(
                            context.l10n.commonSave,
                            style: AppTypography.sans(
                              fontSize: 14,
                              color: colors.primaryDark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                ],
              ),
              SizedBox(height: spacing.space4),

              // ── Title ─────────────────────────────────────────────────────
              Center(
                child: Text(
                  context.l10n.groupEditTitle,
                  style: AppTypography.displayOf(
                    context,
                    fontSize: 24,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              SizedBox(height: spacing.space20),

              // ── Hero — tracks the live name AND the chosen stamp. Wrapping
              // ONLY the hero in the ListenableBuilder keeps the name field
              // (below) from rebuilding on its own keystrokes. ─────────────
              ListenableBuilder(
                listenable: _nameController,
                builder: (context, _) => Center(
                  child: GroupGlyph(
                    name: _nameController.text,
                    glyph: _glyph,
                    inkIndex: _inkIndex,
                    size: 80,
                  ),
                ),
              ),
              SizedBox(height: spacing.space24),

              // ── Name field (underlined, like _WireframeTextField). Outside
              // any name-controller ListenableBuilder. ────────────────────
              Form(
                key: _formKey,
                child: _NameField(controller: _nameController),
              ),
              SizedBox(height: spacing.space24),

              // ── Ink + symbol picker (no internal hero). ──────────────────
              GroupStampPicker(
                showHero: false,
                name: _nameController.text,
                value: (glyph: _glyph, inkIndex: _inkIndex),
                onChanged: (sel) => setState(() {
                  _glyph = sel.glyph;
                  _inkIndex = sel.inkIndex;
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Underlined name field mirroring `_WireframeTextField` from
/// `create_group_screen.dart` (label + underline-bordered [TextFormField] with
/// the localized display-name validator).
class _NameField extends StatelessWidget {
  const _NameField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.groupNameLabel,
          style: AppTypography.sans(
            fontSize: 11,
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        TextFormField(
          key: GroupKeys.editGroupNameField,
          controller: controller,
          textCapitalization: TextCapitalization.words,
          cursorColor: colors.textPrimary,
          style: AppTypography.sans(
            fontSize: 17,
            color: colors.textPrimary,
            height: 1.2,
          ),
          decoration: InputDecoration(
            hintText: context.l10n.groupNameHint,
            filled: false,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
              vertical: context.spacing.space12,
            ),
            border: _border(colors.ink2),
            enabledBorder: _border(colors.ink2),
            focusedBorder: _border(colors.textPrimary, width: 1.5),
            errorBorder: _border(colors.error, width: 1.2),
            focusedErrorBorder: _border(colors.error, width: 1.5),
            errorStyle: AppTypography.sans(
              fontSize: 11,
              color: colors.errorText,
              height: 1.3,
            ),
            // textMuted-decorative-justified: placeholder copy is non-functional
            // guidance; the field label + validation error carry the meaning.
            hintStyle: AppTypography.sans(
              fontSize: 17,
              color: colors.textMuted,
            ),
          ),
          validator: (value) => validateDisplayNameLocalized(context, value),
        ),
      ],
    );
  }

  static UnderlineInputBorder _border(Color color, {double width = 1}) {
    return UnderlineInputBorder(
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
