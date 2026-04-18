import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/tokens/domain_aliases.dart';
import '../keys/event_keys.dart';
import '../models/event_model.dart';

/// Card widget for toggling modules on a Custom event (D-14).
///
/// Renders one [_ModuleToggleRow] per module. The [onModulesChanged] callback
/// fires whenever any toggle flips, passing the updated [EventModules] value.
///
/// Only shown for [EventType.custom] events.
///
/// Extracted from [CreateEventScreen] (Phase 36 ARCH-01 decomposition).
/// Purely presentational — no state, no providers.
class EventModulesCard extends StatelessWidget {
  final EventModules modules;
  final ValueChanged<EventModules> onModulesChanged;

  const EventModulesCard({
    super.key,
    required this.modules,
    required this.onModulesChanged,
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
          Text(
            'Modules',
            key: EventKeys.modulesSection,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _ModuleToggleRow(
            key: EventKeys.moduleLedgerToggle,
            icon: Iconsax.dollar_circle,
            label: 'Ledger',
            color: context.colors.success,
            value: modules.ledger,
            onChanged: (v) =>
                onModulesChanged(modules.copyWith(ledger: v)),
          ),
          _ModuleToggleRow(
            key: EventKeys.moduleGearToggle,
            icon: Iconsax.bag,
            label: 'Gear',
            color: context.colors.warning,
            value: modules.gear,
            onChanged: (v) =>
                onModulesChanged(modules.copyWith(gear: v)),
          ),
          _ModuleToggleRow(
            key: EventKeys.moduleLogisticsToggle,
            icon: Iconsax.car,
            label: 'Logistics',
            color: context.colors.textSecondary,
            value: modules.logistics,
            onChanged: (v) =>
                onModulesChanged(modules.copyWith(logistics: v)),
          ),
          _ModuleToggleRow(
            key: EventKeys.moduleVaultToggle,
            icon: Iconsax.folder,
            label: 'Vault',
            color: context.colors.textSecondary,
            value: modules.vault,
            onChanged: (v) =>
                onModulesChanged(modules.copyWith(vault: v)),
          ),
          _ModuleToggleRow(
            key: EventKeys.moduleMemoriesToggle,
            icon: Iconsax.image,
            label: 'Memories',
            color: context.colors.primary,
            value: modules.memories,
            onChanged: (v) =>
                onModulesChanged(modules.copyWith(memories: v)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private module toggle row
// ---------------------------------------------------------------------------

/// A single module toggle row for Custom event type (D-14).
///
/// Moved from [CreateEventScreen] (Phase 36 ARCH-01 decomposition).
class _ModuleToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ModuleToggleRow({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Switch(
            value: value,
            thumbColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? context.colors.primary
                  : null,
            ),
            trackColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? context.colors.primary.withValues(alpha: 0.3)
                  : null,
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
