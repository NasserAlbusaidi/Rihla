import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';

import '../../features/events/models/event_model.dart';
import '../../features/events/screens/create_event_screen.dart';
import '../../features/events/screens/event_command_center.dart';
import '../../features/events/screens/event_type_picker_screen.dart';
import '../../features/gear/screens/gear_screen.dart';
import '../../features/groups/screens/create_group_screen.dart';
import '../../features/groups/screens/group_activity_screen.dart';
import '../../features/groups/screens/group_detail_screen.dart';
import '../../features/groups/screens/group_settings_screen.dart';
import '../../features/groups/screens/group_settle_up_screen.dart';
import '../../features/groups/screens/join_group_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/ledger/screens/add_expense_screen.dart';
import '../../features/ledger/screens/edit_expense_screen.dart';
import '../../features/ledger/screens/ledger_screen.dart';
import '../../features/ledger/screens/settle_up_screen.dart';
import '../../features/logistics/screens/logistics_screen.dart';
import '../../features/activity/screens/activity_feed_screen.dart';
import '../../features/memories/screens/memories_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/vault/screens/vault_screen.dart';

/// Route names for type-safe navigation
class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String home = '/home';
  static const String settings = '/settings';
  // Groups routes (Phase 2)
  static const String createGroup = '/create-group';
  static const String joinGroup = '/join-group';
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
  static const String eventGear = '/group/:gid/event/:eid/gear';
  static const String eventLogistics = '/group/:gid/event/:eid/logistics';
  static const String eventVault = '/group/:gid/event/:eid/vault';
  static const String eventMemories = '/group/:gid/event/:eid/memories';
  static const String eventMemoryDetail =
      '/group/:gid/event/:eid/memories/:memId';
  static const String eventActivity = '/group/:gid/event/:eid/activity';
}

/// Shared slide-right page transition used by all route-level screens.
///
/// Slides from Offset(1,0) → zero with Curves.easeOutCubic.
Widget _slideRightTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  return SlideTransition(
    position: Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
    child: child,
  );
}

/// Provider to track onboarding completion state
final onboardingCompleteProvider = FutureProvider<bool>((ref) async {
  return await OnboardingScreen.isCompleted();
});

