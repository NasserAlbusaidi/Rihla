import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/localized_name_validators.dart';
import '../../../core/utils/name_validators.dart';
import '../keys/group_keys.dart';
import '../providers/group_provider.dart';

/// #278 PR3: creator-only sheet to add a placeholder ("shadow") member by name
/// inside an existing group.
///
/// Routes through the `addShadowMember` Cloud callable (creator-only,
/// online-only — no offline replay), so the input is connectivity-gated: while
/// offline the field is disabled and an offline hint is shown. On
/// [ShadowMemberNameTakenException] the specific taken name is surfaced inline
/// and the sheet stays open; on success the sheet closes and the live
/// `groupMembersProvider` stream materialises the new member tile.
class AddShadowMemberSheet extends ConsumerStatefulWidget {
  const AddShadowMemberSheet({super.key, required this.groupId});

  final String groupId;

  /// Presents the sheet as a modal bottom sheet over [context].
  static Future<void> show(BuildContext context, {required String groupId}) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.cardSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => AddShadowMemberSheet(groupId: groupId),
    );
  }

  @override
  ConsumerState<AddShadowMemberSheet> createState() =>
      _AddShadowMemberSheetState();
}

class _AddShadowMemberSheetState extends ConsumerState<AddShadowMemberSheet> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = normalizeDisplayName(_controller.text);
    final validationError = validateDisplayNameLocalized(context, name);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref
          .read(groupServiceProvider)
          .addShadowMember(groupId: widget.groupId, displayName: name);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ShadowMemberNameTakenException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = context.l10n.createGroupShadowNameTaken(e.name);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final online =
        ref.watch(connectivityProvider) == ConnectivityStatus.online;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          context.spacing.space24,
          context.spacing.space24,
          context.spacing.space24,
          context.spacing.space24 + bottomInset,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.groupAddPersonTitle,
              style: AppTypography.displayOf(
                context,
                fontSize: 22,
                color: colors.textPrimary,
                height: 1.1,
              ),
            ),
            SizedBox(height: context.spacing.space8),
            Text(
              context.l10n.groupAddPersonSubtitle,
              style: AppTypography.sans(
                fontSize: 13,
                color: colors.textSecondary,
                height: 1.5,
              ),
            ),
            SizedBox(height: context.spacing.space20),
            TextField(
              key: GroupKeys.addPersonInput,
              controller: _controller,
              enabled: online && !_submitting,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              cursorColor: colors.textPrimary,
              maxLength: kDisplayNameMaxLength,
              style: AppTypography.sans(
                fontSize: 17,
                color: colors.textPrimary,
                height: 1.2,
              ),
              decoration: InputDecoration(
                counterText: '',
                isDense: true,
                filled: false,
                hintText: context.l10n.createGroupAddNameHint,
                // textMuted-decorative-justified: placeholder hint copy, not content.
                hintStyle: AppTypography.sans(
                  fontSize: 17,
                  color: colors.textMuted,
                ),
                errorText: _error,
                errorMaxLines: 3,
                contentPadding: EdgeInsets.symmetric(
                  vertical: context.spacing.space12,
                ),
                border: _border(colors.ink2),
                enabledBorder: _border(colors.ink2),
                focusedBorder: _border(colors.textPrimary, width: 1.5),
                disabledBorder: _border(colors.rule2),
                errorBorder: _border(colors.error, width: 1.2),
                focusedErrorBorder: _border(colors.error, width: 1.5),
              ),
            ),
            if (!online) ...[
              SizedBox(height: context.spacing.space8),
              Text(
                context.l10n.createGroupShadowOfflineHint,
                style: AppTypography.sans(
                  fontSize: 11,
                  color: colors.textSecondary,
                  height: 1.3,
                ),
              ),
            ],
            SizedBox(height: context.spacing.space20),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                key: GroupKeys.addPersonSubmit,
                onPressed: (online && !_submitting) ? _submit : null,
                child: _submitting
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: colors.scaffoldBackground,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(context.l10n.groupAddPersonAction),
              ),
            ),
          ],
        ),
      ),
    );
  }

  UnderlineInputBorder _border(Color color, {double width = 1}) {
    return UnderlineInputBorder(
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
