import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../models/event_type_config.dart';
import '../utils/event_display.dart';

/// Pill badge showing the event type icon and label.
///
/// Extracted from [CreateEventScreen] (Phase 36 ARCH-01 decomposition).
/// Purely presentational — no state, no providers.
class EventTypeBadge extends StatelessWidget {
  final EventTypeConfig typeConfig;

  const EventTypeBadge({super.key, required this.typeConfig});

  @override
  Widget build(BuildContext context) {
    final typeColor = typeConfig.resolveColor(context.colors);
    return Container(
      margin: EdgeInsets.only(bottom: context.spacing.space12),
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space16, vertical: context.spacing.space12),
      decoration: BoxDecoration(
        color: typeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Icon(typeConfig.icon, size: 20, color: typeColor),
          SizedBox(width: context.spacing.space8),
          Text(
            typeConfig.type.localizedLabel(context.l10n),
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
