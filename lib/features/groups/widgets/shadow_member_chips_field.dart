import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/name_validators.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../keys/group_keys.dart';

/// #278 V1 — the "Who's in?" add-by-name chips field on the create-group
/// screen.
///
/// The creator types a friend's name and submits it; it becomes a removable
/// placeholder ("shadow") chip. Names are LOCAL UI state owned by the host
/// screen ([names]) — this widget only renders them and reports add/remove. On
/// Create, the host fans out one `addShadowMember` callable per name.
///
/// The field is connectivity-gated: when [enabled] is false (offline), the
/// input is disabled and an offline hint is shown — the callable has no offline
/// replay, but the group itself still creates with just the creator.
class ShadowMemberChipsField extends StatefulWidget {
  const ShadowMemberChipsField({
    super.key,
    required this.names,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
    this.disabledHint,
  });

  /// The placeholder names entered so far, in entry order.
  final List<String> names;

  /// Whether the input accepts new names (false while offline, or — #818 —
  /// while the creator is anonymous).
  final bool enabled;

  /// Called with a trimmed, valid name when the user submits the input.
  /// The host de-duplicates and validates collisions; this widget only filters
  /// empty/invalid entries.
  final ValueChanged<String> onAdd;

  /// Called with the exact name to remove when its chip's × is tapped.
  final ValueChanged<String> onRemove;

  /// #818: footer copy shown instead of [createGroupShadowOfflineHint] when
  /// [enabled] is false for a reason OTHER than connectivity (an anonymous
  /// creator) — null falls back to the offline hint.
  final String? disabledHint;

  @override
  State<ShadowMemberChipsField> createState() => _ShadowMemberChipsFieldState();
}

class _ShadowMemberChipsFieldState extends State<ShadowMemberChipsField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String raw) {
    final name = normalizeDisplayName(raw);
    // Skip empties / invalid (control chars, too long); the host owns
    // collision de-dup so the chip list stays clean.
    if (name.isEmpty || displayNameValidationError(name) != null) {
      _controller.clear();
      return;
    }
    widget.onAdd(name);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.createGroupWhoElse,
          style: AppTypography.sans(
            fontSize: 11,
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        if (widget.names.isNotEmpty) ...[
          SizedBox(height: context.spacing.space8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in widget.names)
                _ShadowChip(
                  name: name,
                  onRemove: () => widget.onRemove(name),
                ),
            ],
          ),
        ],
        SizedBox(height: context.spacing.space8),
        TextField(
          key: GroupKeys.shadowMemberInput,
          controller: _controller,
          enabled: widget.enabled,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: _submit,
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
            prefixIcon: widget.enabled
                ? Icon(Icons.add, size: 20, color: colors.primary)
                : null,
            prefixIconConstraints: const BoxConstraints(
              minWidth: 28,
              minHeight: 0,
            ),
            hintText: context.l10n.createGroupAddNameHint,
            // textMuted-decorative-justified: placeholder hint copy, not content.
            hintStyle: AppTypography.sans(fontSize: 17, color: colors.textMuted),
            contentPadding: EdgeInsets.symmetric(
              vertical: context.spacing.space12,
            ),
            border: _border(colors.ink2),
            enabledBorder: _border(colors.ink2),
            focusedBorder: _border(colors.textPrimary, width: 1.5),
            disabledBorder: _border(colors.rule2),
          ),
        ),
        SizedBox(height: context.spacing.space8),
        Text(
          widget.enabled
              ? context.l10n.groupCreatorBody
              : (widget.disabledHint ??
                    context.l10n.createGroupShadowOfflineHint),
          style: AppTypography.sans(
            fontSize: 11,
            color: colors.textSecondary,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  UnderlineInputBorder _border(Color color, {double width = 1}) {
    return UnderlineInputBorder(
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

/// A single removable placeholder chip — soft outlined to read as an unclaimed
/// "shadow" person until a real user joins and claims the name (#278).
class _ShadowChip extends StatelessWidget {
  const _ShadowChip({required this.name, required this.onRemove});

  final String name;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: GroupKeys.shadowMemberChip(name),
      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 6, 6),
      decoration: BoxDecoration(
        color: colors.cardSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.rule2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // #1168: pre-join placeholder — no userId exists until this name
          // is claimed by a real member, so name fallback is correct here.
          RAvatar(name: name, size: 22),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.sans(
                fontSize: 14,
                color: colors.textPrimary,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkResponse(
            key: GroupKeys.shadowMemberRemove(name),
            onTap: onRemove,
            radius: 16,
            child: Icon(Icons.close, size: 16, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
