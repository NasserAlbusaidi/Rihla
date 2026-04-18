import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';

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
        boxShadow: AppShadowTokens.standard.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Event Name ---
          Text(
            'Event Name',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: nameController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Summer camping trip',
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty
                    ? "Event name can't be empty."
                    : null,
          ),

          const SizedBox(height: 24),

          // --- Dates ---
          Row(
            children: [
              Text(
                'Dates',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              Text(
                '(optional)',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: context.colors.textSecondary),
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
                          ? DateFormat('MMM d, yyyy').format(startDate!)
                          : 'Start date',
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
                          ? DateFormat('MMM d, yyyy').format(endDate!)
                          : 'End date',
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
