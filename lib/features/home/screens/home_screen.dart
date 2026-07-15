import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/activity_row.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../../shared/widgets/scroll_under_header.dart';
import '../../../shared/widgets/section_header.dart';
import '../../activity/utils/activity_display.dart';
import '../../activity/utils/activity_nav.dart';
import '../../auth/widgets/apple_restore_action.dart';
import '../../auth/widgets/google_restore_action.dart';
import '../../groups/models/group_model.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../keys/home_keys.dart';
import '../providers/active_journeys_provider.dart';
import '../providers/dashboard_providers.dart';
import '../widgets/account_backup_nudge.dart';
import '../widgets/add_expense_fab.dart';
import '../widgets/balance_hero_card.dart';
import '../widgets/bottom_nav_shell.dart';
import '../widgets/group_balance_breakdown_sheet.dart';
import '../widgets/guest_account_caption.dart';
import '../widgets/home/greeting_strip.dart';
import '../widgets/home/group_row.dart';
import '../widgets/home/journeys_strip.dart';
import '../widgets/home/top_bar.dart';

/// Home dashboard — saffron travel-journal direction (v2.0).
///
/// Layout, top to bottom:
///  1. Top bar: avatar · italic "Rihla" wordmark with saffron flourish · bell
///  2. Greeting strip: mono uppercase "GOOD MORNING, NAME"
///  3. Hero balance card (saffron-direction rewrite)
///  4. ACTIVE JOURNEYS — horizontal scroll of [JourneyTicketCard]
///  5. GROUPS — list of glyph + name + balance rows
///  6. RECENTLY — top 3 entries from [crossGroupActivityProvider]
///
/// State coverage:
///  - empty → [EmptyStateView] CTA to create or join
///  - loading → [Skeletonizer] over the loaded layout
///  - error → [OfflineBanner] + retry CTA
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BottomNavShell(
      scaffoldKey: HomeKeys.screen,
      child: _DashboardContent(),
    );
  }
}

class _DashboardContent extends ConsumerStatefulWidget {
  @override
  ConsumerState<_DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends ConsumerState<_DashboardContent> {
  final _scrollController = ScrollController();
  final _journeysSectionKey = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(userGroupsProvider);
    // #1011: shared scroll-edge hairline — fades in under the fixed TopBar once
    // the dashboard scrolls beneath it (was a bare Column[TopBar, Expanded]).
    return ScrollUnderHeader(
      header: const TopBar(),
      child: groupsAsync.when(
        data: (groups) => groups.isEmpty
            ? _buildEmpty(context)
            : _buildLoaded(context, groups),
        loading: () => _buildSkeleton(context),
        error: (_, _) => _buildError(context),
      ),
    );
  }

  // ──────────────── Loaded ────────────────

