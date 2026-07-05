import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../features/events/models/event_model.dart';
import '../../features/events/screens/create_event_screen.dart';
import '../../features/events/screens/event_command_center.dart';
import '../../features/events/screens/event_recap_screen.dart';
import '../../features/events/screens/event_settings_screen.dart';
import '../../features/groups/screens/create_group_screen.dart';
import '../../features/groups/screens/group_activity_screen.dart';
import '../../features/groups/screens/group_detail_screen.dart';
import '../../features/groups/screens/group_settings_screen.dart';
import '../../features/groups/screens/group_settle_up_screen.dart';
import '../../features/groups/screens/join_group_screen.dart';
import '../../features/home/screens/cross_group_activity_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/ledger/screens/add_expense_screen.dart';
import '../../features/ledger/screens/edit_expense_screen.dart';
import '../../features/ledger/screens/ledger_screen.dart';
import '../../features/ledger/screens/settle_up_screen.dart';
import '../../features/activity/screens/activity_feed_screen.dart';
import '../../features/search/screens/search_screen.dart';
import '../../features/auth/screens/link_email_screen.dart';
import '../../features/auth/screens/link_email_sent_screen.dart';
import '../../features/auth/screens/recover_pending_screen.dart';
import '../../features/auth/screens/recover_screen.dart';
import '../../features/settings/screens/profile_screen.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../extensions/build_context_l10n.dart';
import '../screens/splash_screen.dart';
import '../theme/tokens/domain_aliases.dart';

/// Route names for type-safe navigation
class AppRoutes {
  static const String splash = '/';
  static const String home = '/home';
  static const String profile = '/profile';
  // Account recovery (P3 + P4)
  static const String linkEmail = '/profile/link-email';
  static const String linkEmailSent = '/profile/link-email/sent';
  static const String recover = '/recover';
  static const String recoverPending = '/recover/pending';
  // Groups routes (Phase 2)
  static const String createGroup = '/create-group';
  static const String joinGroup = '/join-group';
  static const String joinInvite = '/join/:code';
  static const String groupDetail = '/group/:gid';
  static const String groupSettings = '/group/:gid/settings';
  // Group-level routes (Phase 19)
  static const String groupSettleUp = '/group/:gid/settle-up';
  static const String groupActivity = '/group/:gid/activity';
  static const String createEvent = '/group/:gid/create-event';
  static const String createEventTyped = '/group/:gid/create-event/:type';
  // Event hub and module routes (Phase 19)
  static const String eventHub = '/group/:gid/event/:eid';
  static const String eventLedger = '/group/:gid/event/:eid/ledger';
  static const String eventLedgerAdd = '/group/:gid/event/:eid/ledger/add';
  static const String eventLedgerEdit =
      '/group/:gid/event/:eid/ledger/edit/:expId';
  static const String eventLedgerSettleUp =
      '/group/:gid/event/:eid/ledger/settle-up';
  static const String eventActivity = '/group/:gid/event/:eid/activity';
  static const String eventSettings = '/group/:gid/event/:eid/settings';
  static const String eventRecap = '/group/:gid/event/:eid/recap';
  // Cross-group activity (Phase 23)
  static const String activity = '/activity';
  // Global search (#900 friction #3 — PR-5b)
  static const String search = '/search';
}

@visibleForTesting
String? appRouteRedirect(String matchedLocation) {
  if (matchedLocation == AppRoutes.splash) {
    return AppRoutes.home;
  }

  return null;
}

/// Route-level redirect for `AppRoutes.eventLedger` (PR-5 §4): a cold
/// `…/ledger` lands on the hub's Expenses tab instead of the full-chrome
/// route (kept, but unrouted).
///
/// The null-for-children guard is LOAD-BEARING: go_router 13.2.5 runs
/// ancestor route-level redirects for descendant matches too
/// (`_getRouteLevelRedirect` walks the full matched chain from index 0), and
/// `state.uri` is always the FULL matched location (`buildState` passes
/// `matches.uri`) — so without the `endsWith` guard this would also hijack
/// `…/ledger/add`, `…/ledger/edit/:expId`, and `…/ledger/settle-up`.
@visibleForTesting
String? eventLedgerModuleRedirect(GoRouterState state) {
  final loc = state.uri.path;
  if (!loc.endsWith('/ledger')) return null;
  return '${loc.substring(0, loc.length - 7)}?tab=expenses';
}

