import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../shared/animations/tap_bounce.dart';
import '../models/event_model.dart';
import '../keys/event_keys.dart';
import '../models/event_type_config.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';

/// Full-screen event type picker — Step 1 of the event creation flow.
///
/// Displays 5 visual type cards (Trip, Camping, Travel, Night/Day Out, Custom).
/// Each card shows the type's icon, name, description, and enabled module chips.
/// Tapping a card navigates to [CreateEventScreen] with the selected type.
///
/// Per D-02 and UI-SPEC: EventTypePickerScreen.
class EventTypePickerScreen extends StatelessWidget {
  final String groupId;

  const EventTypePickerScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final types = EventTypeConfig.allTypes;

    return Scaffold(
      key: EventKeys.eventTypePickerScreen,
      backgroundColor: AppColorTokens.light.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Choose Event Type', key: EventKeys.eventTypePickerTitle),
        leading: CloseButton(
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: types.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final config = types[index];
          final enabledModuleNames = _enabledModuleNames(config.type);

          final card = Semantics(
            label:
                '${config.label}: ${config.description}. Modules: ${enabledModuleNames.join(", ")}',
            button: true,
            child: TapBounce(
              key: EventKeys.eventTypeCard(config.label),
              onTap: () => context.push(
                '/group/$groupId/create-event/${config.type.value}',
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColorTokens.light.cardSurface,
                  borderRadius:
                      BorderRadius.circular(16),
                  boxShadow: AppShadowTokens.standard.raised,
                ),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Type icon container
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: config.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        config.icon,
                        size: 24,
                        color: config.color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Text column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            config.label,
                            style:
                                Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            config.description,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppColorTokens.light.textMuted,
                                ),
                          ),
                          const SizedBox(height: 8),
                          // Module chips
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: enabledModuleNames
                                .map((name) => _ModuleChip(name: name))
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Trailing arrow
                    Icon(
                      Iconsax.arrow_right_3,
                      size: 18,
                      color: AppColorTokens.light.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          );

          if (disableAnimations) return card;

          return card
              .animate()
              .fadeIn(
                delay: (40 * index).ms,
                duration: 400.ms,
              )
              .slideY(
                begin: 0.05,
                end: 0,
                delay: (40 * index).ms,
                duration: 400.ms,
                curve: Curves.easeOutCubic,
              );
        },
      ),
    );
  }

  /// Returns the names of all enabled modules for the given event type.
  static List<String> _enabledModuleNames(EventType type) {
    final modules = EventModules.forType(type);
    return [
      if (modules.ledger) 'Ledger',
      if (modules.gear) 'Gear',
      if (modules.logistics) 'Logistics',
      if (modules.vault) 'Vault',
      if (modules.memories) 'Memories',
    ];
  }
}

/// Chip displaying a single module name in the type picker card.
class _ModuleChip extends StatelessWidget {
  final String name;

  const _ModuleChip({required this.name});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        name,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      backgroundColor: AppColorTokens.light.inputFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
    );
  }
}

