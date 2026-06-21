import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/tokens/color_tokens.dart';
import 'event_model.dart';

/// Semantic color role assigned to each [EventType].
///
/// Resolves to a concrete [Color] at build time via [EventTypeConfig.resolveColor],
/// sourcing from the active [AppColorTokens] instance so light/dark themes
/// render correctly.
enum EventTypeColorRole {
  /// Maps to [AppColorTokens.primary] (teal).
  primary,

  /// Maps to [AppColorTokens.successText] (WCAG 4.56:1 on white).
  success,

  /// Maps to [AppColorTokens.textSecondary] (neutral gray).
  secondary,

  /// Maps to [AppColorTokens.warning] (amber).
  warning,
}

/// Static configuration providing UI metadata for each [EventType].
///
/// This is the single source of truth for:
/// - Type picker cards (icon, label, description)
/// - Event card type badges
/// - Event hub header accents
///
/// Color assignments per UI-SPEC:
/// - Trip: primary (teal)
/// - Camping: successText (WCAG 4.56:1)
/// - Travel: textSecondary
/// - Night/Day Out: textSecondary
/// - Custom: warning (amber)
///
/// Theme-aware color resolution: call [resolveColor] with the active
/// [AppColorTokens] (typically `context.colors`) to get the correct color
/// for the current theme brightness.
class EventTypeConfig {
  final EventType type;
  final String label;
  final String description;
  final IconData icon;
  final EventTypeColorRole colorRole;

  const EventTypeConfig._({
    required this.type,
    required this.label,
    required this.description,
    required this.icon,
    required this.colorRole,
  });

  /// Resolve the theme-aware color for this event type.
  ///
  /// Pass `context.colors` from a `BuildContext` to get a color that flips
  /// between light and dark automatically.
  Color resolveColor(AppColorTokens tokens) => switch (colorRole) {
    EventTypeColorRole.primary => tokens.primary,
    EventTypeColorRole.success => tokens.successText,
    EventTypeColorRole.secondary => tokens.textSecondary,
    EventTypeColorRole.warning => tokens.warning,
  };

  static const Map<EventType, EventTypeConfig> _configs = {
    EventType.trip: EventTypeConfig._(
      type: EventType.trip,
      label: 'Trip',
      description: 'Plan a shared trip with expenses and activity',
      icon: Iconsax.airplane,
      colorRole: EventTypeColorRole.primary,
    ),
    EventType.camping: EventTypeConfig._(
      type: EventType.camping,
      label: 'Camping',
      description: 'Outdoor trip with shared expense tracking',
      icon: Iconsax.tree,
      colorRole: EventTypeColorRole.success,
    ),
    EventType.travel: EventTypeConfig._(
      type: EventType.travel,
      label: 'Travel',
      description: 'Journey with group expenses and activity',
      icon: Iconsax.car,
      colorRole: EventTypeColorRole.secondary,
    ),
    EventType.nightDayOut: EventTypeConfig._(
      type: EventType.nightDayOut,
      label: 'Night/Day Out',
      description: 'Quick outing with expense splitting',
      icon: Iconsax.moon,
      colorRole: EventTypeColorRole.secondary,
    ),
    EventType.custom: EventTypeConfig._(
      type: EventType.custom,
      label: 'Custom',
      description: 'Start from a flexible event setup',
      icon: Iconsax.element_3,
      colorRole: EventTypeColorRole.warning,
    ),
  };

  /// Returns the [EventTypeConfig] for the given [type].
  static EventTypeConfig forType(EventType type) => _configs[type]!;

  /// Returns configs for all 5 event types in declaration order.
  static List<EventTypeConfig> get allTypes =>
      EventType.values.map((t) => _configs[t]!).toList();

  /// Creatable types for the create-event chip-row — excludes [EventType.custom]
  /// (Custom is no longer creatable; #489). Existing Custom events still render
  /// via [forType], which retains all five configs.
  static List<EventTypeConfig> get selectableTypes =>
      allTypes.where((c) => c.type != EventType.custom).toList();
}
