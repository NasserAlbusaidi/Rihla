import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
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
import '../../../core/theme/error_widgets.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/localized_dates.dart';
import '../../../shared/widgets/cover_art.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../../../shared/widgets/r_icon_button.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../../shared/widgets/section_header.dart';
import '../../events/models/event_model.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../events/providers/event_provider.dart';
import '../../events/utils/event_display.dart';
import '../keys/group_keys.dart';
import '../models/group_model.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_provider.dart';
import '../widgets/add_shadow_member_sheet.dart';
import '../widgets/group_spending_summary_section.dart';

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
        if (router.canPop()) {
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
            if (group == null) return _NotFoundState(groupId: groupId);
            return _Content(group: group);
          },
          loading: () => const _LoadingState(),
          error: (error, stackTrace) {
            // #358: Firestore denies the group read once a user is removed
            // from / loses access to the group. Show a terminal "no access"
            // state (retrying just re-denies) and keep the raw error out of
            // the UI — log it to Sentry for diagnostics instead.
            if (_isPermissionDenied(error)) {
              unawaited(Sentry.captureException(error, stackTrace: stackTrace));
              return const _NoAccessState();
            }
            return _ErrorState(
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
        _isPermissionDenied(eventsAsync.error!);
    final deniedBalances = balancesAsync.hasError &&
        !balancesAsync.hasValue &&
        _isPermissionDenied(balancesAsync.error!);
    final deniedMembers = membersAsync.hasError &&
        !membersAsync.hasValue &&
        _isPermissionDenied(membersAsync.error!);
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
          SliverToBoxAdapter(child: _CoverHeader(group: group)),
          SliverPadding(
            padding: EdgeInsetsDirectional.fromSTEB(
              context.spacing.space20,
              14,
              context.spacing.space20,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: _BalanceCard(
                group: group,
                lines: balanceLines,
                balancesUnavailable:
                    balancesAsync.hasError && !balancesAsync.hasValue,
                memberNames:
                    balances?.memberNames.values.toList() ?? const <String>[],
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
              child: _MembersCard(
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
                  _EventRow(
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

// ──────────────────────────── Cover header

class _CoverHeader extends StatelessWidget {
  const _CoverHeader({required this.group});
  final Group group;

  @override
  Widget build(BuildContext context) {
    final statusBar = MediaQuery.of(context).padding.top;
    final memberCount = group.memberIds.length;
    return SizedBox(
      height: 168 + statusBar,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // #626: cache the procedural cover raster — this header lives in a
          // SliverToBoxAdapter (no automatic per-child RepaintBoundary).
          RepaintBoundary(child: CoverArt.fromSeed(group.name)),
          // Dark gradient overlay — transparent at top, ink at bottom.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  context.colors.textPrimary.withValues(alpha: 0.55),
                ],
                stops: const [0.4, 1.0],
              ),
            ),
          ),
          // Top buttons row.
          Positioned.directional(
            textDirection: Directionality.of(context),
            top: statusBar + 8,
            start: 12,
            end: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                RIconButton(
                  icon: Directionality.of(context) == TextDirection.rtl
                      ? Iconsax.arrow_right
                      : Iconsax.arrow_left,
                  onTap: () {
                    HapticService.lightClick();
                    final router = GoRouter.of(context);
                    if (router.canPop()) {
                      router.pop();
                    } else {
                      router.go('/home');
                    }
                  },
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // #291: surface "invite a friend" on the group screen —
                    // reuses the link-bearing share message (#277) instead of
                    // burying it in Group Settings.
                    RIconButton(
                      key: GroupKeys.groupDetailInviteButton,
                      icon: Iconsax.user_add,
                      semanticLabel: context.l10n.groupShareInviteSemantic,
                      onTap: () {
                        HapticService.selection();
                        shareText(
                          context,
                          context.l10n.groupShareInviteMessage(
                            group.name,
                            AppLinks.inviteUrl(group.inviteCode).toString(),
                            group.inviteCode,
                          ),
                          subject: context.l10n.groupShareSubject(group.name),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    // #807: promote per-group activity out of the overflow
                    // menu (the menu keeps its entry as a redundant path).
                    RIconButton(
                      key: GroupKeys.groupDetailActivityButton,
                      icon: Iconsax.clock,
                      semanticLabel: context.l10n.groupActivity,
                      onTap: () {
                        HapticService.lightClick();
                        GoRouter.of(
                          context,
                        ).push('/group/${group.id}/activity');
                      },
                    ),
                    const SizedBox(width: 8),
                    _OverflowMenu(groupId: group.id),
                  ],
                ),
              ],
            ),
          ),
          // Bottom title block.
          Positioned.directional(
            textDirection: Directionality.of(context),
            start: 20,
            end: 20,
            top: statusBar + 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.groupMemberCountCaps(memberCount),
                  style: AppTypography.caption(
                    context,
                    fontSize: 9,
                    color: context.colors.textOnPrimary.withValues(alpha: 0.85),
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  group.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.displayOf(
                    context,
                    fontSize: 30,
                    color: context.colors.textOnPrimary,
                    height: 1.05,
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

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: PopupMenuButton<String>(
          tooltip: context.l10n.groupMoreTooltip,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(spacing.radiusLarge),
          ),
          offset: const Offset(0, 44),
          borderRadius: const BorderRadius.all(Radius.circular(24)),
          splashRadius: 24,
          onSelected: (key) {
            switch (key) {
              case 'settings':
                GoRouter.of(context).push('/group/$groupId/settings');
              case 'activity':
                GoRouter.of(context).push('/group/$groupId/activity');
            }
          },
          child: Center(
            child: Material(
              color: colors.cardSurface.withValues(alpha: 0.94),
              shape: const CircleBorder(),
              elevation: 1,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(Iconsax.more, size: 18, color: colors.textPrimary),
              ),
            ),
          ),
          itemBuilder: (ctx) => [
            PopupMenuItem(
              value: 'settings',
              child: Row(
                children: [
                  Icon(Iconsax.setting_2, size: 16, color: colors.textPrimary),
                  const SizedBox(width: 10),
                  Text(context.l10n.groupSettings),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'activity',
              child: Row(
                children: [
                  Icon(Iconsax.activity, size: 16, color: colors.textPrimary),
                  const SizedBox(width: 10),
                  Text(context.l10n.groupActivity),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────── Balance card

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.group,
    required this.lines,
    required this.memberNames,
    required this.onAddPrimary,
    required this.onSettleUp,
    this.balancesUnavailable = false,
  });

  final Group group;
  final List<({String currency, Decimal net})> lines;
  final List<String> memberNames;
  final VoidCallback onAddPrimary;
  final VoidCallback onSettleUp;

  /// #1030: the balance basis hard-errored (`hasError && !hasValue`). An
  /// empty [lines] then means "unknown", not "settled" — the caption must
  /// say so instead of the affirmative false "all settled". Stale-valued
  /// errors keep rendering their stale lines and never set this.
  final bool balancesUnavailable;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final allPositive =
        lines.isNotEmpty && lines.every((l) => l.net > Decimal.zero);
    final allNegative =
        lines.isNotEmpty && lines.every((l) => l.net < Decimal.zero);
    final captionColor = balancesUnavailable
        ? colors.textSecondary
        : allPositive
        ? colors.success
        : allNegative
        ? colors.error
        : colors.textSecondary;
    // L7: tri-state caption only when all non-zero lines share one sign;
    // mixed signs → omitted (signed, toned amounts self-explain).
    // #1030: unavailable wins over everything — an errored basis must never
    // read as the affirmative "all settled".
    final String? captionText = balancesUnavailable
        ? context.l10n.settleUpCouldNotLoadBalances
        : lines.isEmpty
        ? context.l10n.groupAllSettled
        : allPositive
        ? context.l10n.groupTheyOweYou
        : allNegative
        ? context.l10n.groupYouOwe
        : null;

    return Container(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(spacing.radiusLarge),
        boxShadow: context.shadows.raised,
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  context.l10n.groupYourBalanceHere,
                  style: AppTypography.displayOf(
                    context,
                    fontSize: 14,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              if (memberNames.isNotEmpty)
                // #807: the stack read as tappable but did nothing — wire it
                // to the members list it implies (group settings hosts it).
                // GestureDetector, not InkWell: a rectangular splash box would
                // clash with the overlapping circular avatars.
                Semantics(
                  button: true,
                  label: context.l10n.groupSettings,
                  child: GestureDetector(
                    key: GroupKeys.groupDetailMemberStack,
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticService.lightClick();
                      GoRouter.of(
                        context,
                      ).push('/group/${group.id}/settings');
                    },
                    child: RAvatarStack(names: memberNames, size: 22, max: 4),
                  ),
                ),
            ],
          ),
          SizedBox(height: context.spacing.space8),
          if (lines.length >= 2)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < lines.length; i++)
                        Padding(
                          padding: EdgeInsetsDirectional.only(
                            top: i == 0 ? 0 : 4,
                          ),
                          child: RAmount(
                            value: lines[i].net,
                            currency: lines[i].currency,
                            size: 24,
                            sign: true,
                            tone: lines[i].net > Decimal.zero
                                ? AmountTone.sage
                                : AmountTone.rust,
                          ),
                        ),
                    ],
                  ),
                ),
                if (captionText != null)
                  Text(
                    captionText,
                    style: AppTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: captionColor,
                    ),
                  ),
              ],
            )
          else
            _singleLineRow(context, captionText!, captionColor),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _PrimaryCtaButton(
                  icon: Iconsax.add,
                  label: context.l10n.eventNew,
                  onTap: onAddPrimary,
                ),
              ),
              SizedBox(width: context.spacing.space8),
              Expanded(
                child: _SecondaryCtaButton(
                  label: context.l10n.groupSettleUp,
                  buttonKey: GroupKeys.settleUpCta,
                  onTap: onSettleUp,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 0/1-line render — byte-identical to the pre-PR-5 single-currency card
  /// for the all-zero and group-currency cases (L7); a sole foreign-currency
  /// line carries its code.
  Widget _singleLineRow(
    BuildContext context,
    String captionText,
    Color captionColor,
  ) {
    final line = lines.isEmpty ? null : lines.first;
    final net = line?.net ?? Decimal.zero;
    final tone = net > Decimal.zero
        ? AmountTone.sage
        : net < Decimal.zero
        ? AmountTone.rust
        : AmountTone.ink;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        RAmount(
          value: net,
          currency: line?.currency ?? group.currency,
          size: 32,
          sign: !net.isZero,
          tone: tone,
          showCurrency: line != null && line.currency != group.currency,
        ),
        const Spacer(),
        Text(
          captionText,
          style: AppTypography.sans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: captionColor,
          ),
        ),
      ],
    );
  }
}

class _PrimaryCtaButton extends StatelessWidget {
  const _PrimaryCtaButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return Material(
      color: colors.primary,
      borderRadius: BorderRadius.circular(spacing.radiusMedium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(spacing.radiusMedium),
        child: Container(
          height: 42,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: colors.textOnPrimary),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textOnPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryCtaButton extends StatelessWidget {
  const _SecondaryCtaButton({
    required this.label,
    required this.onTap,
    this.buttonKey,
  });
  final String label;
  final VoidCallback onTap;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return Material(
      color: colors.cardSoft,
      borderRadius: BorderRadius.circular(spacing.radiusMedium),
      child: InkWell(
        key: buttonKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(spacing.radiusMedium),
        child: Container(
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(spacing.radiusMedium),
            border: Border.all(color: colors.rule, width: 0.5),
          ),
          child: Text(
            label,
            style: AppTypography.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────── Event row

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.shareLines,
    required this.groupCurrency,
    required this.divider,
    required this.onTap,
  });

  final Event event;
  final List<({String currency, Decimal net})> shareLines;
  final String groupCurrency;
  final bool divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final dateLabel = _formatDates(context, event.startDate, event.endDate);
    // #807: a dateless event (e.g. the #245 auto-seed) used to fall back to
    // the type label here, printing it twice (the 9px mono chip above already
    // shows it) — omit the subtitle line instead.
    final subtitle = dateLabel;
    final hasShare = shareLines.isNotEmpty;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: context.spacing.space12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(spacing.radiusMedium),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: CoverArt.forEventType(event.type),
                  ),
                ),
                SizedBox(width: context.spacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _eventTypeLabel(context, event.type),
                        style: AppTypography.caption(
                          context,
                          fontSize: 9,
                          color: colors.textSecondary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        event.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: AppTypography.sans(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: context.spacing.space8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasShare)
                      // L7: ≥2 lines → every line carries its code; a sole
                      // line only when foreign — keeps the single
                      // group-currency render byte-identical to pre-PR-5.
                      for (var i = 0; i < shareLines.length; i++)
                        Padding(
                          padding: EdgeInsetsDirectional.only(
                            top: i == 0 ? 0 : 2,
                          ),
                          child: RAmount(
                            value: shareLines[i].net,
                            currency: shareLines[i].currency,
                            size: 15,
                            sign: true,
                            showCurrency:
                                shareLines.length >= 2 ||
                                shareLines[i].currency != groupCurrency,
                          ),
                        )
                    else
                      Text(
                        '—',
                        style: AppTypography.sans(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      hasShare
                          ? context.l10n.groupYourShare
                          : context.l10n.groupNoShare,
                      style: AppTypography.sans(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (divider) ...[
              SizedBox(height: context.spacing.space12),
              Container(height: 0.5, color: colors.rule),
            ],
          ],
        ),
      ),
    );
  }

  static String? _formatDates(
    BuildContext context,
    DateTime? start,
    DateTime? end,
  ) {
    if (start != null && end != null) {
      return formatDateRangeShort(context, start, end);
    }
    if (start != null) return formatShortMonthDay(context, start);
    if (end != null) {
      return context.l10n.groupEventEnds(formatShortMonthDay(context, end));
    }
    return null;
  }
}

String _eventTypeLabel(BuildContext context, EventType t) =>
    t.localizedShortLabel(context.l10n);

/// True when a stream error is a Firestore `permission-denied` — i.e. the
/// user no longer has read access to the group (removed / un-shared).
bool _isPermissionDenied(Object error) =>
    error is FirebaseException && error.code == 'permission-denied';

// ──────────────────────────── Members card

class _MembersCard extends StatelessWidget {
  const _MembersCard({
    required this.group,
    required this.balancesAsync,
    required this.currentUid,
    this.forceLoading = false,
    this.membersHasError = false,
  });

  final Group group;
  final AsyncValue<GroupBalances> balancesAsync;
  final String? currentUid;

  /// #574: true while the group-detail staging-window retry is in progress —
  /// render a skeleton, never the transient "couldn't load members" error.
  final bool forceLoading;

  /// #574: true when the members read itself failed — `balancesAsync` swallows a
  /// members error into empty data, so the card needs this to show the real
  /// error instead of an endless "Loading members…".
  final bool membersHasError;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final data = balancesAsync.valueOrNull;

    // #382 PR-1: memberNames (currency-independent, spans every known uid)
    // is the row source — the bucket map is empty for a zero-money group, but
    // the members card must still list everyone. Same key set and order as
    // the old flat balances list.
    if (forceLoading || data == null || data.memberNames.isEmpty) {
      return Container(
        padding: EdgeInsets.symmetric(
          vertical: 18,
          horizontal: context.spacing.space16,
        ),
        decoration: BoxDecoration(
          color: colors.cardSurface,
          borderRadius: BorderRadius.circular(spacing.radiusLarge),
          boxShadow: context.shadows.raised,
        ),
        child: forceLoading
            ? SkeletonLoader.groupList(count: 3)
            : Text(
                (balancesAsync.hasError || membersHasError)
                    ? context.l10n.groupMembersLoadFailed
                    : context.l10n.groupMembersLoading,
                style: AppTypography.sans(
                  fontSize: 13,
                  color: colors.textSecondary,
                ),
              ),
      );
    }

    // #486: the hero owns the current user's net — list everyone ELSE here,
    // then a collapsed "You · shown above" row last that does NOT restate the
    // figure. (currentUid null / absent from the roster → no self-row, all
    // render as others.)
    final allMembers = data.memberNames.entries.toList();
    final others = allMembers.where((e) => e.key != currentUid).toList();
    final selfMatches = allMembers.where((e) => e.key == currentUid).toList();
    final self = selfMatches.isEmpty ? null : selfMatches.first;
    final rowCount = others.length + (self == null ? 0 : 1);
    // #630: one O(C×M) pivot for the whole roster; each row indexes it in O(1)
    // instead of re-running a per-row O(C×M) myNetByCurrency pivot.
    final netsByUid = pivotNetsByParticipant(data.balances);
    return Container(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(spacing.radiusLarge),
        boxShadow: context.shadows.raised,
      ),
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space16),
      child: Column(
        children: [
          for (var i = 0; i < others.length; i++)
            _MemberRow(
              name: others[i].value,
              role: _roleFor(
                context: context,
                participantId: others[i].key,
                creatorId: group.createdBy,
                currentUid: currentUid,
              ),
              lines: nonZeroNetsGccFirst(
                netsByUid[others[i].key] ?? const {},
              ),
              groupCurrency: group.currency,
              divider: i < rowCount - 1,
              onTap: () => GoRouter.of(
                context,
              ).push('/group/${group.id}/settle-up?memberId=${others[i].key}'),
            ),
          if (self != null)
            _MemberRow(
              key: GroupKeys.selfMemberRow,
              name: self.value,
              role: context.l10n.groupRoleYou,
              lines: const [],
              groupCurrency: group.currency,
              divider: false,
              shownAbove: true,
              onTap: null,
            ),
        ],
      ),
    );
  }

  static String? _roleFor({
    required BuildContext context,
    required String participantId,
    required String creatorId,
    required String? currentUid,
  }) {
    if (currentUid != null && participantId == currentUid) {
      return context.l10n.groupRoleYou;
    }
    if (participantId == creatorId) return context.l10n.groupRoleCreator;
    return null;
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    super.key,
    required this.name,
    required this.role,
    required this.lines,
    required this.groupCurrency,
    required this.divider,
    required this.onTap,
    this.shownAbove = false,
  });

  final String name;
  final String? role;
  final List<({String currency, Decimal net})> lines;
  final String groupCurrency;
  final bool divider;
  final VoidCallback? onTap;

  /// #486: the current user's collapsed self-row — name + "(You)" but a muted
  /// "shown above" in place of a money figure (the hero owns their net), and
  /// no tap target (you can't settle up with yourself).
  final bool shownAbove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: context.spacing.space12),
            child: Row(
              children: [
                RAvatar(name: name, size: 32),
                SizedBox(width: context.spacing.space12),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.sans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      if (role != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          role!,
                          style: AppTypography.sans(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: context.spacing.space8),
                if (shownAbove)
                  Text(
                    context.l10n.groupBalanceShownAbove,
                    style: AppTypography.sans(
                      fontSize: 13,
                      color: colors.textSecondary,
                    ),
                  )
                else if (lines.isEmpty)
                  Text(
                    '—',
                    style: AppTypography.sans(
                      fontSize: 13,
                      color: colors.textSecondary,
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // L7: ≥2 lines → every line carries its code; a sole
                      // line only when foreign — keeps the single
                      // group-currency render byte-identical to pre-PR-5.
                      for (var i = 0; i < lines.length; i++)
                        Padding(
                          padding: EdgeInsetsDirectional.only(
                            top: i == 0 ? 0 : 2,
                          ),
                          child: RAmount(
                            value: lines[i].net,
                            currency: lines[i].currency,
                            size: 14,
                            sign: true,
                            showCurrency:
                                lines.length >= 2 ||
                                lines[i].currency != groupCurrency,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          if (divider) Container(height: 0.5, color: colors.rule),
        ],
      ),
    );
  }
}

// ──────────────────────────── Skeleton / states

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusBar = MediaQuery.of(context).padding.top;
    return Column(
      children: [
        SizedBox(
          height: 168 + statusBar,
          child: Container(color: colors.cardSoft),
        ),
        Expanded(child: SkeletonLoader.groupList()),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // #358: adopt the shared NetworkErrorWidget for the generic
    // (non-permission) group-load error instead of a hand-rolled
    // EmptyStateView error variant.
    return SafeArea(
      child: NetworkErrorWidget.loadingError(
        customTitle: context.l10n.groupLoadFailedTitle,
        customMessage: context.l10n.activityLoadFailedMessage,
        onRetry: onRetry,
      ),
    );
  }
}

class _NoAccessState extends StatelessWidget {
  const _NoAccessState();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(context.spacing.space24),
          child: EmptyStateView(
            icon: Iconsax.lock,
            title: context.l10n.groupNoAccessTitle,
            message: context.l10n.groupNoAccessMessage,
            actionLabel: context.l10n.groupBackHome,
            onAction: () => GoRouter.of(context).go('/home'),
          ),
        ),
      ),
    );
  }
}

class _NotFoundState extends StatelessWidget {
  const _NotFoundState({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(context.spacing.space24),
          child: EmptyStateView(
            icon: Iconsax.box_remove,
            title: context.l10n.groupNotFoundTitle,
            message: context.l10n.groupNotFoundMessage,
            actionLabel: context.l10n.groupBackHome,
            onAction: () => GoRouter.of(context).go('/home'),
          ),
        ),
      ),
    );
  }
}

extension on Decimal {
  bool get isZero => this == Decimal.zero;
}
