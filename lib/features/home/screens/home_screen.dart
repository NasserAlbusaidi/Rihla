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

/// Home Screen - Shows all trips with Join/Create buttons (Modern Bento Layout)
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(userTripsProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background subtle pattern or gradient
          Positioned(
            top: -150,
            right: -150,
            child:
                Container(
                      width: 400,
                      height: 400,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 1.seconds)
                    .scale(
                      begin: const Offset(0.8, 0.8),
                      end: const Offset(1, 1),
                    ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Header
                _buildHeader(context, ref, user)
                    .animate()
                    .fadeIn(duration: 600.ms)
                    .slideY(begin: -0.1, end: 0, curve: Curves.easeOutCubic),

                // Content
                Expanded(
                  child: tripsAsync.when(
                    data: (trips) => RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(userTripsProvider);
                      },
                      color: AppColors.primary,
                      child: _buildContent(context, ref, trips),
                    ),
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: AppColors.primary,
                      ),
                    ),
                    error: (e, _) => _buildErrorWidget(context, ref, e),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget(BuildContext context, WidgetRef ref, Object error) {
    final isTimeout =
        error.toString().contains('timedOut') ||
        error.toString().contains('timeout');

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Icon(
                isTimeout ? Iconsax.wifi_square : Iconsax.warning_2,
                size: 48,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isTimeout ? 'Connection Lost' : 'Something went wrong',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              isTimeout
                  ? 'Unable to reach the mountains. Check your connection.'
                  : 'We hit a bump in the road. Let\'s try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(userTripsProvider),
              icon: const Icon(Iconsax.refresh, size: 20),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
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
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Row(
        children: [
          // Avatar with shadow and gradient
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.primaryGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'T',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Greeting
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AHALAN,',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  displayName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),

          // Settings Icon
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderLight),
              boxShadow: AppColors.cardShadow,
            ),
            child: IconButton(
              icon: const Icon(Iconsax.setting_2, size: 22),
              color: AppColors.textPrimary,
              onPressed: () => context.push('/settings'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, List<Trip> trips) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Action Buttons
          _buildActionButtons(
            context,
          ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0),

          const SizedBox(height: 40),

          // Section Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MY ADVENTURES',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${trips.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            ],
          ).animate().fadeIn(delay: 400.ms),

          const SizedBox(height: 20),

          // Trip Cards or Empty State
          if (trips.isEmpty)
            _buildEmptyTrips(context).animate().fadeIn(delay: 500.ms)
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: trips.length,
              itemBuilder: (context, index) {
                return _buildTripCard(context, ref, trips[index])
                    .animate()
                    .fadeIn(delay: Duration(milliseconds: 500 + (index * 100)))
                    .slideY(begin: 0.1, end: 0, curve: Curves.easeOutBack);
              },
            ),

          const SizedBox(height: 40),
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
              height: 140, // Height for a "bento top" box
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(Iconsax.add_circle, color: Colors.black, size: 36),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PLAN NEW',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        'Create Trip',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ],
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
              height: 140,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.borderLight, width: 2),
                boxShadow: AppColors.cardShadow,
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(Iconsax.login, color: AppColors.primary, size: 36),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ENTRY CODE',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        'Join Trip',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ],
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
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              shape: BoxShape.circle,
            ),
            child: Icon(Iconsax.map, size: 48, color: AppColors.textMuted),
          ),
          const SizedBox(height: 24),
          const Text(
            'No expeditions yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'The world is waiting. Create your first journey to start tracking.',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTripCard(BuildContext context, WidgetRef ref, Trip trip) {
    final daysLeft = trip.daysUntilStart;
    final isOngoing = trip.isOngoing;

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
        ref.read(currentTripProvider.notifier).state = trip;
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (context) => const CommandCenter()));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          children: [
            // Immersive Header Area
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight.withValues(alpha: 0.5),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Row(
                children: [
                  // Icon container with specialized color
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      getIconData(trip.icon),
                      color: Colors.black,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Info Column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            trip.inviteCode,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primaryDark,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Status Badge
                  _buildStatusBadge(daysLeft, isOngoing),
                ],
              ),
            ),

            // Details Row
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  // Dates Badge
                  if (trip.startDate != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Iconsax.calendar_1,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${DateFormat('MMM d').format(trip.startDate!)}${trip.endDate != null ? ' - ${DateFormat('MMM d').format(trip.endDate!)}' : ''}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const Spacer(),

                  // Action Link
                  const Text(
                    'OPEN',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primaryDark,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Iconsax.arrow_right_3,
                    size: 16,
                    color: AppColors.primaryDark,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(int? daysLeft, bool isOngoing) {
    Color color;
    String text;

    if (isOngoing) {
      color = AppColors.success;
      text = 'LIVE';
    } else if (daysLeft != null && daysLeft > 0) {
      color = AppColors.primary;
      text = '$daysLeft ${daysLeft == 1 ? 'DAY' : 'DAYS'}';
    } else if (daysLeft != null && daysLeft == 0) {
      color = AppColors.amber;
      text = 'TODAY';
    } else {
      color = AppColors.textMuted;
      text = 'PLANNING';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
