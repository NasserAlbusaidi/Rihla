import 'package:flutter/material.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/utils/formatters.dart';
import '../../../events/models/event_model.dart';
import '../../keys/ledger_keys.dart';
import 'card_shell.dart';
import 'info_row.dart';

class WhereCard extends StatelessWidget {
  const WhereCard({super.key, required this.event, this.onChangeDestination});

  final Event event;

  /// Add-mode-only "change destination" tap target (#900 / PR-5 §1). `null`
  /// hides the affordance — this is the mode gate; edit mode never wires it
  /// since an existing expense is pinned to its event.
  final VoidCallback? onChangeDestination;

  @override
  Widget build(BuildContext context) {
    final date = event.startDate ?? event.createdAt;
    final onChangeDestination = this.onChangeDestination;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space24),
      child: CardShell(
        child: Column(
          children: [
            if (onChangeDestination != null)
              InfoRow(
                title: context.l10n.editorAddingToEvent(event.name),
                dense: true,
                trailing: TextButton(
                  key: LedgerKeys.editorChangeDestinationButton,
                  onPressed: onChangeDestination,
                  child: Text(context.l10n.editorChangeDestination),
                ),
              )
            else
              InfoRow(
                title: context.l10n.editorEvent,
                trailingText: event.name,
                dense: true,
              ),
            InfoRow(
              title: context.l10n.editorDate,
              trailingText: AppFormatters.formatShortMonthDay(
                date,
                Localizations.localeOf(context).toLanguageTag(),
              ),
              dense: true,
            ),
          ],
        ),
      ),
    );
  }
}
