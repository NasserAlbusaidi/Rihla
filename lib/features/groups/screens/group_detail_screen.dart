import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../../../core/utils/share_helper.dart';

import '../../../core/config/app_links.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/firestore_error_utils.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/no_access_view.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../../shared/widgets/section_header.dart';
import '../../events/models/event_model.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../events/providers/event_provider.dart';
import '../keys/group_keys.dart';
import '../models/group_model.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_provider.dart';
import '../widgets/add_shadow_member_sheet.dart';
import '../widgets/group_spending_summary_section.dart';
import '../widgets/group_detail/balance_card.dart';
import '../widgets/group_detail/cover_header.dart';
import '../widgets/group_detail/event_row.dart';
import '../widgets/group_detail/members_card.dart';
import '../widgets/group_detail/error_state.dart';
import '../widgets/group_detail/loading_state.dart';
import '../widgets/group_detail/not_found_state.dart';

/// Group detail screen — saffron travel-journal direction.
///
/// Wireframe ref: `Wireframes/Rihla/hifi/screens-group.jsx` → `Hi_GroupDetail()`.
/// Layout, top to bottom:
///  1. Cover header (168px + status bar) — algorithmic cover art, dark
///     gradient overlay, floating back + overflow buttons, group name in
///     italic display with mono "GROUP · N MEMBERS" caption.
///  2. Balance card — sits below the cover with a comfortable gap. Italic
///     header + member avatar stack + RAmount(sign) + sage/rust caption + two CTAs
///     (New event · Settle up).
///  3. Events section — `SectionHeader` with member-visible "New event" action,
///     then per-event rows (56×56 cover swatch · mono type label · name ·
///     date range · per-user share).
///  4. Members section — card-wrapped rows with `RAvatar` · name + role
///     suffix · `RAmount` sign trailing.
///
/// Activity lives on a dedicated screen (`/group/:gid/activity`), reached
/// from the header's clock icon (#807 promotion) and, redundantly, the
/// overflow menu's "Activity" entry.
class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupDetailProvider(groupId));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final router = GoRouter.of(context);
        final routerCanPop = router.canPop();
        // #1188 Part B: breadcrumb the back event so a later Sentry event
        // carries the back-navigation context (no-op when uninitialized).
        Sentry.addBreadcrumb(
          Breadcrumb(
            category: 'nav.back',
            message: 'group-detail back',
            data: {'routerCanPop': routerCanPop},
            level: SentryLevel.info,
          ),
        );
        if (routerCanPop) {
          router.pop();
        } else {
          router.go('/home');
        }
      },
      child: Scaffold(
        key: GroupKeys.detailScreen,
        backgroundColor: context.colors.scaffoldBackground,
        body: groupAsync.when(
          data: (group) {
            if (group == null) return NotFoundState(groupId: groupId);
            return _Content(group: group);
          },
          loading: () => const LoadingState(),
          error: (error, stackTrace) {
            // #358: Firestore denies the group read once a user is removed
            // from / loses access to the group. Show a terminal "no access"
            // state (retrying just re-denies) and keep the raw error out of
            // the UI — log it to Sentry for diagnostics instead.
            if (isPermissionDenied(error)) {
              unawaited(Sentry.captureException(error, stackTrace: stackTrace));
              return const NoAccessView();
            }
            return ErrorState(
              onRetry: () => ref.invalidate(groupDetailProvider(groupId)),
            );
          },
        ),
      ),
    );
  }
}

// ──────────────────────────── Content

class _Content extends ConsumerStatefulWidget {
  const _Content({required this.group});

  final Group group;

  @override
  ConsumerState<_Content> createState() => _ContentState();
}

