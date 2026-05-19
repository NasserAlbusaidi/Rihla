import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/localized_dates.dart';
import '../../../core/utils/localized_name_validators.dart';

/// Card widget containing the event name field and start/end date pickers.
///
/// Purely presentational — owns no state. The parent [CreateEventScreen]
/// owns [nameController], [startDate], [endDate], and date-picker callbacks.
///
/// Extracted from [CreateEventScreen] (Phase 36 ARCH-01 decomposition).
class EventDetailsCard extends StatelessWidget {
  final TextEditingController nameController;
  final DateTime? startDate;
  final DateTime? endDate;
  final VoidCallback onPickStartDate;
  final VoidCallback onPickEndDate;

  const EventDetailsCard({
    super.key,
    required this.nameController,
    required this.startDate,
    required this.endDate,
    required this.onPickStartDate,
    required this.onPickEndDate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: context.shadows.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Event Name ---
          Text(
            context.l10n.eventNameLabel,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: nameController,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: context.l10n.eventNameHint),
            validator: (value) => validateDisplayNameLocalized(context, value),
          ),

          const SizedBox(height: 24),

          // --- Dates ---
          Row(
            children: [
              Text(
                context.l10n.eventDatesLabel,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              Text(
                context.l10n.eventOptionalLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onPickStartDate,
                    child: Text(
                      startDate != null
                          ? formatShortMonthDayYear(context, startDate!)
                          : context.l10n.eventStartDate,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onPickEndDate,
                    child: Text(
                      endDate != null
                          ? formatShortMonthDayYear(context, endDate!)
                          : context.l10n.eventEndDate,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
