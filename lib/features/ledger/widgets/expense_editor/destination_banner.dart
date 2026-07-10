import 'package:flutter/material.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../events/models/event_model.dart';
import '../../keys/ledger_keys.dart';

/// #1088: add-mode destination disclosure pinned under the top bar. The FAB
/// fast path (#900 §1) auto-picks an event; the only other disclosure
/// (`WhereCard`) is the last scroll section — below the fold on a phone.
class DestinationBanner extends StatelessWidget {
  const DestinationBanner({
    super.key,
    required this.event,
    required this.onChangeDestination,
  });

  final Event event;
  final VoidCallback onChangeDestination;

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.editorAddingToEvent(event.name);
    final change = context.l10n.editorChangeDestination;
    return Semantics(
      button: true,
      label: '$label, $change',
      onTap: onChangeDestination,
      excludeSemantics: true,
      child: InkWell(
        key: LedgerKeys.editorDestinationBanner,
        onTap: onChangeDestination,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: AlignmentDirectional.centerStart,
          padding: EdgeInsetsDirectional.only(
            start: context.spacing.space24,
            end: context.spacing.space24,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.sans(
                    fontSize: 13,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
              Text(
                ' · $change',
                maxLines: 1,
                style: AppTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.colors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
