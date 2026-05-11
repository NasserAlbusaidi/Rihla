import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/cover_art.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../groups/providers/group_provider.dart';
import '../keys/event_keys.dart';
import '../models/event_model.dart';
import '../models/event_type_config.dart';
import '../providers/event_provider.dart';
import '../widgets/event_module_list.dart';
import 'event_expense_hero.dart';

/// Per-event hub — saffron direction.
///
/// The wireframe set goes directly from Group Detail → Ledger and has no
/// dedicated command center. We retain a thin event hub here so that the
/// non-money modules (Gear, Logistics, Vault, Memories) stay reachable; the
/// expense flow still primarily lives in the Ledger.
///
/// Layout, top to bottom:
///   1. Cover header (124px + status bar) — `CoverArt.forEventType`, dark
///      gradient overlay, floating back + settings (paper variant) buttons,
///      bottom-left mono caption ("TRIP · MAR 14 — MAR 22") + italic display
///      event name.
///   2. Existing [EventExpenseHero] card lifted slightly over the cover.
///   3. Existing [EventModuleList] grid showing modules per `EventModules`.
class EventCommandCenter extends ConsumerWidget {
  const EventCommandCenter({
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

    return Scaffold(
      key: EventKeys.screen,
      backgroundColor: context.colors.scaffoldBackground,
      body: eventAsync.when(
        loading: () => const _LoadingState(),
        error: (_, _) => _ErrorState(
          onRetry: () => ref.invalidate(
            eventDetailProvider((groupId: groupId, eventId: eventId)),
          ),
        ),
        data: (event) {
          if (event == null) return const _NotFoundState();
          final group = groupAsync.valueOrNull;
          return _Content(
            event: event,
            groupId: groupId,
            eventId: eventId,
            groupName: group?.name,
          );
        },
      ),
    );
  }
}

// ──────────────────────────── Content

class _Content extends StatelessWidget {
  const _Content({
    required this.event,
    required this.groupId,
    required this.eventId,
    required this.groupName,
  });

  final Event event;
  final String groupId;
  final String eventId;
  final String? groupName;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _CoverHeader(
            event: event,
            groupName: groupName,
            onSettings: () {
              HapticService.lightClick();
              GoRouter.of(
                context,
              ).push('/group/$groupId/event/$eventId/settings');
            },
          ),
        ),
        const SliverToBoxAdapter(child: OfflineBanner()),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -20),
              child: EventExpenseHero(
                event: event,
                onTap: () => GoRouter.of(
                  context,
                ).push('/group/$groupId/event/$eventId/ledger'),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          sliver: SliverToBoxAdapter(
            child: EventModuleList(
              groupId: groupId,
              eventId: eventId,
              modules: event.modules,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

// ──────────────────────────── Cover header

class _CoverHeader extends StatelessWidget {
  const _CoverHeader({
    required this.event,
    required this.groupName,
    required this.onSettings,
  });

  final Event event;
  final String? groupName;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final statusBar = MediaQuery.of(context).padding.top;
    final config = EventTypeConfig.forType(event.type);
    final dateRange = _formatDateRange(event.startDate, event.endDate);
    final captionParts = <String>[
      config.label.toUpperCase(),
      ?dateRange,
      if (groupName != null && groupName!.isNotEmpty) groupName!,
    ];

    return SizedBox(
      height: 148 + statusBar,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CoverArt.forEventType(event.type),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  context.colors.textPrimary.withValues(alpha: 0.55),
                ],
                stops: const [0.35, 1.0],
              ),
            ),
          ),
          Positioned(
            top: statusBar + 8,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _PaperIconButton(
                  icon: Iconsax.arrow_left,
                  onTap: () {
                    HapticService.lightClick();
                    if (GoRouter.of(context).canPop()) {
                      GoRouter.of(context).pop();
                    }
                  },
                ),
                _PaperIconButton(
                  key: EventKeys.settingsGearIcon,
                  icon: Iconsax.setting_2,
                  onTap: onSettings,
                ),
              ],
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  captionParts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.mono(
                    fontSize: 9,
                    color: Colors.white.withValues(alpha: 0.85),
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  event.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.display(
                    fontSize: 26,
                    color: Colors.white,
                    height: 1.05,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String? _formatDateRange(DateTime? start, DateTime? end) {
    if (start == null && end == null) return null;
    String fmt(DateTime d) => '${_months[d.month - 1]} ${d.day}';
    if (start == null) return fmt(end!);
    if (end == null) return fmt(start);
    return '${fmt(start)} — ${fmt(end)}';
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

class _PaperIconButton extends StatelessWidget {
  const _PaperIconButton({super.key, required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.cardSurface.withValues(alpha: 0.94),
      shape: const CircleBorder(),
      elevation: 1,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: colors.textPrimary),
        ),
      ),
    );
  }
}

// ──────────────────────────── States

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusBar = MediaQuery.of(context).padding.top;
    return Column(
      children: [
        SizedBox(
          height: 148 + statusBar,
          child: Container(color: colors.cardSoft),
        ),
        const Spacer(),
        CircularProgressIndicator(color: colors.primary),
        const Spacer(flex: 3),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: EmptyStateView(
            icon: Iconsax.warning_2,
            title: 'Could not load event',
            message: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: onRetry,
          ),
        ),
      ),
    );
  }
}

class _NotFoundState extends StatelessWidget {
  const _NotFoundState();
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: EmptyStateView(
            icon: Iconsax.box_remove,
            title: 'Event not found',
            message: 'It may have been deleted, or the link is incorrect.',
            actionLabel: 'Go Home',
            onAction: () => GoRouter.of(context).go('/home'),
          ),
        ),
      ),
    );
  }
}
