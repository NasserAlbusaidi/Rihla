import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../trip/providers/trip_provider.dart';
import '../models/trip_model.dart';
import '../providers/shadow_provider.dart';
import '../../auth/providers/auth_provider.dart';

/// Manage Members Screen - Shadow profiles, merge, and vanish
class ManageMembersScreen extends ConsumerStatefulWidget {
  final Trip trip;

  const ManageMembersScreen({super.key, required this.trip});

  @override
  ConsumerState<ManageMembersScreen> createState() =>
      _ManageMembersScreenState();
}

class _ManageMembersScreenState extends ConsumerState<ManageMembersScreen> {
  @override
  Widget build(BuildContext context) {
    final participantsAsync = ref.watch(
      tripLogisticsParticipantsProvider(widget.trip.id),
    );
    final currentUser = ref.watch(currentUserProvider);
    final isLeader = currentUser?.id == widget.trip.leaderId;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: participantsAsync.when(
                data: (participants) =>
                    _buildParticipantsList(context, participants, isLeader),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: isLeader
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateShadowDialog(context),
              backgroundColor: AppColors.primary,
              icon: const Icon(Iconsax.user_add, color: Colors.white),
              label: const Text(
                'Add Shadow',
                style: TextStyle(color: Colors.white),
              ),
            )
          : null,
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Iconsax.arrow_left),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Text(
              'Manage Members',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildParticipantsList(
    BuildContext context,
    List<Participant> participants,
    bool isLeader,
  ) {
    final shadows = participants.where((p) => p.isShadow).toList();
    final real = participants.where((p) => !p.isShadow).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Real Members Section
          if (real.isNotEmpty) ...[
            _buildSectionTitle('Members', real.length),
            const SizedBox(height: 12),
            ...real.asMap().entries.map(
              (e) => _buildMemberCard(context, e.value, isLeader, e.key),
            ),
          ],

          if (shadows.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildSectionTitle(
              'Shadow Profiles',
              shadows.length,
              isShadow: true,
            ),
            const SizedBox(height: 12),
            ...shadows.asMap().entries.map(
              (e) => _buildShadowCard(context, e.value, isLeader, real, e.key),
            ),
          ],

          if (shadows.isEmpty && real.isEmpty)
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 60),
                  Icon(Iconsax.people, size: 64, color: AppColors.textMuted),
                  const SizedBox(height: 16),
                  Text(
                    'No members yet',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, int count, {bool isShadow = false}) {
    return Row(
      children: [
        Icon(
          isShadow ? Iconsax.ghost : Iconsax.people,
          size: 20,
          color: isShadow ? AppColors.warning : AppColors.primary,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isShadow
                ? AppColors.warning.withValues(alpha: 0.15)
                : AppColors.primaryLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isShadow ? AppColors.warning : AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMemberCard(
    BuildContext context,
    Participant member,
    bool isLeader,
    int index,
  ) {
    return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppColors.cardShadow,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primaryLight,
                child: Text(
                  (member.displayName ?? 'U')[0].toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.displayName ?? 'User',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      member.role.value,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (member.role == ParticipantRole.leader)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Leader',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        )
        .animate()
        .fadeIn(delay: Duration(milliseconds: 100 * index))
        .slideX(begin: 0.1);
  }

  Widget _buildShadowCard(
    BuildContext context,
    Participant shadow,
    bool isLeader,
    List<Participant> realUsers,
    int index,
  ) {
    return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.3),
              width: 1.5,
              strokeAlign: BorderSide.strokeAlignOutside,
            ),
            boxShadow: AppColors.cardShadow,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Ghost avatar
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Iconsax.ghost,
                      color: AppColors.warning,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              shadow.displayName ?? 'Shadow',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Shadow',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.warning,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Awaiting real user to join',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Actions for leader
              if (isLeader) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    // Merge button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: realUsers.isNotEmpty
                            ? () => _showMergeDialog(context, shadow, realUsers)
                            : null,
                        icon: const Icon(Iconsax.link, size: 18),
                        label: const Text('Merge'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Vanish button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showVanishDialog(context, shadow),
                        icon: const Icon(Iconsax.trash, size: 18),
                        label: const Text('Vanish'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: BorderSide(color: AppColors.error),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        )
        .animate()
        .fadeIn(delay: Duration(milliseconds: 100 * index))
        .slideX(begin: 0.1);
  }

  void _showCreateShadowDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Iconsax.ghost, color: AppColors.warning),
            const SizedBox(width: 12),
            const Text('Create Shadow'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Create a placeholder for someone who hasn\'t joined yet. You can assign expenses and car seats to them.',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Dad, Ahmed',
                prefixIcon: Icon(Iconsax.user),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              Navigator.pop(context);

              final service = ref.read(shadowServiceProvider);
              await service.createShadow(
                tripId: widget.trip.id,
                displayName: controller.text.trim(),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Create Shadow'),
          ),
        ],
      ),
    );
  }

  void _showMergeDialog(
    BuildContext context,
    Participant shadow,
    List<Participant> realUsers,
  ) {
    String? selectedUserId;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Iconsax.link, color: AppColors.primary),
              const SizedBox(width: 12),
              const Text('Merge Shadow'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Merge "${shadow.displayName}" with a real user. All expenses and assignments will transfer.',
              ),
              const SizedBox(height: 20),
              const Text(
                'Select Real User:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              ...realUsers.map(
                (user) => RadioListTile<String>(
                  value: user.userId!,
                  groupValue: selectedUserId,
                  onChanged: (v) => setDialogState(() => selectedUserId = v),
                  title: Text(user.displayName ?? 'User'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedUserId != null
                  ? () async {
                      Navigator.pop(context);
                      final service = ref.read(shadowServiceProvider);
                      await service.mergeParticipant(
                        shadowId: shadow.id,
                        realUserId: selectedUserId!,
                      );
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Merge'),
            ),
          ],
        ),
      ),
    );
  }

  void _showVanishDialog(BuildContext context, Participant shadow) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Iconsax.warning_2, color: AppColors.error),
            const SizedBox(width: 12),
            const Text('Vanish Shadow'),
          ],
        ),
        content: Text(
          'Delete "${shadow.displayName}" and all their expenses?\n\nThis will recalculate the trip total for everyone else. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final service = ref.read(shadowServiceProvider);
              await service.vanishShadow(shadow.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Vanish'),
          ),
        ],
      ),
    );
  }
}
