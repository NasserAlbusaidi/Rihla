import 'package:decimal/decimal.dart';
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
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/wordmark_logo.dart';
import '../../auth/widgets/google_restore_action.dart';
import '../../groups/models/group_model.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../../ledger/providers/expense_provider.dart';
import '../keys/home_keys.dart';
import '../providers/active_journeys_provider.dart';
import '../providers/dashboard_providers.dart';
import '../widgets/account_backup_nudge.dart';
import '../widgets/activity_row.dart';
import '../widgets/balance_hero_card.dart';
import '../widgets/bottom_nav_shell.dart';
import '../widgets/group_glyph.dart';
import '../widgets/journey_ticket_card.dart';

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
  // #284: the balance hero scrolls down to the journeys list (the path to
  // per-group settle-up) — there is no cross-group settle screen to route to.
  final _scrollController = ScrollController();
  final _journeysSectionKey = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToJourneys() {
    HapticService.lightClick();
    final sectionContext = _journeysSectionKey.currentContext;
    if (sectionContext == null) return;
    Scrollable.ensureVisible(
      sectionContext,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(userGroupsProvider);
    return Column(
      children: [
        const _TopBar(),
        Expanded(
          child: groupsAsync.when(
            data: (groups) => groups.isEmpty
                ? _buildEmpty(context)
                : _buildLoaded(context, groups),
            loading: () => _buildSkeleton(context),
            error: (_, _) => _buildError(context),
          ),
        ),
      ],
    );
  }

  // ──────────────── Loaded ────────────────

  Widget _buildLoaded(BuildContext context, List<Group> groups) {
    final activityAsync = ref.watch(crossGroupActivityProvider);
    final journeysAsync = ref.watch(activeJourneysProvider);

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
          SliverToBoxAdapter(child: _GreetingStrip(name: _firstName())),
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
          SliverToBoxAdapter(
            child: BalanceHeroCard(onTap: _scrollToJourneys)
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
                    ? context.l10n.homeSeeAll
                    : null,
                onActionTap: () => context.push('/activity'),
              ).animate().fadeIn(delay: 350.ms),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
          SliverToBoxAdapter(
            child: _JourneysStrip(journeysAsync: journeysAsync),
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
                return _GroupRow(
                      group: groups[index],
                      isLast: isLast,
                      onTap: () {
                        HapticService.lightClick();
                        context.push('/group/${groups[index].id}');
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
                          return ActivityRow(
                            activity: entry.log,
                            groupName: entry.groupName,
                            groupId: entry.groupId,
                            onTap: () =>
                                context.push('/group/${entry.groupId}'),
                          );
                        }).toList(),
                      ),
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
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
              TextButton(
                key: const Key('home_empty_recover_cta'),
                // #441 PR3: cross-UID Google restore (discard-shell swap), not a
                // route push. Safe here — the empty state only renders when the
                // user has zero groups, so the discarded anon shell holds no
                // money data.
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
                // #441 PR4: slim email fallback (D3). Same safety argument as
                // the Google CTA above — empty state ⇒ zero groups ⇒ the
                // discarded anon shell holds no money data.
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
      child: IgnorePointer(child: _buildLoaded(context, stubGroups)),
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

// ──────────────── Top bar ────────────────

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceName = ref.watch(settingsProvider.select((s) => s.deviceName));
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 6, 16, 0),
        child: Row(
          children: [
            GestureDetector(
              key: HomeKeys.profileAvatar,
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticService.lightClick();
                context.push('/profile');
              },
              child: RAvatar(name: deviceName, size: 36),
            ),
            const Spacer(),
            const WordmarkLogo(size: 22),
            const Spacer(),
            _IconCircle(
              icon: Iconsax.notification,
              onTap: () {
                HapticService.lightClick();
                context.push('/activity');
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Ghost-variant icon button used in the home top bar. No background fill —
/// just an icon in a 40×40 tap target. The wireframe shows this as the
/// notifications affordance on the right of the top bar.
class _IconCircle extends StatelessWidget {
  const _IconCircle({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: colors.textPrimary),
        ),
      ),
    );
  }
}

// ──────────────── Greeting strip ────────────────

class _GreetingStrip extends StatelessWidget {
  const _GreetingStrip({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? context.l10n.homeGoodMorning
        : hour < 17
        ? context.l10n.homeGoodAfternoon
        : context.l10n.homeGoodEvening;
    return Padding(
      key: HomeKeys.yourGroupsHeader,
      padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 0),
      child: Text(
        context.l10n.homeGreeting(greeting, name).toUpperCase(),
        style: AppTypography.mono(
          fontSize: 10,
          color: colors.textSecondary,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

// ──────────────── Journeys strip ────────────────

class _JourneysStrip extends StatelessWidget {
  const _JourneysStrip({required this.journeysAsync});
  final AsyncValue<List<ActiveJourneyEntry>> journeysAsync;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return journeysAsync.when(
      data: (entries) {
        if (entries.isEmpty) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
              decoration: BoxDecoration(
                color: colors.cardSoft,
                borderRadius: BorderRadius.circular(context.spacing.radiusCard),
                border: Border.all(color: colors.rule, width: 0.5),
              ),
              child: Row(
                children: [
                  Icon(
                    Iconsax.calendar_1,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.l10n.homeNoUpcomingJourneys,
                      style: AppTypography.sans(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                JourneyTicketCard(
                  entry: entries[i],
                  onTap: () => context.push(
                    '/group/${entries[i].groupId}/event/${entries[i].eventId}',
                  ),
                ),
                if (i < entries.length - 1)
                  SizedBox(width: context.spacing.space12),
              ],
            ],
          ),
        );
      },
      loading: () => SizedBox(
        height: 200,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
          child: Container(
            decoration: BoxDecoration(
              color: colors.cardSoft,
              borderRadius: BorderRadius.circular(context.spacing.radiusCard),
            ),
          ),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

// ──────────────── Group row ────────────────

class _GroupRow extends ConsumerWidget {
  const _GroupRow({
    required this.group,
    required this.onTap,
    required this.isLast,
  });

  final Group group;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    // #366: source-agnostic facade — the server aggregate when online, the
    // #104 once-path otherwise. The facade slices by the current uid itself.
    final balanceAsync = ref.watch(homeGroupBalanceProvider(group.id));
    final homeBalance = balanceAsync.valueOrNull;
    // Every non-zero bucket renders as its own line, GCC-first, each labeled
    // with its own currency (honest — D11). Settled ⇔ every bucket zero or
    // the map is empty (D10).
    final lines = nonZeroNetsGccFirst(
      homeBalance?.userNet ?? const <String, Decimal>{},
    );
    final eventCount = homeBalance?.eventCount ?? 0;
    final memberCount = group.memberIds.length;
    final subtitle = context.l10n.homeGroupSubtitle(memberCount, eventCount);
    final allPositive =
        lines.isNotEmpty && lines.every((l) => l.net > Decimal.zero);
    final allNegative =
        lines.isNotEmpty && lines.every((l) => l.net < Decimal.zero);
    // L7: tri-state caption only when all non-zero lines share one sign;
    // mixed signs → omitted (signed, toned amounts self-explain).
    final String? balanceCaption = lines.isEmpty
        ? context.l10n.homeSettled
        : allPositive
        ? context.l10n.homeTheyOweYou
        : allNegative
        ? context.l10n.homeYouOwe
        : null;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GroupGlyph(name: group.name),
                SizedBox(width: context.spacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTypography.sans(
                          fontSize: 12,
                          color: colors.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (lines.isEmpty)
                      RAmount(
                        value: Decimal.zero,
                        currency: group.currency,
                        size: 16,
                      )
                    else
                      for (var i = 0; i < lines.length; i++)
                        Padding(
                          padding: EdgeInsetsDirectional.only(
                            top: i == 0 ? 0 : 2,
                          ),
                          child: RAmount(
                            value: lines[i].net,
                            currency: lines[i].currency,
                            size: lines.length == 1 ? 16 : 14,
                            sign: true,
                          ),
                        ),
                    if (balanceCaption != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        balanceCaption,
                        style: AppTypography.sans(
                          fontSize: 11,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            if (!isLast) ...[
              const SizedBox(height: 14),
              Container(height: 0.5, color: colors.rule),
            ],
          ],
        ),
      ),
    );
  }
}
