import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'event_model.dart';

/// Static configuration providing UI metadata for each [EventType].
///
/// This is the single source of truth for:
/// - Type picker cards (icon, label, description)
/// - Event card type badges
/// - Event hub header accents
///
/// Color assignments per UI-SPEC:
/// - Trip: context.colors.primary (#0D7B74)
/// - Camping: context.colors.successText (#047857) — WCAG 4.56:1
/// - Travel: context.colors.textSecondary (#6B7280)
/// - Night/Day Out: context.colors.textSecondary (#6B7280)
/// - Custom: context.colors.warning (#F59E0B)
class EventTypeConfig {
  final EventType type;
  final String label;
  final String description;
  final IconData icon;
  final Color color;

  const EventTypeConfig._({
    required this.type,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });

  // Colors use inline const literals since const Map cannot reference ThemeExtension fields.
  // Values match AppColorTokens.light exactly.
  static const Map<EventType, EventTypeConfig> _configs = {
    EventType.trip: EventTypeConfig._(
      type: EventType.trip,
      label: 'Trip',
      description: 'Full travel experience with all modules',
      icon: Iconsax.airplane,
      // design-token-justified: event type color — pending Plan 04 category token migration (maps to context.colors.primary)
      color: Color(0xFF0D7B74),
    ),
    EventType.camping: EventTypeConfig._(
      type: EventType.camping,
      label: 'Camping',
      description: 'Outdoor adventure with gear tracking',
      icon: Iconsax.tree,
      // design-token-justified: event type color — pending Plan 04 category token migration (maps to context.colors.successText)
      color: Color(0xFF047857),
    ),
    EventType.travel: EventTypeConfig._(
      type: EventType.travel,
      label: 'Travel',
      description: 'Journey with logistics and documents',
      icon: Iconsax.car,
      // design-token-justified: event type color — pending Plan 04 category token migration (maps to context.colors.textSecondary)
      color: Color(0xFF6B7280),
    ),
    EventType.nightDayOut: EventTypeConfig._(
      type: EventType.nightDayOut,
      label: 'Night/Day Out',
      description: 'Quick outing with expense splitting',
      icon: Iconsax.moon,
      // design-token-justified: event type color — pending Plan 04 category token migration (maps to context.colors.textSecondary)
      color: Color(0xFF6B7280),
    ),
    EventType.custom: EventTypeConfig._(
      type: EventType.custom,
      label: 'Custom',
      description: 'Pick your own modules',
      icon: Iconsax.element_3,
      // design-token-justified: event type color — pending Plan 04 category token migration (maps to context.colors.warning)
      color: Color(0xFFF59E0B),
    ),
  };

  /// Returns the [EventTypeConfig] for the given [type].
  static EventTypeConfig forType(EventType type) => _configs[type]!;

  /// Returns configs for all 5 event types in declaration order.
  static List<EventTypeConfig> get allTypes =>
      EventType.values.map((t) => _configs[t]!).toList();
}