/// Route-level redirect for `AppRoutes.eventActivity` (PR-5 §4) — same
/// pattern as [eventLedgerModuleRedirect], `…/activity` has no children to
/// guard but keeps the same `endsWith` shape for symmetry.
@visibleForTesting
String? eventActivityModuleRedirect(GoRouterState state) {
  final loc = state.uri.path;
  if (!loc.endsWith('/activity')) return null;
  return '${loc.substring(0, loc.length - 9)}?tab=activity';
}

String _emailFromRouteState(GoRouterState state) {
  return state.uri.queryParameters['email'] ?? '';
}

const double _sharedAxisTravel = 0.08;

@visibleForTesting
Offset sharedAxisEnterOffsetForTextDirection(TextDirection direction) {
  return Offset(
    direction == TextDirection.rtl ? -_sharedAxisTravel : _sharedAxisTravel,
    0,
  );
}

@visibleForTesting
Offset sharedAxisExitOffsetForTextDirection(TextDirection direction) {
  return Offset(
    direction == TextDirection.rtl ? _sharedAxisTravel : -_sharedAxisTravel,
    0,
  );
}

/// Shared axis page transition used by all route-level screens.
///
/// The `animations` package horizontal shared-axis transition is always LTR.
/// This local variant keeps the same fade + horizontal travel pattern while
/// resolving travel direction from the ambient [Directionality].
Widget _sharedAxisTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final textDirection = Directionality.of(context);
  final enterTween = Tween<Offset>(
    begin: sharedAxisEnterOffsetForTextDirection(textDirection),
    end: Offset.zero,
  ).chain(CurveTween(curve: Curves.easeOutCubic));
  final exitTween = Tween<Offset>(
    begin: Offset.zero,
    end: sharedAxisExitOffsetForTextDirection(textDirection),
  ).chain(CurveTween(curve: Curves.easeOutCubic));
  final fade = CurvedAnimation(
    parent: animation,
    curve: const Interval(0.25, 1.0, curve: Curves.easeOut),
    reverseCurve: const Interval(0.0, 0.75, curve: Curves.easeIn),
  );

  return FadeTransition(
    opacity: fade,
    child: SlideTransition(
      position: exitTween.animate(secondaryAnimation),
      child: SlideTransition(
        position: enterTween.animate(animation),
        child: child,
      ),
    ),
  );
}

