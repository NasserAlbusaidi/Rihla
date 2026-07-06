import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../keys/group_keys.dart';

/// Bottom-sheet "Delete group" confirmation aligned with Hi_Sheet_Delete
/// (tier 6 · sheets & pickers).
///
/// Renders a rust trash badge, italic display title, scope copy that names
/// the affected group and member count, and a type-to-confirm input that
/// unlocks the destructive button. Invokes [onConfirm] only once the typed
/// token matches [groupName] (case-insensitive, trimmed).
Future<void> showDeleteGroupSheet(
  BuildContext context, {
  required String groupName,
  required int memberCount,
  required VoidCallback onConfirm,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.scaffoldBackground,
    isScrollControlled: true,
    // Destructive-action scrim — darker than the default Material barrier
    // (#000000 @ 0.32) to signal danger on a sheet that requires type-to-confirm.
    // Resolves to ink via the saffron palette.
    barrierColor: context.colors.textPrimary.withValues(alpha: 0.55),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _DeleteGroupSheet(
      groupName: groupName,
      memberCount: memberCount,
      onConfirm: onConfirm,
    ),
  );
}

class _DeleteGroupSheet extends StatefulWidget {
  const _DeleteGroupSheet({
    required this.groupName,
    required this.memberCount,
    required this.onConfirm,
  });

  final String groupName;
  final int memberCount;
  final VoidCallback onConfirm;

  @override
  State<_DeleteGroupSheet> createState() => _DeleteGroupSheetState();
}

class _DeleteGroupSheetState extends State<_DeleteGroupSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _matches =>
      _controller.text.trim().toLowerCase() ==
      widget.groupName.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final rustSoft = Color.alphaBlend(
      colors.error.withValues(alpha: 0.18),
      colors.cardSurface,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Container(
            key: GroupKeys.deleteGroupDialog,
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
                  padding: EdgeInsets.symmetric(horizontal: spacing.space24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: rustSoft,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Iconsax.trash,
                          size: 22,
                          color: colors.error,
                        ),
                      ),
                      SizedBox(height: context.spacing.space12),
                      Text(
                        context.l10n.groupDeleteSheetTitle,
                        style: AppTypography.displayOf(
                          context,
                          fontSize: 28,
                          color: colors.textPrimary,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 6),
                      RichText(
                        text: TextSpan(
                          style: AppTypography.sans(
                            fontSize: 13,
                            color: colors.textSecondary,
                            height: 1.45,
                          ),
                          children: [
                            TextSpan(
                              text: context.l10n.groupDeleteSheetRemovesPrefix,
                            ),
                            TextSpan(
                              text: widget.groupName,
                              style: AppTypography.sans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                            TextSpan(
                              text: widget.memberCount > 0
                                  ? context.l10n.groupDeleteSheetMembersBody(
                                      widget.memberCount,
                                    )
                                  : context.l10n.groupDeleteSheetEveryoneBody,
                            ),
                            TextSpan(
                              text: context.l10n.groupDeleteSheetUndo,
                              style: AppTypography.sans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colors.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: spacing.space20),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: spacing.space24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            context.l10n.groupDeleteSheetTypePrefix,
                            style: AppTypography.sans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colors.textSecondary,
                              letterSpacing: 0.8,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.inputFill,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              widget.groupName,
                              // User free-text (type-to-confirm target) —
                              // sans in every locale (#841).
                              style: AppTypography.sans(
                                fontSize: 11,
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            context.l10n.groupDeleteSheetTypeSuffix,
                            style: AppTypography.sans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colors.textSecondary,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: context.spacing.space8),
                      TextField(
                        controller: _controller,
                        autofocus: false,
                        onChanged: (_) => setState(() {}),
                        // User free-text input the user must match against the
                        // group name — sans in every locale (#841).
                        style: AppTypography.sans(
                          fontSize: 15,
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: colors.cardSurface,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: context.spacing.space12,
                          ),
                          suffixIcon: _matches
                              ? Icon(Icons.check_rounded, color: colors.success)
                              : null,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _matches ? colors.success : colors.error,
                              width: 1.5,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _matches ? colors.success : colors.error,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: spacing.space20),
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    spacing.space24,
                    0,
                    spacing.space24,
                    spacing.space20,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: colors.rule2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              context.l10n.commonCancel,
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
                          child: ElevatedButton.icon(
                            key: GroupKeys.deleteGroupConfirmButton,
                            onPressed: _matches
                                ? () {
                                    HapticService.medium();
                                    Navigator.pop(context);
                                    widget.onConfirm();
                                  }
                                : null,
                            icon: const Icon(Iconsax.trash, size: 14),
                            label: Text(
                              context.l10n.groupDeleteSheetConfirm,
                              style: AppTypography.sans(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _matches
                                  ? colors.error
                                  : colors.error.withValues(alpha: 0.4),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                              disabledBackgroundColor: colors.error.withValues(
                                alpha: 0.35,
                              ),
                              disabledForegroundColor: Colors.white.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
