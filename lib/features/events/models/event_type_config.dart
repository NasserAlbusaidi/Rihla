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
/// - Trip: AppColorTokens.light.primary (#0D7B74)
/// - Camping: AppColorTokens.light.successText (#047857) — WCAG 4.56:1
/// - Travel: AppColorTokens.light.textSecondary (#6B7280)
/// - Night/Day Out: AppColorTokens.light.textSecondary (#6B7280)
/// - Custom: AppColorTokens.light.warning (#F59E0B)
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
      color: Color(0xFF0D7B74), // AppColorTokens.light.primary
    ),
    EventType.camping: EventTypeConfig._(
      type: EventType.camping,
      label: 'Camping',
      description: 'Outdoor adventure with gear tracking',
      icon: Iconsax.tree,
      color: Color(0xFF047857), // AppColorTokens.light.successText — WCAG 4.56:1 on white
                               // (const map cannot reference ThemeExtension fields)
    ),
    EventType.travel: EventTypeConfig._(
      type: EventType.travel,
      label: 'Travel',
      description: 'Journey with logistics and documents',
      icon: Iconsax.car,
      color: Color(0xFF6B7280), // AppColorTokens.light.textSecondary
    ),
    EventType.nightDayOut: EventTypeConfig._(
      type: EventType.nightDayOut,
      label: 'Night/Day Out',
      description: 'Quick outing with expense splitting',
      icon: Iconsax.moon,
      color: Color(0xFF6B7280), // AppColorTokens.light.textSecondary
    ),
    EventType.custom: EventTypeConfig._(
      type: EventType.custom,
      label: 'Custom',
      description: 'Pick your own modules',
      icon: Iconsax.element_3,
      color: Color(0xFFF59E0B), // AppColorTokens.light.warning
    ),
  };

  /// Returns the [EventTypeConfig] for the given [type].
  static EventTypeConfig forType(EventType type) => _configs[type]!;

  /// Returns configs for all 5 event types in declaration order.
  static List<EventTypeConfig> get allTypes =>
      EventType.values.map((t) => _configs[t]!).toList();
}