/// Router provider — redirects splash to `/home`.
///
/// The shippable v1 surface intentionally keeps onboarding out of the route
/// tree so invite links and recovery links cannot be blocked on first launch.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    // Restores the matched route's page subtree after Android process death so
    // the scrollables' `restorationId`s actually take effect. This is a
    // config flag only — it does not alter the route tree or back-guards (#362).
    restorationScopeId: 'router',
    debugLogDiagnostics: kDebugMode,
    redirect: (context, state) => appRouteRedirect(state.matchedLocation),
    routes: [
      // Splash - auto-redirects to /home
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),

      // Home / Trip List
      GoRoute(
        path: AppRoutes.home,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const HomeScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),

      // Create Group (Phase 2)
      GoRoute(
        path: AppRoutes.createGroup,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const CreateGroupScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            );
          },
        ),
      ),

      // Join Group (Phase 2)
      GoRoute(
        path: AppRoutes.joinGroup,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const JoinGroupScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            );
          },
        ),
      ),

      GoRoute(
        path: AppRoutes.joinInvite,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: JoinGroupScreen(
            initialInviteCode: state.pathParameters['code'],
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            );
          },
        ),
      ),

      // Group Detail (Phase 2 — Plan 03)
      GoRoute(
        path: AppRoutes.groupDetail,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: GroupDetailScreen(groupId: state.pathParameters['gid']!),
          transitionsBuilder: _sharedAxisTransition,
        ),
        routes: [
          GoRoute(
            path: 'settings',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: GroupSettingsScreen(groupId: state.pathParameters['gid']!),
              transitionsBuilder: _sharedAxisTransition,
            ),
          ),

          // Group settle-up
          GoRoute(
            path: 'settle-up',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: GroupSettleUpScreen(
                groupId: state.pathParameters['gid']!,
                preSelectedMemberId: state.uri.queryParameters['memberId'],
              ),
              transitionsBuilder: _sharedAxisTransition,
            ),
          ),

          // Group activity
          GoRoute(
            path: 'activity',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: GroupActivityScreen(groupId: state.pathParameters['gid']!),
              transitionsBuilder: _sharedAxisTransition,
            ),
          ),

          // Create event — folded form (type is a chip-row; #489)
          GoRoute(
            path: 'create-event',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: CreateEventScreen(
                groupId: state.pathParameters['gid']!,
                initialEventType: EventType.trip,
              ),
              transitionsBuilder: _sharedAxisTransition,
            ),
          ),

          // Create event — typed deep link (type pre-selected; folded form, #489)
          GoRoute(
            path: 'create-event/:type',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: CreateEventScreen(
                groupId: state.pathParameters['gid']!,
                initialEventType: EventType.fromString(
                  state.pathParameters['type'] ?? 'custom',
                ),
              ),
              transitionsBuilder: _sharedAxisTransition,
            ),
          ),

          // Event hub
          GoRoute(
            path: 'event/:eid',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: EventCommandCenter(
                groupId: state.pathParameters['gid']!,
                eventId: state.pathParameters['eid']!,
                initialTab: EventTab.fromQuery(
                  state.uri.queryParameters['tab'],
                ),
              ),
              transitionsBuilder: _sharedAxisTransition,
            ),
            routes: [
              // Ledger module — PR-5 §4: route-level redirect into the hub's
              // Expenses tab. The pageBuilder below is KEPT (full-chrome
              // screen stays alive for its ~12 direct widget tests) but is
              // unrouted in practice: the redirect fires for every exact
              // `…/ledger` match, before the builder ever runs.
              GoRoute(
                path: 'ledger',
                redirect: (context, state) =>
                    eventLedgerModuleRedirect(state),
                pageBuilder: (context, state) => CustomTransitionPage(
                  key: state.pageKey,
                  child: LedgerScreen(
                    groupId: state.pathParameters['gid']!,
                    eventId: state.pathParameters['eid']!,
                  ),
                  transitionsBuilder: _sharedAxisTransition,
                ),
                routes: [
                  GoRoute(
                    path: 'add',
                    pageBuilder: (context, state) => CustomTransitionPage(
                      key: state.pageKey,
                      child: AddExpenseScreen(
                        groupId: state.pathParameters['gid']!,
                        eventId: state.pathParameters['eid']!,
                      ),
                      transitionsBuilder: _sharedAxisTransition,
                    ),
                  ),
                  GoRoute(
                    path: 'edit/:expId',
                    pageBuilder: (context, state) => CustomTransitionPage(
                      key: state.pageKey,
                      child: EditExpenseScreen(
                        groupId: state.pathParameters['gid']!,
                        eventId: state.pathParameters['eid']!,
                        expenseId: state.pathParameters['expId']!,
                      ),
                      transitionsBuilder: _sharedAxisTransition,
                    ),
                  ),
                  // Event-level settle-up (GoRouter route per D-07)
                  GoRoute(
                    path: 'settle-up',
                    pageBuilder: (context, state) => CustomTransitionPage(
                      key: state.pageKey,
                      child: SettleUpScreen(
                        groupId: state.pathParameters['gid']!,
                        eventId: state.pathParameters['eid']!,
                        preSelectedMemberId:
                            state.uri.queryParameters['memberId'],
                      ),
                      transitionsBuilder: _sharedAxisTransition,
                    ),
                  ),
                ],
              ),

              // Activity module — PR-5 §4: route-level redirect into the
              // hub's Activity tab. The pageBuilder below is KEPT (full-chrome
              // screen stays alive for its direct widget tests) but is
              // unrouted in practice: the redirect fires for every exact
              // `…/activity` match, before the builder ever runs.
              GoRoute(
                path: 'activity',
                redirect: (context, state) =>
                    eventActivityModuleRedirect(state),
                pageBuilder: (context, state) => CustomTransitionPage(
                  key: state.pageKey,
                  child: ActivityFeedScreen(
                    groupId: state.pathParameters['gid']!,
                    eventId: state.pathParameters['eid']!,
                  ),
                  transitionsBuilder: _sharedAxisTransition,
                ),
              ),

              // Event settings (Phase 31 P02)
              GoRoute(
                path: 'settings',
                pageBuilder: (context, state) => CustomTransitionPage(
                  key: state.pageKey,
                  child: EventSettingsScreen(
                    groupId: state.pathParameters['gid']!,
                    eventId: state.pathParameters['eid']!,
                  ),
                  transitionsBuilder: _sharedAxisTransition,
                ),
              ),

              // Event recap / closeout (#202 Slice 1)
              GoRoute(
                path: 'recap',
                pageBuilder: (context, state) => CustomTransitionPage(
                  key: state.pageKey,
                  child: EventRecapScreen(
                    groupId: state.pathParameters['gid']!,
                    eventId: state.pathParameters['eid']!,
                  ),
                  transitionsBuilder: _sharedAxisTransition,
                ),
              ),
            ],
          ),
        ],
      ),

      // Profile (Phase 25)
      GoRoute(
        path: AppRoutes.profile,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const ProfileScreen(showBack: true),
          transitionsBuilder: _sharedAxisTransition,
        ),
        routes: [
          // Account recovery — link flow (P3)
          GoRoute(
            path: 'link-email',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const LinkEmailScreen(),
              transitionsBuilder: _sharedAxisTransition,
            ),
            routes: [
              GoRoute(
                path: 'sent',
                pageBuilder: (context, state) {
                  final email = _emailFromRouteState(state);
                  return CustomTransitionPage(
                    key: state.pageKey,
                    child: LinkEmailSentScreen(email: email),
                    transitionsBuilder: _sharedAxisTransition,
                  );
                },
              ),
            ],
          ),
        ],
      ),

      // Cross-group activity (Phase 23)
      GoRoute(
        path: AppRoutes.activity,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          // #666: top-level route entry → render the back affordance with a
          // /home fallback. The bottom-nav tab keeps the showBack:false default.
          child: const CrossGroupActivityScreen(showBack: true),
          transitionsBuilder: _sharedAxisTransition,
        ),
      ),

      // Global search (#900 friction #3 — PR-5b)
      GoRoute(
        path: AppRoutes.search,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: SearchScreen(query: state.uri.queryParameters['q']),
          transitionsBuilder: _sharedAxisTransition,
        ),
      ),

      // Account recovery — restore flow (P4)
      GoRoute(
        path: AppRoutes.recover,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const RecoverScreen(),
          transitionsBuilder: _sharedAxisTransition,
        ),
        routes: [
          GoRoute(
            path: 'pending',
            pageBuilder: (context, state) {
              final email = _emailFromRouteState(state);
              return CustomTransitionPage(
                key: state.pageKey,
                child: RecoverPendingScreen(email: email),
                transitionsBuilder: _sharedAxisTransition,
              );
            },
          ),
        ],
      ),
    ],

    errorBuilder: (context, state) => const RouteNotFoundScreen(),
  );
});

/// Shown by [GoRouter]'s `errorBuilder` when the requested location does not
/// match any registered route — e.g. a broken or expired share link.
///
/// The raw unmatched path (`state.matchedLocation`) is intentionally never
/// surfaced here: it's implementation detail, not something a user landing
/// on a dead link can act on.
@visibleForTesting
class RouteNotFoundScreen extends StatelessWidget {
  const RouteNotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(context.spacing.space24),
            child: EmptyStateView(
              icon: Iconsax.warning_2,
              title: context.l10n.errorPageNotFoundTitle,
              message: context.l10n.errorPageNotFoundBody,
              actionLabel: context.l10n.commonGoHome,
              onAction: () => context.go(AppRoutes.home),
              iconColor: context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
