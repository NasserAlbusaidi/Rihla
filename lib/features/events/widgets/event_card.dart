import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/animations/tap_bounce.dart';
import '../../ledger/providers/expense_provider.dart';
import '../models/event_model.dart';

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
  /// - Negative (you owe): AppColors.errorText
  /// - Positive (you are owed): AppColors.successText
  /// - Zero (settled): AppColors.textSecondary
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
    final totalSpent = expensesAsync.whenOrNull(
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
      label: '${event.name}, ${event.participantIds.length} people',
      child: TapBounce(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppColors.radiusLarge),
            boxShadow: AppColors.shadowRaised,
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
                        ? AppColors.textMuted
                        : AppColors.primary,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(AppColors.radiusLarge),
                    ),
                  ),
                ),
                // Main content area
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppColors.space16),
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
                        const SizedBox(height: AppColors.space4),
                        // Date range
                        Text(
                          _buildDateText(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppColors.space4),
                        // Personal balance or total spent
                        _buildBalanceLine(context),
                        const SizedBox(height: AppColors.space4),
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
          'You owe ${personalBalance!.abs().toStringAsFixed(3)} ${ event.currency}',
          AppColors.errorText,
        ),
      > 0 => (
          'You are owed ${personalBalance!.toStringAsFixed(3)} ${event.currency}',
          AppColors.successText,
        ),
      _ => ('Settled', AppColors.textSecondary),
    };

    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    );
  }

  /// Builds the expense count / total line.
  ///
  /// Uses textSecondary (not textMuted) — functional text per WCAG.
  Widget _buildExpenseCountLine(BuildContext context, Decimal totalSpent) {
    // When personalBalance is provided, show total as secondary info
    if (personalBalance != null) {
      return Text(
        '${totalSpent.toStringAsFixed(3)} ${event.currency}',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
      );
    }
    // When no personalBalance, show the total as the primary financial line
    return Text(
      '${totalSpent.toStringAsFixed(3)} ${event.currency}',
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
      ),
    );
  }

  /// Builds the date text with date range if dates are set.
  String _buildDateText() {
    if (event.startDate != null && event.endDate != null) {
      final fmt = DateFormat('MMM d');
      // Use en-dash (U+2013) between start and end dates
      return '${fmt.format(event.startDate!)} \u2013 ${fmt.format(event.endDate!)} \u00B7 ${event.participantIds.length} people';
    } else if (event.startDate != null) {
      return '${DateFormat('MMM d').format(event.startDate!)} \u00B7 ${event.participantIds.length} people';
    }
    return '${event.participantIds.length} people';
  }
}
