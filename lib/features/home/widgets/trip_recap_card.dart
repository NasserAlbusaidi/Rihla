import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../trip/models/trip_model.dart';
import '../../trip/providers/trip_provider.dart';

/// Summary card shown for completed trips, displaying duration,
/// expense count, and traveler count.
class TripRecapCard extends ConsumerWidget {
  final Trip trip;

  const TripRecapCard({super.key, required this.trip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(tripExpensesProvider(trip.id));
    final participantsAsync = ref.watch(
      tripLogisticsParticipantsProvider(trip.id),
    );

    return Container(
      padding: const EdgeInsets.all(AppColors.space20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppColors.cardShadow,
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppColors.space8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Iconsax.cup,
                  size: 18,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(width: AppColors.space12),
              const Text(
                'TRIP RECAP',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textSecondary,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppColors.space16),
          Row(
            children: [
              // Duration
              Expanded(
                child: _recapStat(
                  '${trip.totalDays ?? '\u2013'}',
                  'days',
                  Iconsax.calendar_1,
                ),
              ),
              // Expenses count
              Expanded(
                child: expensesAsync.when(
                  data: (expenses) => _recapStat(
                    '${expenses.length}',
                    'expenses',
                    Iconsax.receipt_item,
                  ),
                  loading: () =>
                      _recapStat('\u2013', 'expenses', Iconsax.receipt_item),
                  error: (_, __) =>
                      _recapStat('\u2013', 'expenses', Iconsax.receipt_item),
                ),
              ),
              // Members
              Expanded(
                child: participantsAsync.when(
                  data: (participants) => _recapStat(
                    '${participants.length}',
                    'travelers',
                    Iconsax.people,
                  ),
                  loading: () =>
                      _recapStat('\u2013', 'travelers', Iconsax.people),
                  error: (_, __) =>
                      _recapStat('\u2013', 'travelers', Iconsax.people),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _recapStat(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppColors.primaryDark),
        const SizedBox(height: AppColors.space8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
