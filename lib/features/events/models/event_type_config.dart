import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import 'event_model.dart';

/// Static configuration providing UI metadata for each [EventType].
///
/// This is the single source of truth for:
/// - Type picker cards (icon, label, description)
/// - Event card type badges
/// - Event hub header accents
///
/// Color assignments per UI-SPEC:
/// - Trip: AppColors.mint (#13EC92)
/// - Camping: AppColors.emerald (#10B981)
/// - Travel: AppColors.sky (#0EA5E9)
/// - Night/Day Out: AppColors.indigo (#6366F1)
/// - Custom: AppColors.amber (#F59E0B)
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

  static const Map<EventType, EventTypeConfig> _configs = {
    EventType.trip: EventTypeConfig._(
      type: EventType.trip,
      label: 'Trip',
      description: 'Full travel experience with all modules',
      icon: Iconsax.airplane,
      color: AppColors.mint,
    ),
    EventType.camping: EventTypeConfig._(
      type: EventType.camping,
      label: 'Camping',
      description: 'Outdoor adventure with gear tracking',
      icon: Iconsax.tree,
      color: AppColors.emerald,
    ),
    EventType.travel: EventTypeConfig._(
      type: EventType.travel,
      label: 'Travel',
      description: 'Journey with logistics and documents',
      icon: Iconsax.car,
      color: AppColors.sky,
    ),
    EventType.nightDayOut: EventTypeConfig._(
      type: EventType.nightDayOut,
      label: 'Night/Day Out',
      description: 'Quick outing with expense splitting',
      icon: Iconsax.moon,
      color: AppColors.indigo,
    ),
    EventType.custom: EventTypeConfig._(
      type: EventType.custom,
      label: 'Custom',
      description: 'Pick your own modules',
      icon: Iconsax.element_3,
      color: AppColors.amber,
    ),
  };

  /// Returns the [EventTypeConfig] for the given [type].
  static EventTypeConfig forType(EventType type) => _configs[type]!;

  /// Returns configs for all 5 event types in declaration order.
  static List<EventTypeConfig> get allTypes =>
      EventType.values.map((t) => _configs[t]!).toList();
}
