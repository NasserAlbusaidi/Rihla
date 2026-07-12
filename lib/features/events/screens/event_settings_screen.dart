import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../shared/widgets/r_icon_button.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../keys/event_keys.dart';
import '../providers/event_provider.dart';
import '../utils/event_permissions.dart';
import '../widgets/event_danger_section.dart';
import '../widgets/event_info_section.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

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
    final groupAsync = ref.watch(groupDetailProvider(groupId));
    final currentUserId = ref.watch(currentUserIdProvider);

    return Scaffold(
      key: EventKeys.settingsScreen,
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: eventAsync.when(
          data: (event) {
            if (event == null) {
              return _buildError(context, ref, context.l10n.eventNotFound);
            }

            final group = groupAsync.valueOrNull;
            final isAdmin =
                group != null &&
                EventPermissions.isEventAdmin(
                  event: event,
                  group: group,
                  currentUserId: currentUserId,
                );

            return SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.spacing.space24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: context.spacing.space16),
                    _buildBackButton(context),
                    SizedBox(height: context.spacing.space16),
                    Text(
                      context.l10n.eventSettingsTitle,
                      style: AppTypography.displayOf(
                        context,
                        fontSize: 28,
                        color: context.colors.textPrimary,
                        letterSpacing: -0.5,
                        height: 1.0,
                      ),
                    ),
                    SizedBox(height: context.spacing.space24),
                    EventInfoSection(event: event)
                        .animate()
                        .fadeIn(delay: 100.ms, duration: 400.ms)
                        .slideY(begin: 0.1, curve: Curves.easeOutCubic),
                    SizedBox(height: context.spacing.space16),
                    if (isAdmin)
                      EventDangerSection(
                            groupId: groupId,
                            eventId: eventId,
                            event: event,
                            isAdmin: isAdmin,
                          )
                          .animate()
                          .fadeIn(delay: 200.ms, duration: 400.ms)
                          .slideY(begin: 0.1, curve: Curves.easeOutCubic),
                    SizedBox(height: context.spacing.space32),
                  ],
                ),
              ),
            );
          },
          loading: () => Padding(
            padding: EdgeInsets.symmetric(horizontal: context.spacing.space24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: context.spacing.space16),
                _buildBackButton(context),
                SizedBox(height: context.spacing.space16),
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
      alignment: AlignmentDirectional.centerStart,
      child: RIconButton(
        key: EventKeys.settingsBackButton,
        variant: RIconButtonVariant.ghost,
        icon: Iconsax.arrow_left,
        matchTextDirection: true,
        onTap: () => GoRouter.of(context).pop(),
      ),
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref, String? message) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: context.spacing.space16),
          _buildBackButton(context),
          const SizedBox(height: 48),
          Center(
            child: Column(
              children: [
                Icon(
                  Iconsax.warning_2,
                  size: 32,
                  color: context.colors.textSecondary,
                ),
                SizedBox(height: context.spacing.space8),
                Text(
                  context.l10n.eventSettingsLoadFailed,
                  style: AppTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                  ),
                ),
                SizedBox(height: context.spacing.space4),
                Text(
                  context.l10n.activityLoadFailedMessage,
                  style: AppTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: context.colors.textSecondary,
                  ),
                ),
                SizedBox(height: context.spacing.space16),
                TextButton(
                  onPressed: () => ref.invalidate(
                    eventDetailProvider((groupId: groupId, eventId: eventId)),
                  ),
                  child: Text(
                    context.l10n.groupTryAgain,
                    style: TextStyle(color: context.colors.primary),
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
