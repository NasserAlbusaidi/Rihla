import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/error_widgets.dart';
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
                      );
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Iconsax.timer_1,
                size: 32,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'NO ACTIVITY YET',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Updates will appear here as your group adds expenses, claims gear, and makes changes.',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
