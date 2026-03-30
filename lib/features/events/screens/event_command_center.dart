import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../groups/providers/group_provider.dart';
import '../keys/event_keys.dart';
import '../models/event_type_config.dart';
import '../providers/event_provider.dart';
import '../widgets/event_module_list.dart';
import 'event_expense_hero.dart';

/// Per-event hub (CommandCenter equivalent) for events.
///
/// Shows a dark header with the event name, type badge, and group name.
/// Renders module cards in a 2x3 grid filtered by the event's [EventModules].
/// Uses CustomScrollView + slivers per Phase 18 home dashboard pattern.
/// Uses string IDs + provider lookup per D-08, D-14.
class EventCommandCenter extends ConsumerWidget {
  final String groupId;
  final String eventId;

  const EventCommandCenter({
    super.key,
    required this.groupId,
    required this.eventId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(
      eventDetailProvider((groupId: groupId, eventId: eventId)),
    );
    final groupAsync = ref.watch(groupDetailProvider(groupId));

    // Loading state — skeleton instead of CircularProgressIndicator
    if (eventAsync.isLoading || groupAsync.isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            const ModuleHeader(title: 'Loading...', useDarkTheme: true),
            Expanded(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppColors.space24,
                  AppColors.space20,
                  AppColors.space24,
                  AppColors.space24,
                ),
                child: Column(
                  children: [
                    SkeletonLoader.dashboardHero(),
                    const SizedBox(height: AppColors.space24),
                    SkeletonLoader.cardList(count: 6),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final event = eventAsync.valueOrNull;
    final group = groupAsync.valueOrNull;

    // Not-found state per D-11
    if (event == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            const ModuleHeader(title: 'Not Found', useDarkTheme: true),
            Expanded(
              child: EmptyStateView(
                icon: Iconsax.warning_2,
                title: 'This event no longer exists',
                message:
                    'It may have been deleted. Tap below to go back to your groups.',
                actionLabel: 'Go Home',
                onAction: () => context.go('/home'),
                iconColor: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final config = EventTypeConfig.forType(event.type);

    return Scaffold(
      key: EventKeys.screen,
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton(
        key: EventKeys.addExpenseFab,
        onPressed: () {
          HapticService.medium();
          context.push('/group/$groupId/event/$eventId/ledger/add');
        },
        backgroundColor: AppColors.primary,
        shape: const CircleBorder(),
        child: const Icon(Iconsax.add, color: Colors.black),
      ),
      body: CustomScrollView(
        slivers: [
          // Dark header with event name, type, and group
          SliverToBoxAdapter(
            child: ModuleHeader(
              title: event.name,
              // Middle dot U+00B7 between type label and group name
              subtitle: '${config.label} \u00B7 ${group?.name ?? ''}',
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
          ),

          // Offline connectivity indicator
          const SliverToBoxAdapter(child: OfflineBanner()),

          // Expense hero card
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppColors.space24,
              AppColors.space20,
              AppColors.space24,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: EventExpenseHero(
                event: event,
                onTap: () =>
                    context.push('/group/$groupId/event/$eventId/ledger'),
              ),
            ),
          ),

          // Module grid
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppColors.space24,
              AppColors.space24,
              AppColors.space24,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: EventModuleList(
                groupId: groupId,
                eventId: eventId,
                modules: event.modules,
              ),
            ),
          ),

          // Bottom spacing
          const SliverToBoxAdapter(
            child: SizedBox(height: AppColors.space32),
          ),
        ],
      ),
    );
  }
}
