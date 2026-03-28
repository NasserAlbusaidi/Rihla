import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/page_transitions.dart';
import '../models/event_model.dart';
import '../keys/event_keys.dart';
import '../models/event_type_config.dart';
import 'create_event_screen.dart';

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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Choose Event Type'),
        leading: CloseButton(
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppColors.space24),
        itemCount: types.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: AppColors.space12),
        itemBuilder: (context, index) {
          final config = types[index];
          final enabledModuleNames = _enabledModuleNames(config.type);

          final card = Semantics(
            label:
                '${config.label}: ${config.description}. Modules: ${enabledModuleNames.join(", ")}',
            button: true,
            child: _PressableCard(
              onTap: () => Navigator.of(context).push(
                AppPageRoute(
                  builder: (_) => CreateEventScreen(
                    groupId: groupId,
                    eventType: config.type,
                  ),
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius:
                      BorderRadius.circular(AppColors.radiusLarge),
                  boxShadow: AppColors.shadowRaised,
                ),
                padding: const EdgeInsets.all(AppColors.space16),
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
                    const SizedBox(width: AppColors.space12),
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
                          const SizedBox(height: AppColors.space4),
                          Text(
                            config.description,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppColors.textMuted,
                                ),
                          ),
                          const SizedBox(height: AppColors.space8),
                          // Module chips
                          Wrap(
                            spacing: AppColors.space4,
                            runSpacing: AppColors.space4,
                            children: enabledModuleNames
                                .map((name) => _ModuleChip(name: name))
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppColors.space8),
                    // Trailing arrow
                    const Icon(
                      Iconsax.arrow_right_3,
                      size: 18,
                      color: AppColors.textMuted,
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
      backgroundColor: AppColors.surfaceLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusSmall),
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
    );
  }
}

/// Wraps a child with a 0.98 scale-down animation on press.
///
/// Mirrors the [_PressableWrapper] pattern from [SmartModuleCard].
class _PressableCard extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;

  const _PressableCard({required this.onTap, required this.child});

  @override
  State<_PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<_PressableCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: widget.child,
      ),
    );
  }
}
