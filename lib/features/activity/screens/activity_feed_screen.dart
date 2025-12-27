import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../trip/models/trip_model.dart';
import '../services/activity_service.dart';
import '../widgets/timeline_card.dart';

class ActivityFeedScreen extends ConsumerWidget {
  final Trip trip;

  const ActivityFeedScreen({super.key, required this.trip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch activity log stream
    final activityAsync = ref.watch(tripActivityProvider(trip.id));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Timeline & Audit'),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => context.pop(),
        ),
      ),
      body: activityAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (logs) {
          if (logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'No activity yet',
                    style: TextStyle(color: Colors.grey[500], fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              return TimelineCard(log: log, isLast: index == logs.length - 1);
            },
          );
        },
      ),
    );
  }
}
