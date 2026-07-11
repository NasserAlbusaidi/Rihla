import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../../shared/widgets/r_avatar.dart';
import '../../../events/models/event_model.dart';
import '../../../groups/services/member_name_resolver.dart';

/// #280: single-choice "who paid" picker. Tap a participant to select and
/// close, returning the chosen id via [Navigator.pop]. Render-only names
/// (disambiguated, #289); the caller writes the id.
class PayerPickerSheet extends StatelessWidget {
  const PayerPickerSheet({
    super.key,
    required this.event,
    required this.selectedPayerId,
    this.eligibleIds,
  });

  final Event event;
  final String? selectedPayerId;

  /// #1149: candidate allow-list (active members ∪ the current selection —
  /// the caller unions in the selection so a legacy ghost payer never
  /// strands). Null → no filtering (membership unknown → fail open, and the
  /// pre-#1149 behavior for direct constructions).
  final Set<String>? eligibleIds;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final displayNames = MemberNameResolver.disambiguateEventParticipants(
      event,
    );
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colors.scaffoldBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                context.spacing.space20,
                context.spacing.space4,
                context.spacing.space20,
                context.spacing.space12,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  context.l10n.editorPaidBy,
                  style: AppTypography.sans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  for (final id in event.participantIds)
                    if (eligibleIds == null || eligibleIds!.contains(id))
                      _PayerOption(
                        name:
                            displayNames[id] ??
                            event.participantNames[id] ??
                            context.l10n.editorUnknownParticipant,
                        selected: id == selectedPayerId,
                        onTap: () => Navigator.of(context).pop(id),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayerOption extends StatelessWidget {
  const _PayerOption({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsetsDirectional.symmetric(
        horizontal: context.spacing.space12,
      ),
      leading: RAvatar(name: name, size: 36),
      title: Text(
        name,
        style: AppTypography.sans(
          fontSize: 15,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: colors.textPrimary,
        ),
      ),
      trailing: selected
          ? Icon(Iconsax.tick_circle, color: colors.primary, size: 20)
          : null,
    );
  }
}
