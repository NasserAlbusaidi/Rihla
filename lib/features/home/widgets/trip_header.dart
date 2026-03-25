import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/app_metadata.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/page_transitions.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../logistics/providers/sub_group_provider.dart';
import '../../trip/models/trip_model.dart';
import '../../trip/providers/trip_provider.dart';
import '../../trip/screens/edit_trip_screen.dart';
import '../../trip/screens/manage_members_screen.dart';
import '../../trip/services/trip_export_service.dart';

/// Header bar with back button, trip name, member avatars, and popup menu.
class TripHeader extends ConsumerWidget {
  final Trip trip;

  const TripHeader({super.key, required this.trip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppColors.space24,
        AppColors.space12,
        AppColors.space12,
        AppColors.space20,
      ),
      child: Row(
        children: [
          // Back Button
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderLight),
              boxShadow: AppColors.cardShadow,
            ),
            child: Tooltip(
              message: 'Go back',
              child: IconButton(
                icon: const Icon(Iconsax.arrow_left_2, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
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
          _MemberStack(trip: trip),

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
        HapticService.lightClick();
        _openEditTrip(context, trip);
        break;
      case 'members':
        HapticService.lightClick();
        _openManageMembers(context, trip);
        break;
      case 'export_pdf':
        HapticService.medium();
        _exportPDF(context, ref, trip);
        break;
      case 'export_csv':
        HapticService.medium();
        _exportCSV(context, ref, trip);
        break;
      case 'delete':
        HapticService.warning();
        _showDeleteConfirmation(context, ref, trip);
        break;
    }
  }

  void _shareInviteCode(BuildContext context, Trip trip) {
    HapticService.lightClick();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppColors.space32,
          AppColors.space24,
          AppColors.space32,
          40,
        ),
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
              padding: const EdgeInsets.symmetric(
                horizontal: AppColors.space32,
                vertical: AppColors.space20,
              ),
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

  void _openEditTrip(BuildContext context, Trip trip) {
    Navigator.of(context).push(
      AppPageRoute(builder: (context) => EditTripScreen(trip: trip)),
    );
  }

  void _openManageMembers(BuildContext context, Trip trip) {
    Navigator.of(context).push(
      AppPageRoute(builder: (context) => ManageMembersScreen(trip: trip)),
    );
  }

  Future<void> _exportPDF(
    BuildContext context,
    WidgetRef ref,
    Trip trip,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
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
}

/// Overlapping avatar stack for trip members.
class _MemberStack extends ConsumerWidget {
  final Trip trip;

  const _MemberStack({required this.trip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
}
