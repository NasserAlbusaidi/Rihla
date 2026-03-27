import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../groups/models/group_model.dart';
import '../../ledger/screens/add_expense_screen.dart';
import '../../ledger/screens/ledger_screen.dart';
import '../models/event_model.dart';
import '../models/event_type_config.dart';
import '../widgets/event_module_list.dart';
import 'event_expense_hero.dart';

/// Per-event hub (CommandCenter equivalent) for events.
///
/// Shows a dark header with the event name, type badge, and group name.
/// Renders module cards filtered by the event's [EventModules] configuration.
/// Uses EventRef-based providers — no Trip facade per D-17 removal in 04-05.
class EventCommandCenter extends ConsumerWidget {
  final Event event;
  final Group group;

  const EventCommandCenter({
    super.key,
    required this.event,
    required this.group,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventRef = (groupId: event.groupId, eventId: event.id);
    final config = EventTypeConfig.forType(event.type);

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          HapticService.medium();
          Navigator.of(context).push(
            AppPageRoute(
              builder: (_) => AddExpenseScreen(
                groupId: event.groupId,
                eventId: event.id,
              ),
            ),
          );
        },
        backgroundColor: AppColors.primary,
        shape: const CircleBorder(),
        child: const Icon(Iconsax.add, color: Colors.black),
      ),
      body: Column(
        children: [
          ModuleHeader(
            title: event.name,
            // Middle dot U+00B7 between type label and group name
            subtitle: '${config.label} \u00B7 ${group.name}',
            actions: [
              Semantics(
                label: 'Event options',
                button: true,
                child: IconButton(
                  icon: const Icon(
                    Iconsax.more_circle,
                    color: Colors.white,
                    size: 22,
                  ),
                  onPressed: () {
                    // TODO(Phase 3+): Event options menu (edit name/dates, delete)
                  },
                ),
              ),
            ],
            useDarkTheme: true,
          ),
          const OfflineBanner(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppColors.space24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppColors.space20),
                  EventExpenseHero(
                    event: event,
                    onTap: () => Navigator.of(context).push(
                      AppPageRoute(
                        builder: (_) => LedgerScreen(
                          event: event,
                          group: group,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppColors.space24),
                  EventModuleList(event: event, group: group, eventRef: eventRef),
                  const SizedBox(height: AppColors.space32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
