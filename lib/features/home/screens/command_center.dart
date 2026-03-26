import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/providers/connectivity_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/page_transitions.dart';
import '../../ledger/screens/add_expense_screen.dart';
import '../../trip/models/trip_model.dart';
import '../../trip/providers/trip_provider.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../widgets/expense_summary_hero.dart';
import '../widgets/module_list.dart';
import '../widgets/preparation_hero.dart';
import '../widgets/trip_header.dart';
import '../widgets/trip_recap_card.dart';
import '../../ledger/screens/ledger_screen.dart';

/// @Deprecated('Supabase sync removed — Firestore handles offline persistence.')
/// Retained for backward compat with screens that watch it. No-op in 04-04+.
final _tripDataSeedProvider = FutureProvider.family<void, String>((ref, tripId) async {
  // No-op: Firestore offline persistence replaces Supabase downloadTripData.
});

/// Command Center - Main navigation hub for trips (Light theme)
class CommandCenter extends ConsumerWidget {
  const CommandCenter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(userTripsProvider);
    final currentTrip = ref.watch(currentTripProvider);

    // Eagerly download trip data on entry (runs once per trip via FutureProvider)
    final tripForSeed = currentTrip ?? ref.read(userTripsProvider).valueOrNull?.firstOrNull;
    if (tripForSeed != null) {
      ref.watch(_tripDataSeedProvider(tripForSeed.id));
    }

    // Re-download on connectivity restore
    ref.listen<ConnectivityStatus>(connectivityProvider, (prev, next) {
      if (prev == ConnectivityStatus.offline && next == ConnectivityStatus.online) {
        final trip = currentTrip ?? ref.read(userTripsProvider).valueOrNull?.firstOrNull;
        if (trip != null) {
          ref.invalidate(_tripDataSeedProvider(trip.id));
        }
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: tripsAsync.when(
        data: (trips) {
          if (trips.isEmpty) return null;
          final trip = currentTrip ?? trips.first;
          return FloatingActionButton(
            onPressed: () {
              HapticService.medium();
              _openAddExpense(context, trip);
            },
            backgroundColor: AppColors.primary,
            shape: const CircleBorder(),
            child: const Icon(Iconsax.add, color: Colors.black),
          );
        },
        loading: () => null,
        error: (_, __) => null,
      ),
      body: SafeArea(
        child: tripsAsync.when(
          data: (trips) => trips.isEmpty
              ? _buildEmptyState(context)
              : _buildTripView(context, ref, currentTrip ?? trips.first),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _buildErrorState(context, ref, e.toString()),
        ),
      ),
    );
  }

  Widget _buildTripView(BuildContext context, WidgetRef ref, Trip trip) {
    return Column(
      children: [
        TripHeader(trip: trip),
        const OfflineBanner(),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppColors.space24,
              0,
              AppColors.space24,
              AppColors.space24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppColors.space8),

                // Hero Section (Preparation Meter)
                PreparationHero(trip: trip)
                    .animate()
                    .fadeIn(duration: 600.ms)
                    .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),

                const SizedBox(height: AppColors.space16),

                // Expense Summary Hero
                ExpenseSummaryHero(
                  trip: trip,
                  onTap: () => _openLedger(context, trip),
                )
                    .animate()
                    .fadeIn(delay: 200.ms, duration: 600.ms)
                    .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),

                // Trip Recap for completed trips
                if (trip.isPast) ...[
                  const SizedBox(height: AppColors.space16),
                  TripRecapCard(trip: trip)
                      .animate()
                      .fadeIn(delay: 300.ms, duration: 600.ms)
                      .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
                ],

                const SizedBox(height: AppColors.space32),

                // Action Section Header
                Row(
                  children: [
                    Text(
                      'MODULES',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Iconsax.element_3,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                  ],
                ).animate().fadeIn(delay: 400.ms),

                const SizedBox(height: AppColors.space16),

                // Module Cards
                ModuleList(trip: trip),

                const SizedBox(height: 100), // Space for FAB
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppColors.space24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Icon(Iconsax.map, size: 48, color: AppColors.primary),
          ).animate().fadeIn().scale(delay: 100.ms),

          const SizedBox(height: AppColors.space24),

          Text(
            'No Trips Yet',
            style: Theme.of(context).textTheme.headlineMedium,
          ).animate().fadeIn(delay: 200.ms),

          const SizedBox(height: AppColors.space8),

          Text(
            'Create a new trip or join an existing one\nto start planning your adventure',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 300.ms),

          const SizedBox(height: 40),

          // Create Trip Button
          _buildPrimaryButton(
            context,
            icon: Iconsax.add_circle,
            label: 'Create Trip',
            onTap: () => context.push('/create-trip'),
          ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2),

          const SizedBox(height: AppColors.space16),

          // Join Trip Button
          _buildSecondaryButton(
            context,
            icon: Iconsax.login,
            label: 'Join Trip',
            onTap: () => context.push('/join-trip'),
          ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.2),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, WidgetRef ref, String error) {
    final isTimeout = error.contains('timedOut') || error.contains('timeout');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppColors.space24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isTimeout ? Iconsax.wifi_square : Iconsax.warning_2,
              size: 64,
              color: isTimeout ? AppColors.textMuted : AppColors.rose,
            ),
            const SizedBox(height: AppColors.space16),
            Text(
              isTimeout ? 'Connection Timeout' : 'Oops!',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppColors.space8),
            Text(
              isTimeout
                  ? 'Unable to connect to the server. Please check your internet connection.'
                  : error,
              style: const TextStyle(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppColors.space24),
            ElevatedButton.icon(
              onPressed: () {
                ref.invalidate(userTripsProvider);
              },
              icon: const Icon(Iconsax.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppColors.space24,
                  vertical: AppColors.space12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: AppColors.space8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(width: AppColors.space8),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openLedger(BuildContext context, Trip trip) {
    Navigator.of(context).push(
      AppPageRoute(builder: (context) => LedgerScreen(trip: trip)),
    );
  }

  void _openAddExpense(BuildContext context, Trip trip) {
    Navigator.of(context).push(
      AppPageRoute(
        builder: (context) => AddExpenseScreen(tripId: trip.id),
      ),
    );
  }
}
