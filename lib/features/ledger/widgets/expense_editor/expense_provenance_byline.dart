import 'package:flutter/material.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../events/models/event_model.dart';
import '../../models/expense_model.dart';
import '../../utils/expense_provenance.dart';

/// #248 PR5: compact "Added by … · edited by …" byline under the description.
/// Reads the expense's createdBy / lastEditedBy uids and resolves them through
/// the same disambiguated participantNames chain the payer uses, so creator and
/// payer are surfaced side by side without conflating them. Renders nothing for
/// legacy expenses with no creator.
class ExpenseProvenanceByline extends StatelessWidget {
  const ExpenseProvenanceByline({
    super.key,
    required this.displayNames,
    required this.event,
    required this.expense,
  });

  /// #289 disambiguation map, shared from the parent (#627 follow-up).
  final Map<String, String> displayNames;
  final Event event;
  final Expense expense;

  @override
  Widget build(BuildContext context) {
    String resolve(String uid) =>
        displayNames[uid] ??
        event.participantNames[uid] ??
        context.l10n.activitySomeone;

    final provenance = resolveExpenseProvenance(
      createdBy: expense.createdBy,
      lastEditedBy: expense.lastEditedBy,
      resolveName: resolve,
    );
    if (provenance == null) return const SizedBox.shrink();

    final text = provenance.editorName == null
        ? context.l10n.editorProvenanceAdded(provenance.creatorName)
        : context.l10n.editorProvenanceAddedEdited(
            provenance.creatorName,
            provenance.editorName!,
          );

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        context.spacing.space24,
        context.spacing.space8,
        context.spacing.space24,
        0,
      ),
      child: Text(
        text,
        style: AppTypography.sans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}
