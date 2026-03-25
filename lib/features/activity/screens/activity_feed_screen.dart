import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/error_widgets.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/module_header.dart';
import '../../trip/models/trip_model.dart';
import '../services/activity_service.dart';
import '../widgets/timeline_card.dart';

class ActivityFeedScreen extends ConsumerWidget {
  final Trip trip;

  const ActivityFeedScreen({super.key, required this.trip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(tripActivityProvider(trip.id));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          ModuleHeader(
            title: 'Activity',
            subtitle: trip.name.toUpperCase(),
          ),
          Expanded(
            child: activityAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => NetworkErrorWidget(
                onRetry: () => ref.invalidate(tripActivityProvider(trip.id)),
              ),
              data: (logs) {
                if (logs.isEmpty) return _buildEmptyState();

                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(tripActivityProvider(trip.id)),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(24),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      return TimelineCard(
                        log: log,
                        isLast: index == logs.length - 1,
                      )
                          .animate()
                          .fadeIn(delay: Duration(milliseconds: (50 * index).clamp(0, 500)), duration: 300.ms)
                          .slideY(begin: 0.05, end: 0, delay: Duration(milliseconds: (50 * index).clamp(0, 500)));
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return EmptyStateView(
      icon: Iconsax.activity,
      title: 'No activity yet',
      message: 'Actions from your trip will appear here',
      iconColor: AppColors.sky,
    );
  }
}