  Widget _buildLoaded(
    BuildContext context,
    List<Group> groups, {
    bool isPlaceholder = false,
  }) {
    final activityAsync = ref.watch(crossGroupActivityProvider);
    final journeysAsync = ref.watch(activeJourneysProvider);
    final targetsAsync = ref.watch(addExpenseTargetsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(userGroupsProvider);
        // #104/#410: refresh the one-shot FALLBACK path (offline / missing
        // aggregate doc). The #366 aggregate path needs no invalidation — its
        // single-doc stream is live, so peer-device updates arrive without a
        // pull (the trigger writes the doc, the listener emits).
        ref.invalidate(groupBalancesOnceProvider);
        await ref.read(userGroupsProvider.future);
      },
      color: context.colors.primary,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(child: GreetingStrip(name: _firstName())),
          // #818 Wave 4.3: persistent guest-account explainer — the only
          // non-dismissible statement of the "lives on this phone" fact,
          // since the #285 backup nudge below can be dismissed forever.
          const SliverToBoxAdapter(child: GuestAccountCaption()),
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
          SliverToBoxAdapter(
            child:
                BalanceHeroCard(
                  onTap: () => GroupBalanceBreakdownSheet.show(context),
                )
                .animate()
                .fadeIn(delay: 250.ms, duration: 500.ms)
                .slideY(begin: 0.15, curve: Curves.easeOutQuart),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 22)),
          // #285: one-time, non-blocking prompt to back up an anonymous account
          // by linking an email. Self-hides unless the user is anonymous; lives
          // here so it only appears once the user has a group (data to lose).
          const SliverToBoxAdapter(child: AccountBackupNudge()),
          SliverToBoxAdapter(
            child: KeyedSubtree(
              key: _journeysSectionKey,
              child: SectionHeader(
                title: context.l10n.homeActiveJourneys,
                actionLabel:
                    journeysAsync.hasValue &&
                        (journeysAsync.value?.isNotEmpty ?? false)
                    ? context.l10n.homeSeeActivity
                    : null,
                onActionTap: () {
                  // #818 Wave 5.2: same tab-select as the bell — one
                  // concern, same destination.
                  final scope = BottomNavTabScope.maybeOf(context);
                  if (scope != null) {
                    scope.selectTab(1);
                  } else {
                    context.push('/activity');
                  }
                },
              ).animate().fadeIn(delay: 350.ms),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
          SliverToBoxAdapter(
            child: JourneysStrip(journeysAsync: journeysAsync),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 22)),
          SliverToBoxAdapter(
            child: SectionHeader(
              title: context.l10n.homeGroups,
              actionLabel: context.l10n.homeNewGroup,
              actionKey: HomeKeys.createGroupFab,
              onActionTap: () => _showCreateOrJoinSheet(context),
            ).animate().fadeIn(delay: 500.ms),
          ),
          const SliverToBoxAdapter(
            child: SizedBox(key: HomeKeys.groupsHeaderGap, height: 14),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final isLast = index == groups.length - 1;
                return GroupRow(
                      group: groups[index],
                      isLast: isLast,
                      isPlaceholder: isPlaceholder,
                      onTap: () {
                        HapticService.lightClick();
                        // #900 friction #2: smart-forward to the sole open
                        // event so a one-open-event group skips the
                        // zero-expense group overview. Client-side only —
                        // never a router redirect (see PR-5 §2).
                        final gid = groups[index].id;
                        final targets =
                            targetsAsync.valueOrNull ?? AddExpenseTargets.empty;
                        final open = targets.openByGroup[gid];
                        final soleEvent =
                            (targets.allResolved &&
                                open != null &&
                                open.length == 1)
                            ? open.single
                            : null;
                        if (soleEvent != null) {
                          // #996: push the /group/:gid ancestor FIRST —
                          // go_router's imperative push does NOT materialize
                          // ancestors, so without this Back from the hub
                          // skipped the overview (the only home of + New
                          // event / invite / settings) straight to home.
                          context.push('/group/$gid');
                          context.push('/group/$gid/event/${soleEvent.eventId}');
                        } else {
                          context.push('/group/$gid');
                        }
                      },
                    )
                    .animate()
                    .fadeIn(delay: (550 + (index * 50)).ms, duration: 400.ms)
                    .slideY(begin: 0.1);
              }, childCount: groups.length),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 22)),
          SliverToBoxAdapter(
            child: SectionHeader(
              title: context.l10n.homeRecently,
            ).animate().fadeIn(delay: 700.ms),
          ),
          SliverToBoxAdapter(child: SizedBox(height: context.spacing.space4)),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
            sliver: SliverToBoxAdapter(
              key: HomeKeys.activitySection,
              child: activityAsync.when(
                data: (entries) => entries.isEmpty
                    ? Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: context.spacing.space8,
                        ),
                        child: Text(
                          context.l10n.homeNoActivityYet,
                          style: AppTypography.sans(
                            fontSize: 13,
                            color: context.colors.textSecondary,
                          ),
                        ),
                      )
                    : Column(
                        children: entries.take(3).map((entry) {
                          // D-a: category icon leads, no avatar.
                          return ActivityRow(
                            glyph: glyphForGroupActivityType(entry.log.type),
                            actorName: entry.log.actorName,
                            description: localizedGroupActivityText(
                              context.l10n,
                              entry.log,
                            ),
                            timestamp: entry.log.timestamp,
                            groupName: entry.groupName,
                            // #852: per-type deep-link, same table as the
                            // History tab (activity_nav.dart).
                            onTap: () => context.push(
                              activityRowTarget(
                                groupId: entry.groupId,
                                log: entry.log,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
            ),
          ),
          // #1166: the FAB-lane clearance lives HERE now — a trailing
          // in-scroll spacer — not on an outer Padding around the viewport.
          // #1078's outer Padding shrank the CustomScrollView itself, and a
          // Viewport clips its children to its own bounds: that made the
          // reserved 88px a permanent clip line 88px above the true screen
          // edge. Invisible at rest (bottomNavBackground == scaffoldBackground)
          // but reading as an opaque bar swallowing content while scrolling —
          // and amplifying the "FAB looks attached to the nav" illusion this
          // lane was supposed to prevent. A trailing spacer still delivers
          // #1078's guarantee once the list is scrolled fully into view (the
          // last row then sits kHomeFabLaneClearance above the true bottom
          // edge, clear of the FAB); the one accepted trade-off is a SHORT
          // list (shorter than the viewport) where the FAB may rest over the
          // last row — ordinary floating-FAB-over-content behaviour, not the
          // reported occluding-shelf bug.
          const SliverToBoxAdapter(
            child: SizedBox(height: kHomeFabLaneClearance),
          ),
        ],
      ),
    );
  }

  String _firstName() {
    final raw = ref.watch(settingsProvider.select((s) => s.deviceName));
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return context.l10n.homeTravellerFallback;
    return trimmed.split(RegExp(r'\s+')).first;
  }

  // ──────────────── States ────────────────

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(context.spacing.space32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(
                    context.spacing.radiusLarge,
                  ),
                ),
                child: Icon(
                  Iconsax.people,
                  size: 48,
                  color: context.colors.primary,
                ),
              ),
              SizedBox(height: context.spacing.space20),
              Text(
                context.l10n.homeStartFirstGroup,
                style: AppTypography.sans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: context.spacing.space8),
              Text(
                context.l10n.homeStartFirstGroupBody,
                style: AppTypography.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: context.colors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: context.spacing.space24),
              SizedBox(
                width: double.infinity,
                height: context.spacing.buttonHeight,
                child: ElevatedButton.icon(
                  key: HomeKeys.createGroupFab,
                  onPressed: () => context.push('/create-group'),
                  icon: const Icon(Iconsax.add),
                  label: Text(context.l10n.homeCreateGroup),
                ),
              ),
              SizedBox(height: context.spacing.space12),
              SizedBox(
                width: double.infinity,
                height: context.spacing.buttonHeight,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/join-group'),
                  icon: const Icon(Iconsax.login_1),
                  label: Text(context.l10n.homeJoinGroup),
                ),
              ),
              SizedBox(height: context.spacing.space20),
              // #818 Wave 4.2: frames the two restore CTAs below — otherwise
              // they float with no context ("Restore *what*?" on a fresh
              // install). Copy-only; the buttons/keys/gating are untouched.
              Text(
                context.l10n.homeRestoreSectionCaption.toUpperCase(),
                textAlign: TextAlign.center,
                style: AppTypography.caption(
                  context,
                  fontSize: 10.5,
                  color: context.colors.textSecondary,
                  letterSpacing: 1.7,
                ),
              ),
              SizedBox(height: context.spacing.space8),
              if (defaultTargetPlatform == TargetPlatform.iOS)
                TextButton(
                  key: const Key('home_empty_recover_apple_cta'),
                  // #1256: same discard-shell contract as the Google CTA
                  // below — the swap self-gates via outgoingShellProvablyEmpty;
                  // visibility is not the safety boundary (#648). Rendered
                  // ABOVE Google per the 4.8 parity requirement.
                  onPressed: () => triggerAppleRestore(context, ref),
                  child: Text(
                    context.l10n.homeRestoreWithApple,
                    style: AppTypography.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
              TextButton(
                key: const Key('home_empty_recover_cta'),
                // #441 PR3 / #648: cross-UID Google restore (discard-shell
                // swap), not a route push. The empty state can FALSE-EMPTY on
                // the cold-start firebaseUserProvider race, so the CTA's
                // visibility is NOT the safety boundary — triggerGoogleRestore
                // re-verifies a provably-empty shell before swapping (#648).
                onPressed: () => triggerGoogleRestore(context, ref),
                child: Text(
                  context.l10n.homeRestoreWithGoogle,
                  style: AppTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
              TextButton(
                key: const Key('home_empty_recover_email_cta'),
                // #441 PR4: slim email fallback (D3). This only routes to
                // /recover; the actual cross-UID swap is the #647-guarded
                // bootstrap (restoreWithEmailLink runs only after the
                // empty-shell gate), so CTA visibility here isn't load-bearing.
                onPressed: () => context.push('/recover'),
                child: Text(
                  context.l10n.homeRestoreWithEmail,
                  style: AppTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Column(
      children: [
        const OfflineBanner(),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: EmptyStateView(
                icon: Iconsax.warning_2,
                title: context.l10n.homeErrorTitle,
                message: context.l10n.homeErrorMessage,
                actionLabel: context.l10n.commonRetry,
                onAction: () => ref.refresh(userGroupsProvider),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    final stubGroups = [
      Group(
        id: 'sk1',
        name: 'Loading group one',
        inviteCode: '',
        createdBy: '',
        memberIds: const ['1', '2', '3'],
        createdAt: DateTime.now(),
      ),
      Group(
        id: 'sk2',
        name: 'Loading group two',
        inviteCode: '',
        createdBy: '',
        memberIds: const ['1', '2'],
        createdAt: DateTime.now(),
      ),
    ];
    return Skeletonizer(
      enabled: true,
      containersColor: context.colors.cardSoft,
      child: IgnorePointer(
        child: _buildLoaded(context, stubGroups, isPlaceholder: true),
      ),
    );
  }

  // ──────────────── Sheets ────────────────

  void _showCreateOrJoinSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.spacing.radiusSheet),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: HomeKeys.createGroupOption,
              contentPadding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
              minTileHeight: 64,
              leading: Icon(Iconsax.people, color: context.colors.primary),
              title: Text(
                context.l10n.homeCreateAGroup,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/create-group');
              },
            ),
            ListTile(
              key: HomeKeys.joinGroupOption,
              contentPadding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
              minTileHeight: 64,
              leading: Icon(
                Iconsax.login_1,
                color: context.colors.textSecondary,
              ),
              title: Text(
                context.l10n.homeJoinAGroup,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/join-group');
              },
            ),
          ],
        ),
      ),
    );
  }
}
