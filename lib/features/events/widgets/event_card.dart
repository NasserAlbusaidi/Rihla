import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/utils/localized_dates.dart';
import '../../../shared/animations/tap_bounce.dart';
import '../../ledger/providers/expense_provider.dart';
import '../models/event_model.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// Card widget for displaying an event in the group timeline.
///
/// Phase 20 redesign (D-01, D-02, D-03):
/// - Left accent bar replaces 48x48 icon container and type badge chip
/// - Teal accent for active events, gray for past events (D-03)
/// - Optional inline personal balance text with WCAG-safe color coding (D-01)
/// - Past events wrapped in Opacity(0.6) per D-02
class EventCard extends ConsumerWidget {
  final Event event;
  final VoidCallback onTap;

  /// Optional personal balance for the current user in this event.
  ///
  /// When non-null, renders an inline balance text with color coding:
  /// - Negative (you owe): context.colors.errorText
  /// - Positive (you are owed): context.colors.successText
  /// - Zero (settled): context.colors.textSecondary
  ///
  /// When null, shows the event's live total spent amount.
  final Decimal? personalBalance;

  const EventCard({
    super.key,
    required this.event,
    required this.onTap,
    this.personalBalance,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Sum expenses from Firestore for live financial total (EVT-07).
    // Only used when personalBalance is null.
    final eventRef = (groupId: event.groupId, eventId: event.id);
    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    final totalSpent =
        expensesAsync.whenOrNull(
          data: (expenses) {
            if (expenses.isEmpty) return Decimal.zero;
            return expenses.fold<Decimal>(
              Decimal.zero,
              (sum, e) => sum + e.amount,
            );
          },
        ) ??
        Decimal.zero;

    final card = Semantics(
      button: true,
      label: context.l10n.eventSemanticCard(
        event.name,
        event.participantIds.length,
      ),
      child: TapBounce(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.cardSurface,
            borderRadius: BorderRadius.circular(context.spacing.radiusCard),
            border: Border.all(
              color: context.colors.border.withValues(alpha: 0.5),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left accent bar — teal for active, gray for past (D-03)
                Container(
                  width: 3.0,
                  decoration: BoxDecoration(
                    color: event.isPast
                        ? context.colors.textSecondary.withValues(alpha: 0.3)
                        : context.colors.primary,
                    borderRadius: const BorderRadiusDirectional.only(
                      topStart: Radius.circular(20),
                      bottomStart: Radius.circular(20),
                    ),
                  ),
                ),
                // Main content area
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(context.spacing.space16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Event name
                        Text(
                          event.name,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: context.spacing.space4),
                        // Date range
                        Text(
                          _buildDateText(context),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: context.colors.textSecondary,
                          ),
                        ),
                        SizedBox(height: context.spacing.space4),
                        // Personal balance or total spent
                        _buildBalanceLine(context),
                        SizedBox(height: context.spacing.space4),
                        // Expense count
                        _buildExpenseCountLine(context, totalSpent),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Dim past events at 0.6 opacity per D-02. The card remains tappable.
    if (event.isPast) {
      return Opacity(opacity: 0.6, child: card);
    }
    return card;
  }

  /// Builds the personal balance line if personalBalance is set,
  /// otherwise renders nothing (expense count line handles totals).
  Widget _buildBalanceLine(BuildContext context) {
    if (personalBalance == null) {
      return const SizedBox.shrink();
    }

    // Dart 3 switch for balance color coding and text (D-01)
    final (text, color) = switch (personalBalance!.compareTo(Decimal.zero)) {
      < 0 => (
        context.l10n.eventYouOweAmount(
          personalBalance!.abs().toStringAsFixed(3),
          'OMR',
        ),
        context.colors.errorText,
      ),
      > 0 => (
        context.l10n.eventYouAreOwedAmount(
          personalBalance!.toStringAsFixed(3),
          'OMR',
        ),
        context.colors.successText,
      ),
      _ => (context.l10n.ledgerSettled, context.colors.textSecondary),
    };

    return Text(
      text,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
    );
  }

  /// Builds the expense count / total line.
  ///
  /// Uses textSecondary (not textMuted) — functional text per WCAG.
  Widget _buildExpenseCountLine(BuildContext context, Decimal totalSpent) {
    // When personalBalance is provided, show total as secondary info
    if (personalBalance != null) {
      return Text(
        'OMR ${totalSpent.toStringAsFixed(3)}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: context.colors.textSecondary,
        ),
      );
    }
    // When no personalBalance, show the total as the primary financial line
    return Text(
      'OMR ${totalSpent.toStringAsFixed(3)}',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: context.colors.textSecondary,
      ),
    );
  }

  /// Builds the date text with date range if dates are set.
  String _buildDateText(BuildContext context) {
    if (event.startDate != null && event.endDate != null) {
      return '${formatDateRangeShort(context, event.startDate, event.endDate)} '
          '\u00B7 ${context.l10n.ledgerPeople(event.participantIds.length)}';
    } else if (event.startDate != null) {
      return '${formatShortMonthDay(context, event.startDate!)} '
          '\u00B7 ${context.l10n.ledgerPeople(event.participantIds.length)}';
    }
    return context.l10n.ledgerPeople(event.participantIds.length);
  }
}