/// Router provider with onboarding-aware redirects
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: kDebugMode,
    redirect: (context, state) {
      final isSplash = state.matchedLocation == AppRoutes.splash;
      final isOnboarding = state.matchedLocation == AppRoutes.onboarding;
      final onboardingDone =
          ref.read(onboardingCompleteProvider).valueOrNull ?? false;

      // If on splash, redirect based on onboarding state
      if (isSplash) {
        return onboardingDone ? AppRoutes.home : AppRoutes.onboarding;
      }

      // Allow onboarding screen
      if (isOnboarding) return null;

      return null;
    },
    routes: [
      // Splash - auto-redirects based on onboarding
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const _SplashScreen(),
      ),

      // Onboarding
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const OnboardingScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
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
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
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
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
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
          transitionsBuilder: _slideRightTransition,
        ),
        routes: [
          GoRoute(
            path: 'settings',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child:
                  GroupSettingsScreen(groupId: state.pathParameters['gid']!),
              transitionsBuilder: _slideRightTransition,
            ),
          ),

          // Group settle-up
          GoRoute(
            path: 'settle-up',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: GroupSettleUpScreen(
                groupId: state.pathParameters['gid']!,
                preSelectedMemberId:
                    state.uri.queryParameters['memberId'],
              ),
              transitionsBuilder: _slideRightTransition,
            ),
          ),

          // Group activity
          GoRoute(
            path: 'activity',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: GroupActivityScreen(
                groupId: state.pathParameters['gid']!,
              ),
              transitionsBuilder: _slideRightTransition,
            ),
          ),

          // Create event — type selector
          GoRoute(
            path: 'create-event',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: EventTypePickerScreen(
                groupId: state.pathParameters['gid']!,
              ),
              transitionsBuilder: _slideRightTransition,
            ),
          ),

          // Create event — typed (EventType parsed from path param)
          GoRoute(
            path: 'create-event/:type',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: CreateEventScreen(
                groupId: state.pathParameters['gid']!,
                eventType: EventType.fromString(
                  state.pathParameters['type'] ?? 'custom',
                ),
              ),
              transitionsBuilder: _slideRightTransition,
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
              ),
              transitionsBuilder: _slideRightTransition,
            ),
            routes: [
              // Ledger module
              GoRoute(
                path: 'ledger',
                pageBuilder: (context, state) => CustomTransitionPage(
                  key: state.pageKey,
                  child: LedgerScreen(
                    groupId: state.pathParameters['gid']!,
                    eventId: state.pathParameters['eid']!,
                  ),
                  transitionsBuilder: _slideRightTransition,
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
                      transitionsBuilder: _slideRightTransition,
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
                      transitionsBuilder: _slideRightTransition,
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
                      ),
                      transitionsBuilder: _slideRightTransition,
                    ),
                  ),
                ],
              ),

              // Gear module
              GoRoute(
                path: 'gear',
                pageBuilder: (context, state) => CustomTransitionPage(
                  key: state.pageKey,
                  child: GearScreen(
                    groupId: state.pathParameters['gid']!,
                    eventId: state.pathParameters['eid']!,
                  ),
                  transitionsBuilder: _slideRightTransition,
                ),
              ),

              // Logistics module
              GoRoute(
                path: 'logistics',
                pageBuilder: (context, state) => CustomTransitionPage(
                  key: state.pageKey,
                  child: LogisticsScreen(
                    groupId: state.pathParameters['gid']!,
                    eventId: state.pathParameters['eid']!,
                  ),
                  transitionsBuilder: _slideRightTransition,
                ),
              ),

              // Vault module
              GoRoute(
                path: 'vault',
                pageBuilder: (context, state) => CustomTransitionPage(
                  key: state.pageKey,
                  child: VaultScreen(
                    groupId: state.pathParameters['gid']!,
                    eventId: state.pathParameters['eid']!,
                  ),
                  transitionsBuilder: _slideRightTransition,
                ),
              ),

              // Memories module
              GoRoute(
                path: 'memories',
                pageBuilder: (context, state) => CustomTransitionPage(
                  key: state.pageKey,
                  child: MemoriesScreen(
                    groupId: state.pathParameters['gid']!,
                    eventId: state.pathParameters['eid']!,
                  ),
                  transitionsBuilder: _slideRightTransition,
                ),
                routes: [
                  // Memory detail — Plan 03 scope (no MemoryDetailScreen yet)
                  GoRoute(
                    path: ':memId',
                    pageBuilder: (context, state) => CustomTransitionPage(
                      key: state.pageKey,
                      child: Scaffold(
                        body: Center(
                          child: Text(
                              'MemoryDetail:${state.pathParameters['memId']}'),
                        ),
                      ),
                      transitionsBuilder: _slideRightTransition,
                    ),
                  ),
                ],
              ),

              // Activity module
              GoRoute(
                path: 'activity',
                pageBuilder: (context, state) => CustomTransitionPage(
                  key: state.pageKey,
                  child: ActivityFeedScreen(
                    groupId: state.pathParameters['gid']!,
                    eventId: state.pathParameters['eid']!,
                  ),
                  transitionsBuilder: _slideRightTransition,
                ),
              ),
            ],
          ),
        ],
      ),

      // Settings
      GoRoute(
        path: AppRoutes.settings,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SettingsScreen(),
          transitionsBuilder: _slideRightTransition,
        ),
      ),
    ],

    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.matchedLocation}')),
    ),
  );
});

/// Splash screen that auto-redirects -- branded loading
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDark,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withAlpha(100),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(Icons.explore_rounded, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 24),
            const Text(
              'Rihla',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 40),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
