import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/tokens/color_tokens.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../keys/event_keys.dart';
import '../providers/event_provider.dart';
import '../widgets/event_danger_section.dart';
import '../widgets/event_info_section.dart';

/// Screen for managing event settings — name, dates, description, and
/// danger zone (delete event for creators).
///
/// Mirrors GroupSettingsScreen layout: no AppBar, inline back button,
/// SingleChildScrollView with 24px horizontal padding, two section widgets
/// with staggered entrance animations.
class EventSettingsScreen extends ConsumerWidget {
  const EventSettingsScreen({
    super.key,
    required this.groupId,
    required this.eventId,
  });

  final String groupId;
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(
      eventDetailProvider((groupId: groupId, eventId: eventId)),
    );
    final currentUserId = ref.watch(currentUserIdProvider);

    return Scaffold(
      key: EventKeys.settingsScreen,
      backgroundColor: AppColorTokens.light.scaffoldBackground,
      body: SafeArea(
        child: eventAsync.when(
          data: (event) {
            if (event == null) {
              return _buildError(context, ref, 'Event not found');
            }

            final isCreator =
                currentUserId != null && currentUserId == event.createdBy;

            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    _buildBackButton(context),
                    const SizedBox(height: 16),
                    Text(
                      'Event Settings',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColorTokens.light.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    EventInfoSection(event: event)
                        .animate()
                        .fadeIn(delay: 100.ms, duration: 400.ms)
                        .slideY(begin: 0.1, curve: Curves.easeOutCubic),
                    const SizedBox(height: 16),
                    if (isCreator)
                      EventDangerSection(
                        groupId: groupId,
                        eventId: eventId,
                        event: event,
                        isCreator: isCreator,
                      )
                          .animate()
                          .fadeIn(delay: 200.ms, duration: 400.ms)
                          .slideY(begin: 0.1, curve: Curves.easeOutCubic),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            );
          },
          loading: () => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                _buildBackButton(context),
                const SizedBox(height: 16),
                SkeletonLoader.generic(count: 3),
              ],
            ),
          ),
          error: (e, st) => _buildError(context, ref, null),
        ),
      ),
    );
  }

  Widget _buildBackButton(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: EventKeys.settingsBackButton,
        decoration: BoxDecoration(
          color: AppColorTokens.light.inputFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColorTokens.light.inputFill),
        ),
        child: IconButton(
          icon: Icon(
            Iconsax.arrow_left,
            color: AppColorTokens.light.textPrimary,
            size: 20,
          ),
          onPressed: () => GoRouter.of(context).pop(),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref, String? message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          _buildBackButton(context),
          const SizedBox(height: 48),
          Center(
            child: Column(
              children: [
                Icon(
                  Iconsax.warning_2,
                  size: 32,
                  color: AppColorTokens.light.textSecondary,
                ),
                const SizedBox(height: 8),
                Text(
                  'Could not load settings',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColorTokens.light.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Check your connection and try again.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppColorTokens.light.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => ref.invalidate(
                    eventDetailProvider(
                        (groupId: groupId, eventId: eventId)),
                  ),
                  child: Text(
                    'Try again',
                    style: TextStyle(color: AppColorTokens.light.primary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
