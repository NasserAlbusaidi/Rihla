import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../groups/models/group_model.dart';
import '../../home/widgets/expense_summary_hero.dart';
import '../../ledger/screens/add_expense_screen.dart';
import '../../ledger/screens/ledger_screen.dart';
import '../../trip/models/trip_model.dart';
import '../models/event_model.dart';
import '../models/event_type_config.dart';
import '../widgets/event_module_list.dart';

/// Per-event hub (CommandCenter equivalent) for events.
///
/// Shows a dark header with the event name, type badge, and group name.
/// Renders module cards filtered by the event's [EventModules] configuration.
/// Uses a [Trip] facade built from [event.bridgeTripId] to pass the bridge
/// trip ID to existing module screens without modifying them.
///
/// Per Research Pattern 5 and D-17 to D-21.
class EventCommandCenter extends ConsumerWidget {
  final Event event;
  final Group group;

  const EventCommandCenter({
    super.key,
    required this.event,
    required this.group,
  });

  /// Builds a Trip facade from the event's bridge trip ID.
  ///
  /// This allows existing module screens (Ledger, Gear, Logistics, Vault,
  /// Memories) to function via the Supabase bridge without modification.
  /// The facade maps EventModules fields to TripModules fields.
  Trip _buildTripFacade() {
    return Trip(
      id: event.bridgeTripId,
      name: event.name,
      inviteCode: '',
      leaderId: event.createdBy,
      modules: TripModules(
        docs: event.modules.vault,
        gear: event.modules.gear,
        itinerary: false,
        logistics: event.modules.logistics,
      ),
      createdAt: event.createdAt,
      startDate: event.startDate,
      endDate: event.endDate,
      currency: event.currency,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = _buildTripFacade();
    final config = EventTypeConfig.forType(event.type);

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          HapticService.medium();
          Navigator.of(context).push(
            AppPageRoute(
              builder: (_) => AddExpenseScreen(tripId: trip.id),
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
                  ExpenseSummaryHero(
                    trip: trip,
                    onTap: () => Navigator.of(context).push(
                      AppPageRoute(builder: (_) => LedgerScreen(trip: trip)),
                    ),
                  ),
                  const SizedBox(height: AppColors.space24),
                  EventModuleList(event: event, trip: trip),
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
