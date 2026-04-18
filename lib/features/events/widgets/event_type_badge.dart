import 'package:flutter/material.dart';

import '../../../core/theme/tokens/domain_aliases.dart';
import '../models/event_type_config.dart';

/// Pill badge showing the event type icon and label.
///
/// Extracted from [CreateEventScreen] (Phase 36 ARCH-01 decomposition).
/// Purely presentational — no state, no providers.
class EventTypeBadge extends StatelessWidget {
  final EventTypeConfig typeConfig;

  const EventTypeBadge({
    super.key,
    required this.typeConfig,
  });

  @override
  Widget build(BuildContext context) {
    final typeColor = typeConfig.resolveColor(context.colors);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: typeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Icon(typeConfig.icon, size: 20, color: typeColor),
          const SizedBox(width: 8),
          Text(
            typeConfig.label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: typeColor,
            ),
          ),
        ],
      ),
    );
  }
}
