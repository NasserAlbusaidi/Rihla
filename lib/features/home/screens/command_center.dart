import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:decimal/decimal.dart';
import '../../../core/services/haptic_service.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../gear/screens/gear_screen.dart';
import '../../ledger/screens/add_expense_screen.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/screens/ledger_screen.dart';
import '../../logistics/screens/logistics_screen.dart';
import '../../logistics/providers/sub_group_provider.dart';
import '../../gear/providers/gear_provider.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../trip/models/trip_model.dart';
import '../../trip/providers/trip_provider.dart';
import '../../trip/screens/edit_trip_screen.dart';
import '../../trip/screens/manage_members_screen.dart';
import '../../trip/services/trip_export_service.dart';
import '../../vault/screens/vault_screen.dart';
import '../../activity/screens/activity_feed_screen.dart';

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
            child: const Icon(Iconsax.add, color: Colors.white),
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
      padding: const EdgeInsets.all(24),
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

          const SizedBox(height: 24),

          Text(
            'No Trips Yet',
            style: Theme.of(context).textTheme.headlineMedium,
          ).animate().fadeIn(delay: 200.ms),

          const SizedBox(height: 8),

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

          const SizedBox(height: 16),

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
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero Section (Preparation Meter)
                _buildPreparationHero(
                  context,
                  ref,
                  trip,
                ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),

                const SizedBox(height: 20),

                // Expense Summary Hero - Most Important Feature
                _buildExpenseSummaryHero(
                  context,
                  ref,
                  trip,
                ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),

                const SizedBox(height: 24),

                // Module Cards
                _buildModuleGrid(context, trip),

                const SizedBox(height: 100), // Space for FAB
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreparationHero(BuildContext context, WidgetRef ref, Trip trip) {
    final gearAsync = ref.watch(tripGearProvider(trip.id));
    final daysLeft = trip.daysUntilStart;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          // Circular Progress Ring
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 70,
                height: 70,
                child: gearAsync.when(
                  data: (items) {
                    final total = items.length;
                    final claimed = items
                        .where((i) => i.assignedTo != null)
                        .length;
                    final percent = total > 0 ? claimed / total : 0.0;
                    return CircularProgressIndicator(
                      value: percent,
                      strokeWidth: 8,
                      backgroundColor: AppColors.surfaceLight,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.mint,
                      ),
                      strokeCap: StrokeCap.round,
                    );
                  },
                  loading: () => const CircularProgressIndicator(
                    strokeWidth: 8,
                    backgroundColor: AppColors.surfaceLight,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.mint),
                  ),
                  error: (error, stack) => const CircularProgressIndicator(
                    value: 0,
                    strokeWidth: 8,
                    backgroundColor: AppColors.surfaceLight,
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    daysLeft != null && daysLeft > 0 ? '$daysLeft' : '–',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'DAYS',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 16),
          // Preparation Stats
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Preparation Status',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
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
                        const SizedBox(height: 4),
                        _prepStatusRow(
                          '$packed/$total',
                          'Items Packed',
                          AppColors.amber,
                        ),
                      ],
                    );
                  },
                  loading: () => const Text('Loading...'),
                  error: (_, __) => const Text('Error loading status'),
                ),
              ],
            ),
          ),
        ],
      ),
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.surfaceLight, width: 1),
          boxShadow: AppColors.cardShadow,
        ),
        child: expensesAsync.when(
          data: (expenses) {
            // Calculate total expenses
            Decimal totalExpenses = Decimal.zero;
            for (final e in expenses) {
              totalExpenses = totalExpenses + e.amount;
            }

            // Get user balance
            final userBalance = balancesAsync.maybeWhen(
              data: (balances) => balances.cast<UserBalance?>().firstWhere(
                (b) => b?.participantId == currentParticipant?.id,
                orElse: () => null,
              ),
              orElse: () => null,
            );
            final net = userBalance?.netBalance ?? Decimal.zero;
            final isOwed = net > Decimal.zero;
            final owes = net < Decimal.zero;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Iconsax.wallet_3,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Expenses',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (net != Decimal.zero)
                          Text(
                            isOwed
                                ? 'You are owed ${net.toStringAsFixed(2)}'
                                : 'You owe ${net.abs().toStringAsFixed(2)}',
                            style: TextStyle(
                              color: isOwed ? AppColors.emerald : AppColors.rose,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    const Icon(
                      Iconsax.arrow_right_3,
                      color: AppColors.textMuted,
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Total Expenses - Big Number
                Text(
                  '${totalExpenses.toStringAsFixed(2)} OMR',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(),
          ),
          error: (_, __) => const Text(
            'Unable to load expenses',
            style: TextStyle(color: AppColors.textMuted),
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
        const SizedBox(width: 8),
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

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    Trip trip,
    List<Trip> allTrips,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 20, 20),
      color: Colors.transparent,
      child: Row(
        children: [
          // Back Button
          IconButton(
            icon: const Icon(Iconsax.arrow_left),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Back to trips',
          ),

          // Trip Info + Copyable Code
          Expanded(
            child: GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: trip.inviteCode));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invite code copied to clipboard'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          trip.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Iconsax.copy,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'CODE: ${trip.inviteCode}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.mint,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Member Avatar Stack
          _buildMemberStack(ref, trip),

          const SizedBox(width: 12),

          // More Menu
          _buildMoreMenu(context, ref, trip),
        ],
      ),
    );
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

  Widget _buildMoreMenu(BuildContext context, WidgetRef ref, Trip trip) {
    return PopupMenuButton<String>(
      icon: const Icon(Iconsax.more, color: AppColors.textSecondary),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onSelected: (value) {
        if (value == 'signout') {
          ref.read(authServiceProvider).signOut();
        } else if (value == 'create') {
          context.push('/create-trip');
        } else if (value == 'settings') {
          context.push('/settings');
        } else if (value == 'delete') {
          _showDeleteConfirmation(context, ref, trip);
        } else if (value == 'edit') {
          _openEditTrip(context, trip);
        } else if (value == 'members') {
          _openManageMembers(context, trip);
        } else if (value == 'timeline') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ActivityFeedScreen(trip: trip),
            ),
          );
        } else if (value == 'export_pdf') {
          _exportPDF(context, ref, trip);
        } else if (value == 'export_csv') {
          _exportCSV(context, ref, trip);
        }
      },
      itemBuilder: (context) => [
        if (trip.leaderId == ref.read(currentUserProvider)?.id)
          const PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Iconsax.edit_2, size: 20, color: AppColors.primary),
                SizedBox(width: 12),
                Text('Edit Trip'),
              ],
            ),
          ),
        if (trip.leaderId == ref.read(currentUserProvider)?.id)
          const PopupMenuItem(
            value: 'members',
            child: Row(
              children: [
                Icon(Iconsax.people, size: 20, color: AppColors.primary),
                SizedBox(width: 12),
                Text('Manage Members'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'create',
          child: Row(
            children: [
              Icon(Iconsax.add_circle, size: 20, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Create Trip'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'settings',
          child: Row(
            children: [
              Icon(Iconsax.setting_2, size: 20, color: AppColors.textSecondary),
              SizedBox(width: 12),
              Text('Settings'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'timeline',
          child: Row(
            children: [
              Icon(Iconsax.clock, size: 20, color: AppColors.textSecondary),
              SizedBox(width: 12),
              Text('Activity Log'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'export_pdf',
          child: Row(
            children: [
              Icon(
                Iconsax.document_download,
                size: 20,
                color: AppColors.primary,
              ),
              SizedBox(width: 12),
              Text('Export PDF'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'export_csv',
          child: Row(
            children: [
              Icon(Iconsax.document_text, size: 20, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Export CSV'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (trip.leaderId == ref.read(currentUserProvider)?.id)
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Iconsax.trash, size: 20, color: AppColors.error),
                SizedBox(width: 12),
                Text('Delete Trip', style: TextStyle(color: AppColors.error)),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'signout',
          child: Row(
            children: [
              Icon(Iconsax.logout, size: 20, color: AppColors.error),
              SizedBox(width: 12),
              Text('Sign Out', style: TextStyle(color: AppColors.error)),
            ],
          ),
        ),
      ],
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
            const SizedBox(width: 12),
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

  Future<void> _exportPDF(
    BuildContext context,
    WidgetRef ref,
    Trip trip,
  ) async {
    ScaffoldMessenger.of(context).showSnackBar(
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
            SizedBox(width: 12),
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
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _exportCSV(
    BuildContext context,
    WidgetRef ref,
    Trip trip,
  ) async {
    ScaffoldMessenger.of(context).showSnackBar(
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
            SizedBox(width: 12),
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
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _buildModuleGrid(BuildContext context, Trip trip) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        // Vault (Docs module)
        if (trip.modules.docs)
          _ModuleTile(
            icon: Iconsax.document_text,
            title: 'Vault',
            subtitle: 'Docs & Tickets',
            color: AppColors.indigo,
            onTap: () => _openVault(context, trip),
          ),

        // Gear
        if (trip.modules.gear)
          Consumer(
            builder: (context, ref, child) {
              final gearAsync = ref.watch(tripGearProvider(trip.id));
              final hasMissing = gearAsync.maybeWhen(
                data: (items) => items.any((i) => i.assignedTo == null),
                orElse: () => false,
              );
              return _ModuleTile(
                icon: Iconsax.bag_2,
                title: 'Gear',
                subtitle: hasMissing ? 'Items Missing' : 'All Ready',
                color: hasMissing ? AppColors.amber : AppColors.accentSecondary,
                isPulsing: hasMissing,
                onTap: () => _openGear(context, trip),
              );
            },
          ),

        // Ledger - always shown (expenses are core functionality)
        Consumer(
          builder: (context, ref, child) {
            final balancesAsync = ref.watch(tripBalancesProvider(trip.id));
            final currentParticipant = ref.watch(
              currentParticipantProvider(trip.id),
            );
            return balancesAsync.maybeWhen(
              data: (balances) {
                final userBalance = balances.cast<UserBalance?>().firstWhere(
                  (b) => b?.participantId == currentParticipant?.id,
                  orElse: () => null,
                );
                final net = userBalance?.netBalance ?? Decimal.zero;
                final isDebt = net < Decimal.zero;
                final isOwed = net > Decimal.zero;

                return _ModuleTile(
                  icon: Iconsax.wallet_3,
                  title: 'Ledger',
                  subtitle: net == Decimal.zero
                      ? 'No Balance'
                      : isDebt
                      ? 'You owe ${net.abs().toStringAsFixed(2)}'
                      : 'Owed ${net.toStringAsFixed(2)}',
                  color: isDebt
                      ? AppColors.rose
                      : (isOwed
                            ? AppColors.emerald
                            : AppColors.accentSecondary),
                  onTap: () => _openLedger(context, trip),
                );
              },
              orElse: () => _ModuleTile(
                icon: Iconsax.wallet_3,
                title: 'Ledger',
                subtitle: 'Split Expenses',
                color: AppColors.accentSecondary,
                onTap: () => _openLedger(context, trip),
              ),
            );
          },
        ),

        // Logistics
        if (trip.modules.logistics)
          _ModuleTile(
            icon: Iconsax.car,
            title: 'Logistics',
            subtitle: 'Convoy & Rooms',
            color: AppColors.sky,
            onTap: () => _openLogistics(context, trip),
          ),
      ],
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isTimeout ? Iconsax.wifi_square : Iconsax.warning_2,
              size: 64,
              color: isTimeout ? AppColors.textMuted : AppColors.rose,
            ),
            const SizedBox(height: 16),
            Text(
              isTimeout ? 'Connection Timeout' : 'Oops!',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isTimeout
                  ? 'Unable to connect to the server. Please check your internet connection.'
                  : error,
              style: const TextStyle(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
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
                  horizontal: 24,
                  vertical: 12,
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
              const SizedBox(width: 8),
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
            const SizedBox(width: 8),
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

class _ModuleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool isPulsing;

  const _ModuleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.isPulsing = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget card = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: color.withValues(alpha: isPulsing ? 0.8 : 0.15),
            width: isPulsing ? 2.5 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isPulsing ? color : AppColors.textMuted,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    if (isPulsing) {
      card = card
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .shimmer(color: color.withValues(alpha: 0.2), duration: 1500.ms)
          .scale(
            begin: const Offset(1, 1),
            end: const Offset(1.02, 1.02),
            duration: 1000.ms,
            curve: Curves.easeInOut,
          );
    }

    return card;
  }
}