class _ContentState extends ConsumerState<_Content> {
  // #574: a freshly-created group transiently denies its members/events
  // subcollection listens for ~1s (server consistency lag after create). A
  // Firestore listen that hits permission-denied is TERMINATED — it won't
  // recover on its own — so re-subscribe a bounded number of times, showing a
  // skeleton meanwhile, instead of flashing a hard "couldn't load" error. A
  // genuine, persistent denial still surfaces after the bound (no infinite
  // skeleton); non-permission errors are never retried.
  static const _maxStagingRetries = 3;
  static const _stagingRetryDelay = Duration(milliseconds: 800);
  int _stagingRetries = 0;
  Timer? _retryTimer;

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  void _scheduleStagingRetry() {
    if (_retryTimer?.isActive ?? false) return;
    final groupId = widget.group.id;
    _retryTimer = Timer(_stagingRetryDelay, () {
      if (!mounted) return;
      setState(() => _stagingRetries++);
      // Re-subscribe the terminated listens; balances recomputes from them.
      ref.invalidate(groupBalancesProvider(groupId));
      ref.invalidate(groupMembersProvider(groupId));
      ref.invalidate(groupEventsProvider(groupId));
    });
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final eventsAsync = ref.watch(groupEventsProvider(group.id));
    final balancesAsync = ref.watch(groupBalancesProvider(group.id));
    // Watch members directly: a members hard error is loud on balancesAsync
    // since #1030, but the direct watch is still needed to retry the members
    // listen itself AND to surface its terminal error on the members card
    // (else _MembersCard hangs on "Loading members…").
    final membersAsync = ref.watch(groupMembersProvider(group.id));
    final currentUid = ref.watch(currentUserIdProvider);
    final balances = balancesAsync.valueOrNull;
    final balanceLines = nonZeroNetsGccFirst(
      myNetByCurrency(balances?.balances ?? const {}, currentUid),
    );

    // #574: bounded retry while a freshly-created group's subcollection listens
    // transiently deny (permission-denied). The members/events listens are
    // INDEPENDENT and the server can grant them at different times, so all three
    // are observed. Render a skeleton during the window; surface the real error
    // only once the retry budget is spent.
    final deniedEvents = eventsAsync.hasError &&
        !eventsAsync.hasValue &&
        isPermissionDenied(eventsAsync.error!);
    final deniedBalances = balancesAsync.hasError &&
        !balancesAsync.hasValue &&
        isPermissionDenied(balancesAsync.error!);
    final deniedMembers = membersAsync.hasError &&
        !membersAsync.hasValue &&
        isPermissionDenied(membersAsync.error!);
    final anyDenied = deniedEvents || deniedBalances || deniedMembers;
    final staging = anyDenied && _stagingRetries < _maxStagingRetries;
    if (staging) {
      _scheduleStagingRetry();
    } else if (!anyDenied && (eventsAsync.hasValue || balancesAsync.hasValue)) {
      // Reset the budget ONLY when fully recovered. While any source is still
      // denied after the budget is spent, leave retries pinned so the state stays
      // terminal instead of looping reset → re-retry forever.
      _stagingRetries = 0;
    }

    // A members read that failed (even one balancesAsync swallowed into empty
    // data) must show the real error after the bound, never an endless spinner.
    final membersHasError = membersAsync.hasError && !membersAsync.hasValue;

    return RefreshIndicator(
      color: context.colors.primary,
      backgroundColor: context.colors.cardSurface,
      onRefresh: () async {
        ref.invalidate(groupDetailProvider(group.id));
        ref.invalidate(groupEventsProvider(group.id));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: CoverHeader(group: group)),
          SliverPadding(
            padding: EdgeInsetsDirectional.fromSTEB(
              context.spacing.space20,
              14,
              context.spacing.space20,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: BalanceCard(
                group: group,
                lines: balanceLines,
                balancesUnavailable:
                    balancesAsync.hasError && !balancesAsync.hasValue,
                memberNames:
                    balances?.memberNames.values.toList() ?? const <String>[],
                memberIds:
                    balances?.memberNames.keys.toList() ?? const <String>[],
                onAddPrimary: () {
                  HapticService.lightClick();
                  GoRouter.of(context).push('/group/${group.id}/create-event');
                },
                onSettleUp: () {
                  HapticService.lightClick();
                  GoRouter.of(context).push('/group/${group.id}/settle-up');
                },
              ).animate().fadeIn(delay: 80.ms, duration: 360.ms),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: context.spacing.space20)),
          SliverToBoxAdapter(
            // #486: single "New event" entry. The hero CTA owns it; this header
            // no longer duplicates the action ~40px away.
            child: SectionHeader(
              key: GroupKeys.eventsSection,
              title: context.l10n.groupEvents,
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: context.spacing.space8)),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
            sliver: _eventsSliver(
              context: context,
              eventsAsync: eventsAsync,
              balances: balances,
              currentUid: currentUid,
              groupId: group.id,
              currency: group.currency,
              forceLoading: staging,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 22)),
          SliverToBoxAdapter(
            // #807: creator-only shortcut to add-by-name — the same sheet the
            // settings screen offers, without the 4-tap settings detour. The
            // gate mirrors GroupMembersSection's isCurrentUserCreator. D6-R:
            // anonymous creators included — addShadowMember accepts them; the
            // durable boundary is at join/claim.
            child: SectionHeader(
              key: GroupKeys.membersAndBalancesSection,
              title: context.l10n.groupPeople,
              actionLabel: currentUid != null && group.createdBy == currentUid
                  ? context.l10n.groupAddMemberAction
                  : null,
              actionKey: GroupKeys.groupDetailAddPersonAction,
              onActionTap: currentUid != null && group.createdBy == currentUid
                  ? () {
                      HapticService.selection();
                      AddShadowMemberSheet.show(context, groupId: group.id);
                    }
                  : null,
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: context.spacing.space8)),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
            sliver: SliverToBoxAdapter(
              child: MembersCard(
                group: group,
                balancesAsync: balancesAsync,
                currentUid: currentUid,
                forceLoading: staging,
                membersHasError: membersHasError,
              ),
            ),
          ),
          // #180: header + padding live INSIDE the widget so an empty group
          // renders nothing here — no dangling section header.
          SliverToBoxAdapter(
            child: GroupSpendingSummarySection(groupId: group.id),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _eventsSliver({
    required BuildContext context,
    required AsyncValue<List<Event>> eventsAsync,
    required GroupBalances? balances,
    required String? currentUid,
    required String groupId,
    required String currency,
    bool forceLoading = false,
  }) {
    if (forceLoading) {
      // #574: staging-window retry in progress — show the loading skeleton, not
      // the transient permission-denied error.
      return SliverToBoxAdapter(child: SkeletonLoader.eventCard());
    }
    return eventsAsync.when(
      data: (events) {
        if (events.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: context.spacing.space20),
              child: EmptyStateView(
                key: GroupKeys.noEventsEmpty,
                icon: Iconsax.calendar_add,
                title: context.l10n.groupNoEventsTitle,
                message: context.l10n.groupNoEventsMessage,
                actionLabel: context.l10n.groupCreateEvent,
                onAction: () =>
                    GoRouter.of(context).push('/group/$groupId/create-event'),
                // #353 — let the creator pull members in immediately, reusing
                // the existing link-bearing invite share (#291/#277).
                secondaryActionLabel: context.l10n.groupInvitePeople,
                secondaryActionIcon: Iconsax.user_add,
                onSecondaryAction: () {
                  HapticService.selection();
                  shareText(
                    context,
                    context.l10n.groupShareInviteMessage(
                      widget.group.name,
                      AppLinks.inviteUrl(widget.group.inviteCode).toString(),
                      widget.group.inviteCode,
                    ),
                    subject: context.l10n.groupShareSubject(widget.group.name),
                  );
                },
              ),
            ),
          );
        }
        final perEvent = (currentUid != null && balances != null)
            ? balances.perEventBreakdown[currentUid] ?? const {}
            : const <String, Map<String, Decimal>>{};
        // #807: card-wrap the rows (same treatment as _MembersCard /
        // _BalanceCard) so the events — including a fresh group's auto-seeded
        // one (#245) — carry visual weight next to the loud "New event" CTA
        // instead of rendering as bare undressed list rows.
        return SliverToBoxAdapter(
          child: Container(
            decoration: BoxDecoration(
              color: context.colors.cardSurface,
              borderRadius: BorderRadius.circular(
                context.spacing.radiusLarge,
              ),
              boxShadow: context.shadows.raised,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: context.spacing.space16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < events.length; index++)
                  EventRow(
                    event: events[index],
                    shareLines: nonZeroNetsGccFirst(
                      perEvent[events[index].id] ?? const <String, Decimal>{},
                    ),
                    groupCurrency: currency,
                    divider: index != events.length - 1,
                    onTap: () => GoRouter.of(
                      context,
                    ).push('/group/$groupId/event/${events[index].id}'),
                  ),
              ],
            ),
          ),
        );
      },
      loading: () =>
          SliverToBoxAdapter(child: SkeletonLoader.eventCard()),
      error: (_, _) => SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: context.spacing.space12),
          child: Text(
            context.l10n.groupLoadEventsFailed,
            style: AppTypography.sans(
              fontSize: 13,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

