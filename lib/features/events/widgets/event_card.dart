import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../ledger/providers/expense_provider.dart';
import '../models/event_model.dart';
import '../models/event_type_config.dart';

/// Card widget for displaying an event in the group timeline.
///
/// Displays event type icon, name with type badge, date range, participant
/// count, and live financial total from Firestore via eventExpensesProvider.
///
/// Past events (endDate before now) are wrapped in Opacity(0.6) per D-26.
class EventCard extends ConsumerWidget {
  final Event event;
  final VoidCallback onTap;

  const EventCard({
    super.key,
    required this.event,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = EventTypeConfig.forType(event.type);

    // Sum expenses from Firestore for live financial total (EVT-07).
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
      label:
          '${event.name}, ${config.label} event, ${event.participantIds.length} people',
      child: _PressableCard(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                BorderRadius.circular(AppColors.radiusLarge),
            boxShadow: AppColors.shadowRaised,
          ),
          padding: const EdgeInsets.all(AppColors.space16),
          child: Row(
            children: [
              // Type icon container — 48x48 with rounded corners and tinted bg
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: config.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(config.icon, size: 22, color: config.color),
              ),
              const SizedBox(width: AppColors.space12),
              // Main content column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name row with type badge
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            event.name,
                            style:
                                Theme.of(context).textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppColors.space4),
                        // Type badge chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: config.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(
                              AppColors.radiusSmall,
                            ),
                          ),
                          child: Text(
                            config.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: config.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppColors.space4),
                    // Meta row: date range · participant count
                    Text(
                      _buildMetaText(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: AppColors.space4),
                    // Live financial total from bridge trip expenses
                    Text(
                      '${totalSpent.toStringAsFixed(3)} ${event.currency}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppColors.space8),
              // Trailing chevron
              const Icon(
                Iconsax.arrow_right_3,
                size: 18,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );

    // Dim past events at 0.6 opacity per D-26. The card remains tappable.
    if (event.isPast) {
      return Opacity(opacity: 0.6, child: card);
    }
    return card;
  }

  /// Builds the meta text line with date range and participant count joined
  /// by middle dot separators (U+00B7).
  String _buildMetaText() {
    final parts = <String>[];

    // Date range
    if (event.startDate != null && event.endDate != null) {
      final fmt = DateFormat('MMM d');
      // Use en-dash (U+2013) between start and end dates per Copywriting Contract
      parts.add('${fmt.format(event.startDate!)} \u2013 ${fmt.format(event.endDate!)}');
    } else if (event.startDate != null) {
      parts.add(DateFormat('MMM d').format(event.startDate!));
    } else {
      parts.add('No dates');
    }

    // Participant count
    parts.add('${event.participantIds.length} people');

    // Join with middle dot (U+00B7)
    return parts.join(' \u00B7 ');
  }
}

/// Internal pressable wrapper with scale animation for tap feedback.
///
/// Scales to 0.98 on press down, restores to 1.0 on release.
class _PressableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _PressableCard({required this.child, required this.onTap});

  @override
  State<_PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<_PressableCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeInOut,
        child: widget.child,
      ),
    );
  }
}
