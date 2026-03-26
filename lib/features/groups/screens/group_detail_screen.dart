import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/module_header.dart';
// skeleton_loader not used here — members section uses inline placeholders
import '../../events/providers/event_provider.dart';
import '../../events/screens/event_type_picker_screen.dart';
import '../../events/widgets/event_card.dart';
import '../models/group_model.dart';
import '../providers/group_provider.dart';
import '../widgets/group_member_tile.dart';
import '../widgets/invite_code_display.dart';
import 'group_settings_screen.dart';

/// Group dashboard screen showing the group header, stats chips,
/// invite code section, real-time members list, and event timeline
/// placeholder (GRP-03, D-14).
class GroupDetailScreen extends ConsumerWidget {
  final String groupId;

  const GroupDetailScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupDetailProvider(groupId));

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: Semantics(
        label: 'Create event',
        button: true,
        child: FloatingActionButton(
          onPressed: () => Navigator.of(context).push(
            AppPageRoute(
              builder: (_) => EventTypePickerScreen(groupId: groupId),
            ),
          ),
          backgroundColor: AppColors.primary,
          shape: const CircleBorder(),
          child: const Icon(Iconsax.add, color: Colors.black),
        ),
      ),
      body: groupAsync.when(
        data: (group) {
          if (group == null) {
            return const Center(child: Text('Group not found'));
          }
          return _buildContent(context, ref, group);
        },
        loading: () => _buildLoading(context),
        error: (e, st) => const Center(child: Text('Error loading group')),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, Group group) {
    return Column(
      children: [
        ModuleHeader(
          title: group.name,
          subtitle: 'Created ${DateFormat('MMM d, yyyy').format(group.createdAt)}',
          actions: [
            // Settings icon — navigates to GroupSettingsScreen
            IconButton(
              icon: const Icon(
                Iconsax.setting_2,
                color: Colors.white,
                size: 22,
              ),
              onPressed: () => Navigator.of(context).push(
                AppPageRoute(
                  builder: (_) => GroupSettingsScreen(groupId: group.id),
                ),
              ),
            ),
          ],
          useDarkTheme: true,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppColors.space24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppColors.space8),
                _buildStatsRow(context, group),
                const SizedBox(height: AppColors.space24),
                _buildInviteSection(context, group),
                const SizedBox(height: AppColors.space24),
                _buildMembersSection(context, ref),
                const SizedBox(height: AppColors.space24),
                _buildEventsSection(context, ref, group),
                const SizedBox(height: AppColors.space32),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(BuildContext context, Group group) {
    return Row(
      children: [
        // Member count chip
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppColors.space8,
            vertical: AppColors.space4,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(AppColors.radiusSmall),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Iconsax.people,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppColors.space4),
              Text(
                '${group.memberIds.length} members',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppColors.space8),
        // Currency chip
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppColors.space8,
            vertical: AppColors.space4,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(AppColors.radiusSmall),
          ),
          child: Text(
            group.currency,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Widget _buildInviteSection(BuildContext context, Group group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Invite Code',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppColors.space12),
        InviteCodeDisplay(code: group.inviteCode),
        const SizedBox(height: AppColors.space12),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: AppColors.buttonHeight,
                child: ElevatedButton.icon(
                  icon: const Icon(Iconsax.copy, size: 16),
                  label: const Text('Copy'),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppColors.radiusMedium),
                    ),
                  ),
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: group.inviteCode),
                    );
                    HapticService.success();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Invite code copied'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: AppColors.space12),
            Expanded(
              child: SizedBox(
                height: AppColors.buttonHeight,
                child: OutlinedButton.icon(
                  icon: const Icon(Iconsax.share, size: 16),
                  label: const Text('Share'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppColors.radiusMedium),
                    ),
                  ),
                  onPressed: () {
                    Share.share(
                      'Join my group on Rihla! Use code ${group.inviteCode} to join.',
                      subject: 'Join ${group.name}',
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMembersSection(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(groupMembersProvider(groupId));
    // Safely retrieve UID — returns null when Firebase is not initialized
    // (e.g., in widget test environments).
    String? currentUid;
    try {
      currentUid = FirebaseConfig.currentUser?.uid;
    } catch (_) {
      currentUid = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Members',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppColors.space12),
        membersAsync.when(
          data: (members) => Column(
            children: members
                .map(
                  (m) => GroupMemberTile(
                    member: m,
                    isCurrentUser: m.userId == currentUid,
                  ),
                )
                .toList(),
          ),
          loading: () => Column(
            children: List.generate(
              2,
              (_) => Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppColors.space8,
                ),
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius:
                        BorderRadius.circular(AppColors.radiusSmall),
                  ),
                ),
              ),
            ),
          ),
          error: (e, st) => Text(
            "Couldn't load members",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildEventsSection(
    BuildContext context,
    WidgetRef ref,
    Group group,
  ) {
    final eventsAsync = ref.watch(groupEventsProvider(groupId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header with optional count chip when events exist
        eventsAsync.when(
          data: (events) => Row(
            children: [
              Text(
                'Events',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              if (events.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppColors.space8,
                    vertical: AppColors.space4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius:
                        BorderRadius.circular(AppColors.radiusSmall),
                  ),
                  child: Text(
                    '${events.length}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ),
            ],
          ),
          loading: () =>
              Text('Events', style: Theme.of(context).textTheme.titleMedium),
          error: (e, st) =>
              Text('Events', style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: AppColors.space12),
        // Event list or empty state
        eventsAsync.when(
          data: (events) {
            if (events.isEmpty) {
              return const EmptyStateView(
                icon: Iconsax.calendar_add,
                title: 'No events yet',
                message:
                    'Tap the + button to create the first event for this group.',
              );
            }
            return Column(
              children: [
                for (int i = 0; i < events.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppColors.space12),
                  EventCard(
                    event: events[i],
                    onTap: () {
                      // TODO(Plan 03-04): Navigate to EventCommandCenter
                      // Navigator.of(context).push(
                      //   AppPageRoute(
                      //     builder: (_) => EventCommandCenter(
                      //       event: events[i],
                      //       group: group,
                      //     ),
                      //   ),
                      // );
                    },
                  ),
                ],
              ],
            );
          },
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text(
            "Couldn't load events",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoading(BuildContext context) {
    return const Column(
      children: [
        ModuleHeader(
          title: 'Loading...',
          subtitle: '',
          useDarkTheme: true,
        ),
        Expanded(
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }
}
