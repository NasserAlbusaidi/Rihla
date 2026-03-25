import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../gear/providers/gear_provider.dart';
import '../../trip/models/trip_model.dart';

/// Hero card showing trip countdown and gear preparation progress.
///
/// When gear module is disabled, shows a simpler countdown-only card.
/// When gear is enabled, shows a circular progress ring with gear stats.
class PreparationHero extends ConsumerWidget {
  final Trip trip;

  const PreparationHero({super.key, required this.trip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daysLeft = trip.daysUntilStart;
    final hasGear = trip.modules.gear;

    if (!hasGear) {
      return _buildSimpleCountdown(daysLeft);
    }

    return _buildFullPreparation(ref, daysLeft);
  }

  /// Simple countdown card when gear module is disabled.
  Widget _buildSimpleCountdown(int? daysLeft) {
    return Container(
      padding: const EdgeInsets.all(AppColors.space20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppColors.cardShadow,
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          // Countdown Circle
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.primaryGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _countdownValue(daysLeft),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                    letterSpacing: -1,
                  ),
                ),
                Text(
                  _countdownLabel,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: Colors.black87,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppColors.space20),
          // Trip status text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusLabel(daysLeft),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryDark,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _statusDescription(daysLeft),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Full preparation hero with gear progress ring and stats.
  Widget _buildFullPreparation(WidgetRef ref, int? daysLeft) {
    final gearAsync = ref.watch(tripGearProvider(trip.id));

    return Container(
      padding: const EdgeInsets.all(AppColors.space20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppColors.cardShadow,
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          // Circular Progress Ring
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: gearAsync.when(
                    data: (items) {
                      final total = items.length;
                      final claimed = items
                          .where((i) => i.assignedTo != null)
                          .length;
                      final percent = total > 0 ? claimed / total : 0.0;
                      return CircularProgressIndicator(
                        value: percent,
                        strokeWidth: 10,
                        backgroundColor: AppColors.surfaceLight,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.mint,
                        ),
                        strokeCap: StrokeCap.round,
                      );
                    },
                    loading: () => const CircularProgressIndicator(
                      strokeWidth: 10,
                      backgroundColor: AppColors.surfaceLight,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.mint),
                    ),
                    error: (error, stack) => const CircularProgressIndicator(
                      value: 0,
                      strokeWidth: 10,
                      backgroundColor: AppColors.surfaceLight,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _countdownValue(daysLeft),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        letterSpacing: -1,
                      ),
                    ),
                    Text(
                      _countdownLabel,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textMuted,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppColors.space24),
          // Preparation Stats
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TRIP PREP',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textSecondary,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: AppColors.space8),
                gearAsync.when(
                  data: (items) {
                    final total = items.length;
                    final packed = items.where((i) => i.isPacked).length;
                    final claimed = items
                        .where((i) => i.assignedTo != null)
                        .length;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _prepStatusRow(
                          '${(total > 0 ? (claimed / total * 100) : 0).toInt()}%',
                          'Gear Claimed',
                          AppColors.mint,
                        ),
                        const SizedBox(height: 6),
                        _prepStatusRow(
                          '$packed/$total',
                          'Items Packed',
                          AppColors.amber,
                        ),
                      ],
                    );
                  },
                  loading: () => const Text('Recalculating...'),
                  error: (_, __) => const Text('Status Error'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _countdownValue(int? daysLeft) {
    if (trip.isPast) return '${trip.totalDays ?? '\u2013'}';
    if (daysLeft != null && daysLeft > 0) return '$daysLeft';
    if (trip.isOngoing) return '${trip.daysIntoTrip ?? '\u2013'}';
    return '\u2013';
  }

  String get _countdownLabel {
    if (trip.isPast) return 'DAYS';
    if (trip.isOngoing) return 'DAY';
    return 'DAYS';
  }

  String _statusLabel(int? daysLeft) {
    if (trip.isPast) return 'TRIP COMPLETE';
    if (daysLeft != null && daysLeft > 0) return 'ADVENTURE AWAITS';
    if (trip.isOngoing) return 'NOW EXPLORING';
    return 'UP NEXT';
  }

  String _statusDescription(int? daysLeft) {
    if (trip.isPast) return 'What a journey!';
    if (daysLeft != null && daysLeft > 0) return 'Get ready for departure!';
    if (trip.isOngoing) return 'Enjoying the journey';
    return 'Planning your next adventure';
  }

  Widget _prepStatusRow(String value, String label, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppColors.space8),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }
}
