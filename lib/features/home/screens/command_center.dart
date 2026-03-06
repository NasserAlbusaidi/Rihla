import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:decimal/decimal.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/config/app_metadata.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../gear/screens/gear_screen.dart';
import '../../ledger/screens/add_expense_screen.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/screens/ledger_screen.dart';
import '../../logistics/screens/logistics_screen.dart';
import '../../logistics/models/sub_group_model.dart';
import '../../logistics/providers/sub_group_provider.dart';
import '../../gear/providers/gear_provider.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../trip/models/trip_model.dart';
import '../../trip/providers/trip_provider.dart';
import '../../trip/screens/edit_trip_screen.dart';
import '../../trip/screens/manage_members_screen.dart';
import '../../trip/services/trip_export_service.dart';
import '../../vault/screens/vault_screen.dart';
import '../../vault/providers/document_provider.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../../shared/widgets/smart_module_card.dart';

/// Command Center - Main navigation hub for trips (Light theme)
class CommandCenter extends ConsumerWidget {
  const CommandCenter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(userTripsProvider);
    final currentTrip = ref.watch(currentTripProvider);

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
              : _buildTripView(context, ref, currentTrip ?? trips.first, trips),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _buildErrorState(context, ref, e.toString()),
        ),
      ),
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

  Widget _buildTripView(
    BuildContext context,
    WidgetRef ref,
    Trip trip,
    List<Trip> allTrips,
  ) {
    return Column(
      children: [
        _buildHeader(context, ref, trip, allTrips),
        const OfflineBanner(),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppColors.space24, 0, AppColors.space24, AppColors.space24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppColors.space8),

                // Hero Section (Preparation Meter)
                _buildPreparationHero(context, ref, trip)
                    .animate()
                    .fadeIn(duration: 600.ms)
                    .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),

                const SizedBox(height: AppColors.space16),

                // Expense Summary Hero
                _buildExpenseSummaryHero(context, ref, trip)
                    .animate()
                    .fadeIn(delay: 200.ms, duration: 600.ms)
                    .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),

                // Trip Recap for completed trips
                if (trip.isPast) ...[
                  const SizedBox(height: AppColors.space16),
                  _buildTripRecap(context, ref, trip)
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
                _buildModuleList(context, ref, trip),

                const SizedBox(height: 100), // Space for FAB
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreparationHero(BuildContext context, WidgetRef ref, Trip trip) {
    final daysLeft = trip.daysUntilStart;
    final hasGear = trip.modules.gear;

    // If gear module is disabled, show a simpler countdown card
    if (!hasGear) {
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
                    trip.isPast
                        ? '${trip.totalDays ?? '–'}'
                        : daysLeft != null && daysLeft > 0
                        ? '$daysLeft'
                        : trip.isOngoing
                            ? '${trip.daysIntoTrip ?? '–'}'
                            : '–',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                      letterSpacing: -1,
                    ),
                  ),
                  Text(
                    trip.isPast ? 'DAYS' : trip.isOngoing ? 'DAY' : 'DAYS',
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
                    trip.isPast
                        ? 'TRIP COMPLETE'
                        : daysLeft != null && daysLeft > 0
                        ? 'ADVENTURE AWAITS'
                        : trip.isOngoing
                        ? 'NOW EXPLORING'
                        : 'UP NEXT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primaryDark,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    trip.isPast
                        ? 'What a journey!'
                        : daysLeft != null && daysLeft > 0
                        ? 'Get ready for departure!'
                        : trip.isOngoing
                        ? 'Enjoying the journey'
                        : 'Planning your next adventure',
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

    // Full preparation hero with gear stats
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
          // Circular Progress Ring (Custom Gauge Look)
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
                      trip.isPast
                          ? '${trip.totalDays ?? '–'}'
                          : daysLeft != null && daysLeft > 0
                          ? '$daysLeft'
                          : trip.isOngoing
                              ? '${trip.daysIntoTrip ?? '–'}'
                              : '–',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        letterSpacing: -1,
                      ),
                    ),
                    Text(
                      trip.isPast ? 'DAYS' : trip.isOngoing ? 'DAY' : 'DAYS',
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

  /// Trip Recap card for completed trips
  Widget _buildTripRecap(BuildContext context, WidgetRef ref, Trip trip) {
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
                  '${trip.totalDays ?? '–'}',
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
                  loading: () => _recapStat('–', 'expenses', Iconsax.receipt_item),
                  error: (_, __) => _recapStat('–', 'expenses', Iconsax.receipt_item),
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
                  loading: () => _recapStat('–', 'travelers', Iconsax.people),
                  error: (_, __) => _recapStat('–', 'travelers', Iconsax.people),
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

  /// Expense Summary Hero - Shows total expenses prominently (core feature)
  Widget _buildExpenseSummaryHero(
    BuildContext context,
    WidgetRef ref,
    Trip trip,
  ) {
    final expensesAsync = ref.watch(tripExpensesProvider(trip.id));
    final balancesAsync = ref.watch(tripBalancesProvider(trip.id));
    final currentParticipant = ref.watch(currentParticipantProvider(trip.id));

    return GestureDetector(
      onTap: () => _openLedger(context, trip),
      child: Container(
        height: 130, // Increased slightly for better fit
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: SizedBox.expand(
            child: Stack(
              children: [
                // Abstract visual elements
                Positioned(
                  top: -30,
                  right: -30,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),

                expensesAsync.when(
                  data: (expenses) {
                    Decimal totalExpenses = Decimal.zero;
                    for (final e in expenses) {
                      totalExpenses = totalExpenses + e.amount;
                    }

                    final userBalance = balancesAsync.maybeWhen(
                      data: (balances) =>
                          balances.cast<UserBalance?>().firstWhere(
                            (b) => b?.participantId == currentParticipant?.id,
                            orElse: () => null,
                          ),
                      orElse: () => null,
                    );
                    final net = userBalance?.netBalance ?? Decimal.zero;
                    final isOwed = net > Decimal.zero;

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppColors.space24,
                        vertical: AppColors.space20, // Reduced from 24 to prevent overflow
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Iconsax.wallet_3,
                                      color: AppColors.mint,
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'SPENDING',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                              if (net != Decimal.zero)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        (isOwed
                                                ? AppColors.emerald
                                                : AppColors.rose)
                                            .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    isOwed ? 'OWED' : 'OWE',
                                    style: TextStyle(
                                      color: isOwed
                                          ? AppColors.mint
                                          : AppColors.rose,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                            ],
                          ),

                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TweenAnimationBuilder<double>(
                                      tween: Tween<double>(begin: 0, end: totalExpenses.toDouble()),
                                      duration: const Duration(milliseconds: 800),
                                      curve: Curves.easeOutCubic,
                                      builder: (context, value, child) {
                                        return Text(
                                          AppFormatters.formatCurrency(
                                            Decimal.parse(value.toStringAsFixed(3)),
                                            trip.currency,
                                          ),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 28,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -1,
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 2),
                                    if (net != Decimal.zero)
                                      TweenAnimationBuilder<double>(
                                        tween: Tween<double>(begin: 0, end: net.abs().toDouble()),
                                        duration: const Duration(milliseconds: 800),
                                        curve: Curves.easeOutCubic,
                                        builder: (context, value, child) {
                                          final formatted = AppFormatters.formatCurrency(
                                            Decimal.parse(value.toStringAsFixed(3)),
                                            trip.currency,
                                          );
                                          return Text(
                                            isOwed
                                                ? 'Settlements pending: +$formatted'
                                                : 'Pending payment: -$formatted',
                                            style: TextStyle(
                                              color: isOwed
                                                  ? AppColors.mint.withValues(alpha: 0.8)
                                                  : AppColors.rose.withValues(alpha: 0.8),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          );
                                        },
                                      )
                                    else
                                      const Text(
                                        'All balances settled',
                                        style: TextStyle(
                                          color: Colors.white38,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Iconsax.arrow_right_3,
                                color: Colors.white24,
                                size: 20,
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.mint),
                  ),
                  error: (_, __) => const Center(
                    child: Text(
                      'Could not load expenses',
                      style: TextStyle(
                        color: Colors.white38,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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

  IconData _getTripTypeIcon(String icon) {
    switch (icon) {
      case 'airplane': return Iconsax.airplane;
      case 'car': return Iconsax.car;
      case 'camping': return Iconsax.home_2;
      case 'hiking': return Iconsax.routing_2;
      case 'beach': return Iconsax.sun_1;
      case 'mountain': return Iconsax.cloud;
      case 'ship': return Iconsax.ship;
      case 'train': return Iconsax.bus;
      default: return Iconsax.airplane;
    }
  }

  String _getTripTypeLabel(String icon) {
    switch (icon) {
      case 'airplane': return 'Flight Trip';
      case 'car': return 'Road Trip';
      case 'camping': return 'Camping Trip';
      case 'hiking': return 'Hiking Adventure';
      case 'beach': return 'Beach Getaway';
      case 'mountain': return 'Mountain Escape';
      case 'ship': return 'Cruise';
      case 'train': return 'Train Journey';
      default: return 'Trip Dashboard';
    }
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    Trip trip,
    List<Trip> allTrips,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppColors.space24, AppColors.space12, AppColors.space12, AppColors.space20),
      child: Row(
        children: [
          // Back Button (Styled)
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderLight),
              boxShadow: AppColors.cardShadow,
            ),
            child: IconButton(
              icon: const Icon(Iconsax.arrow_left_2, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          const SizedBox(width: AppColors.space16),

          // Trip Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.name.toUpperCase(),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    fontSize: 20,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      _getTripTypeIcon(trip.icon),
                      size: 14,
                      color: AppColors.primaryDark,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _getTripTypeLabel(trip.icon),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Member Avatar Stack
          _buildMemberStack(ref, trip),

          const SizedBox(width: AppColors.space12),

          // Menu Button
          PopupMenuButton<String>(
            icon: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderLight),
                boxShadow: AppColors.cardShadow,
              ),
              child: const Icon(Iconsax.more, size: 20),
            ),
            offset: const Offset(0, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            onSelected: (value) =>
                _handleMoreSelection(context, ref, value, trip),
            itemBuilder: (context) => [
              _buildPopupMenuItem('Share Invite Code', Iconsax.share, 'share_code'),
              _buildPopupMenuItem('Edit Trip', Iconsax.edit_2, 'edit'),
              _buildPopupMenuItem('Members', Iconsax.user_tag, 'members'),
              _buildPopupMenuItem(
                'Export PDF',
                Iconsax.document_download,
                'export_pdf',
              ),
              _buildPopupMenuItem(
                'Export CSV',
                Iconsax.document_text,
                'export_csv',
              ),
              const PopupMenuDivider(),
              _buildPopupMenuItem(
                'Delete Trip',
                Iconsax.trash,
                'delete',
                isDestructive: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildPopupMenuItem(
    String title,
    IconData icon,
    String value, {
    bool isDestructive = false,
  }) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isDestructive ? AppColors.error : AppColors.textPrimary,
          ),
          const SizedBox(width: AppColors.space12),
          Text(
            title,
            style: TextStyle(
              color: isDestructive ? AppColors.error : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _handleMoreSelection(
    BuildContext context,
    WidgetRef ref,
    String value,
    Trip trip,
  ) {
    switch (value) {
      case 'share_code':
        _shareInviteCode(context, trip);
        break;
      case 'edit':
        _openEditTrip(context, trip);
        break;
      case 'members':
        _openManageMembers(context, trip);
        break;
      case 'export_pdf':
        _exportPDF(context, ref, trip);
        break;
      case 'export_csv':
        _exportCSV(context, ref, trip);
        break;
      case 'delete':
        _showDeleteConfirmation(context, ref, trip);
        break;
    }
  }

  Widget _buildMemberStack(WidgetRef ref, Trip trip) {
    final participantsAsync = ref.watch(
      tripLogisticsParticipantsProvider(trip.id),
    );

    return participantsAsync.when(
      data: (members) {
        final displayCount = 3;
        final topMembers = members.take(displayCount).toList();
        final extraCount = members.length - topMembers.length;

        return Row(
          children: [
            SizedBox(
              width: (topMembers.length * 24.0) + (extraCount > 0 ? 32.0 : 0.0),
              height: 32,
              child: Stack(
                children: [
                  for (int i = 0; i < topMembers.length; i++)
                    Positioned(
                      left: i * 22.0,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: AppColors.surfaceLight,
                          backgroundImage:
                              topMembers[i].avatarUrl != null &&
                                  topMembers[i].avatarUrl!.startsWith('http')
                              ? NetworkImage(topMembers[i].avatarUrl!)
                              : null,
                          child:
                              topMembers[i].avatarUrl == null ||
                                  !topMembers[i].avatarUrl!.startsWith('http')
                              ? Text(
                                  topMembers[i].displayName?[0].toUpperCase() ??
                                      '?',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  if (extraCount > 0)
                    Positioned(
                      left: topMembers.length * 22.0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            '+$extraCount',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  void _showDeleteConfirmation(BuildContext context, WidgetRef ref, Trip trip) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Iconsax.trash, color: AppColors.error),
            ),
            const SizedBox(width: AppColors.space12),
            const Text('Delete Trip?'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${trip.name}"?\n\nThis will remove all expenses, gear, and documents. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await ref
                  .read(tripServiceProvider)
                  .deleteTrip(trip.id);
              if (success) {
                ref.invalidate(userTripsProvider);
                if (context.mounted) {
                  context.go('/home');
                }
              }
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  void _openEditTrip(BuildContext context, Trip trip) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => EditTripScreen(trip: trip)));
  }

  void _openManageMembers(BuildContext context, Trip trip) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => ManageMembersScreen(trip: trip)),
    );
  }

  /// Show date range picker for exports. Returns null if cancelled.
  Future<DateTimeRange?> _pickExportDateRange(BuildContext context, Trip trip) async {
    return showDateRangePicker(
      context: context,
      firstDate: trip.startDate ?? DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: trip.startDate != null
          ? DateTimeRange(start: trip.startDate!, end: DateTime.now())
          : null,
      helpText: 'Select date range for export',
    );
  }

  Future<void> _exportPDF(
    BuildContext context,
    WidgetRef ref,
    Trip trip,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    // Optional date range filter
    final dateRange = await _pickExportDateRange(context, trip);
    // null means user cancelled the picker — proceed with all data
    // If user selects a range, use it to filter
    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: AppColors.space12),
            Text('Generating PDF...'),
          ],
        ),
        duration: Duration(seconds: 10),
      ),
    );

    try {
      final expenses = await ref.read(tripExpensesProvider(trip.id).future);
      final settlements = await ref.read(
        tripSettlementsProvider(trip.id).future,
      );
      final participants = await ref.read(
        tripLogisticsParticipantsProvider(trip.id).future,
      );
      final subGroups = await ref.read(tripSubGroupsProvider(trip.id).future);

      await TripExportService.exportAndSharePDF(
        trip: trip,
        expenses: expenses,
        settlements: settlements,
        participants: participants,
        subGroups: subGroups,
        startDate: dateRange?.start,
        endDate: dateRange?.end,
      );

      messenger.hideCurrentSnackBar();
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _exportCSV(
    BuildContext context,
    WidgetRef ref,
    Trip trip,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final dateRange = await _pickExportDateRange(context, trip);
    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: AppColors.space12),
            Text('Generating CSV...'),
          ],
        ),
        duration: Duration(seconds: 10),
      ),
    );

    try {
      final expenses = await ref.read(tripExpensesProvider(trip.id).future);
      final participants = await ref.read(
        tripLogisticsParticipantsProvider(trip.id).future,
      );

      await TripExportService.exportAndShareCSV(
        trip: trip,
        expenses: expenses,
        participants: participants,
        startDate: dateRange?.start,
        endDate: dateRange?.end,
      );

      messenger.hideCurrentSnackBar();
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _buildModuleList(BuildContext context, WidgetRef ref, Trip trip) {
    return Consumer(
      builder: (context, ref, child) {
        // Gather data for all modules
        final expensesAsync = ref.watch(tripExpensesProvider(trip.id));
        final balancesAsync = ref.watch(tripBalancesProvider(trip.id));
        final currentParticipant = ref.watch(currentParticipantProvider(trip.id));
        final gearAsync = trip.modules.gear
            ? ref.watch(tripGearProvider(trip.id))
            : null;
        final subGroupsAsync = trip.modules.logistics
            ? ref.watch(tripSubGroupsProvider(trip.id))
            : null;
        final docsAsync = trip.modules.docs
            ? ref.watch(tripDocumentsProvider(trip.id))
            : null;

        // Build module card configs with priorities
        final cards = <_ModuleCardConfig>[];

        // --- Ledger (always shown) ---
        final expenses = expensesAsync.valueOrNull ?? [];
        final balances = balancesAsync.valueOrNull;
        final userBalance = balances?.cast<UserBalance?>().firstWhere(
          (b) => b?.participantId == currentParticipant?.id,
          orElse: () => null,
        );
        final net = userBalance?.netBalance ?? Decimal.zero;
        final isDebt = net < Decimal.zero;
        final isOwed = net > Decimal.zero;

        String? ledgerSummary;
        String? ledgerAction;
        int ledgerPriority = 10;
        bool ledgerEmpty = expenses.isEmpty;

        if (expenses.isNotEmpty) {
          final count = expenses.length;
          if (net == Decimal.zero) {
            ledgerSummary = '$count expense${count != 1 ? 's' : ''} · All settled';
            ledgerPriority = 50;
          } else if (isDebt) {
            ledgerAction = 'You owe ${AppFormatters.formatCurrency(net.abs(), trip.currency)}';
            ledgerPriority = 100;
          } else {
            ledgerAction = 'You are owed ${AppFormatters.formatCurrency(net, trip.currency)}';
            ledgerPriority = 90;
          }
        }

        cards.add(_ModuleCardConfig(
          icon: Iconsax.wallet_3,
          title: 'Ledger',
          description: 'Track shared expenses and split costs fairly',
          color: isDebt ? AppColors.rose : (isOwed ? AppColors.emerald : AppColors.accentSecondary),
          onTap: () => _openLedger(context, trip),
          summaryText: ledgerSummary,
          actionText: ledgerAction,
          priority: ledgerPriority,
          isEmpty: ledgerEmpty,
        ));

        // --- Gear ---
        if (trip.modules.gear) {
          final gearItems = gearAsync?.valueOrNull ?? [];
          final gearEmpty = gearItems.isEmpty;
          String? gearSummary;
          String? gearAction;
          int gearPriority = 10;

          if (gearItems.isNotEmpty) {
            final total = gearItems.length;
            final claimed = gearItems.where((i) => i.assignedTo != null).length;
            final packed = gearItems.where((i) => i.isPacked).length;
            final unclaimed = total - claimed;

            if (unclaimed > 0) {
              gearAction = '$unclaimed item${unclaimed != 1 ? 's' : ''} still need someone';
              gearPriority = 80;
            } else {
              gearSummary = '$total items · $packed packed';
              gearPriority = 50;
            }
          }

          cards.add(_ModuleCardConfig(
            icon: Iconsax.bag_2,
            title: 'Gear',
            description: 'Create a shared packing list and claim items',
            color: (gearAction != null) ? AppColors.amber : AppColors.accentSecondary,
            onTap: () => _openGear(context, trip),
            summaryText: gearSummary,
            actionText: gearAction,
            priority: gearPriority,
            isEmpty: gearEmpty,
          ));
        }

        // --- Logistics ---
        if (trip.modules.logistics) {
          final subGroups = subGroupsAsync?.valueOrNull ?? [];
          final logisticsEmpty = subGroups.isEmpty;
          String? logisticsSummary;
          int logisticsPriority = 10;

          if (subGroups.isNotEmpty) {
            final cars = subGroups.where((g) => g.type == SubGroupType.car).length;
            final rooms = subGroups.where((g) => g.type == SubGroupType.room).length;
            final parts = <String>[];
            if (cars > 0) parts.add('$cars car${cars != 1 ? 's' : ''}');
            if (rooms > 0) parts.add('$rooms room${rooms != 1 ? 's' : ''}');
            logisticsSummary = parts.join(' · ');
            logisticsPriority = 50;
          }

          cards.add(_ModuleCardConfig(
            icon: Iconsax.car,
            title: 'Logistics',
            description: 'Organize cars, rooms, and teams for your group',
            color: AppColors.sky,
            onTap: () => _openLogistics(context, trip),
            summaryText: logisticsSummary,
            priority: logisticsPriority,
            isEmpty: logisticsEmpty,
          ));
        }

        // --- Vault ---
        if (trip.modules.docs) {
          final docs = docsAsync?.valueOrNull ?? [];
          final vaultEmpty = docs.isEmpty;
          String? vaultSummary;
          int vaultPriority = 10;

          if (docs.isNotEmpty) {
            vaultSummary = '${docs.length} document${docs.length != 1 ? 's' : ''} uploaded';
            vaultPriority = 50;
          }

          cards.add(_ModuleCardConfig(
            icon: Iconsax.document_text,
            title: 'Vault',
            description: 'Store tickets, permits, and trip documents',
            color: AppColors.indigo,
            onTap: () => _openVault(context, trip),
            summaryText: vaultSummary,
            priority: vaultPriority,
            isEmpty: vaultEmpty,
          ));
        }

        // Sort by priority (highest first)
        cards.sort((a, b) => b.priority.compareTo(a.priority));

        return Column(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              SmartModuleCard(
                icon: cards[i].icon,
                title: cards[i].title,
                description: cards[i].description,
                color: cards[i].color,
                onTap: cards[i].onTap,
                summaryText: cards[i].summaryText,
                actionText: cards[i].actionText,
                priority: cards[i].priority,
                isEmpty: cards[i].isEmpty,
              )
                  .animate()
                  .fadeIn(delay: (100 * i).ms, duration: 400.ms)
                  .slideY(begin: 0.1, end: 0, delay: (100 * i).ms, duration: 400.ms),
            ],
          ],
        );
      },
    );
  }

  void _shareInviteCode(BuildContext context, Trip trip) {
    HapticService.lightClick();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppColors.space32, AppColors.space24, AppColors.space32, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppColors.space24),
            const Text(
              'INVITE CODE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Invite Friends',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: AppColors.space8),
            const Text(
              'Share this code with anyone you want to join',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppColors.space24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppColors.space32, vertical: AppColors.space20),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              child: Text(
                trip.inviteCode,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 8,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            const SizedBox(height: AppColors.space24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(
                      text:
                          'Join my trip "${trip.name}" on ${AppMetadata.visibleAppName}! Code: ${trip.inviteCode}',
                    ),
                  );
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Row(
                        children: [
                          Icon(Iconsax.tick_circle, color: Colors.white, size: 18),
                          SizedBox(width: AppColors.space8),
                          Text('Invite copied to clipboard!'),
                        ],
                      ),
                      backgroundColor: AppColors.primary,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Iconsax.copy),
                label: const Text('Copy Invite'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openLedger(BuildContext context, Trip trip) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => LedgerScreen(trip: trip)));
  }

  void _openAddExpense(BuildContext context, Trip trip) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddExpenseScreen(tripId: trip.id),
      ),
    );
  }

  void _openGear(BuildContext context, Trip trip) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => GearScreen(trip: trip)));
  }

  void _openLogistics(BuildContext context, Trip trip) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => LogisticsScreen(trip: trip)),
    );
  }

  void _openVault(BuildContext context, Trip trip) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => VaultScreen(trip: trip)));
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
}

/// Internal config for building module cards with priority sorting.
class _ModuleCardConfig {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;
  final String? summaryText;
  final String? actionText;
  final int priority;
  final bool isEmpty;

  const _ModuleCardConfig({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
    this.summaryText,
    this.actionText,
    this.priority = 10,
    this.isEmpty = true,
  });
}
