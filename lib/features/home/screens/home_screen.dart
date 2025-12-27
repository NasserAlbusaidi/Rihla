import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../trip/models/trip_model.dart';
import '../../trip/providers/trip_provider.dart';
import 'command_center.dart';

/// Home Screen - Shows all trips with Join/Create buttons
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(userTripsProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(
              context,
              ref,
              user,
            ).animate().fadeIn().slideY(begin: -0.2),

            // Content
            Expanded(
              child: tripsAsync.when(
                data: (trips) => _buildContent(context, ref, trips),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, dynamic user) {
    final email = user?.email ?? 'Traveler';
    final displayName = email.split('@').first;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'T',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Greeting
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back,',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),

          // Settings
          IconButton(
            icon: const Icon(Iconsax.setting_2),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, List<Trip> trips) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Action Buttons
          _buildActionButtons(
            context,
          ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),

          const SizedBox(height: 32),

          // Active Trips Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Your Trips',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '${trips.length} ${trips.length == 1 ? 'trip' : 'trips'}',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
              ),
            ],
          ).animate().fadeIn(delay: 200.ms),

          const SizedBox(height: 16),

          // Trip Cards or Empty State
          if (trips.isEmpty)
            _buildEmptyTrips(context).animate().fadeIn(delay: 300.ms)
          else
            ...trips.asMap().entries.map((entry) {
              final index = entry.key;
              final trip = entry.value;
              return _buildTripCard(context, ref, trip)
                  .animate()
                  .fadeIn(delay: Duration(milliseconds: 300 + (index * 100)))
                  .slideX(begin: 0.1);
            }),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        // Create Trip
        Expanded(
          child: GestureDetector(
            onTap: () => context.push('/create-trip'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Column(
                children: [
                  Icon(Iconsax.add_circle, color: Colors.white, size: 32),
                  SizedBox(height: 8),
                  Text(
                    'Create Trip',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(width: 16),

        // Join Trip
        Expanded(
          child: GestureDetector(
            onTap: () => context.push('/join-trip'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
                boxShadow: AppColors.cardShadow,
              ),
              child: Column(
                children: [
                  Icon(Iconsax.login, color: AppColors.primary, size: 32),
                  const SizedBox(height: 8),
                  const Text(
                    'Join Trip',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyTrips(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(Iconsax.map, size: 64, color: AppColors.textMuted),
          const SizedBox(height: 16),
          const Text(
            'No trips yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a new trip or join an existing one\nto start your adventure',
            style: TextStyle(fontSize: 14, color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTripCard(BuildContext context, WidgetRef ref, Trip trip) {
    final daysLeft = trip.daysUntilStart;
    final isOngoing = trip.isOngoing;

    // Helper to get icon from name
    IconData getIconData(String iconName) {
      switch (iconName) {
        case 'airplane':
          return Iconsax.airplane;
        case 'car':
          return Iconsax.car;
        case 'camping':
          return Iconsax.home_2;
        case 'hiking':
          return Iconsax.routing_2;
        case 'beach':
          return Iconsax.sun_1;
        case 'mountain':
          return Iconsax.cloud;
        case 'ship':
          return Iconsax.ship;
        case 'train':
          return Iconsax.bus;
        default:
          return Iconsax.airplane;
      }
    }

    return GestureDetector(
      onTap: () {
        // Set as current trip and navigate to command center
        ref.read(currentTripProvider.notifier).state = trip;
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (context) => const CommandCenter()));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          children: [
            // Header with gradient
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.1),
                    AppColors.primaryLight,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  // Trip Icon
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      getIconData(trip.icon),
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Trip Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Iconsax.ticket,
                              size: 14,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              trip.inviteCode,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Status Badge
                  if (daysLeft != null && daysLeft > 0)
                    _buildBadge('$daysLeft days', AppColors.primary)
                  else if (isOngoing)
                    _buildBadge('Ongoing', AppColors.success)
                  else
                    _buildBadge('Upcoming', AppColors.warning),
                ],
              ),
            ),

            // Details Row
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Dates
                  if (trip.startDate != null) ...[
                    Icon(
                      Iconsax.calendar_1,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${DateFormat('MMM d').format(trip.startDate!)}${trip.endDate != null ? ' - ${DateFormat('MMM d').format(trip.endDate!)}' : ''}',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],

                  const Spacer(),

                  // Arrow
                  Icon(
                    Iconsax.arrow_right_3,
                    size: 20,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
