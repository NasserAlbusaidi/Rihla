import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:animations/animations.dart';
import '../../features/events/models/event_model.dart';
import '../../features/events/screens/create_event_screen.dart';
import '../../features/events/screens/event_command_center.dart';
import '../../features/events/screens/event_settings_screen.dart';
import '../../features/events/screens/event_type_picker_screen.dart';
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
import '../../features/settings/screens/profile_screen.dart';
import '../screens/splash_screen.dart';

/// Route names for type-safe navigation
class AppRoutes {
  static const String splash = '/';
  static const String home = '/home';
  static const String profile = '/profile';
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
  static const String eventActivity = '/group/:gid/event/:eid/activity';
  static const String eventSettings = '/group/:gid/event/:eid/settings';
  // Cross-group activity (Phase 23)
  static const String activity = '/activity';
}

/// Shared axis page transition used by all route-level screens.
///
/// Uses the Material 3 SharedAxisTransition pattern for fluid spatial navigation.
Widget _sharedAxisTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  return SharedAxisTransition(
    animation: animation,
    secondaryAnimation: secondaryAnimation,
    transitionType: SharedAxisTransitionType.horizontal,
    fillColor: Colors.transparent,
    child: child,
  );
}

/// Router provider — splash always redirects to /home (no onboarding).
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: kDebugMode,
    redirect: (context, state) {
      if (state.matchedLocation == AppRoutes.splash) {
        return AppRoutes.home;
      }
      return null;
    },
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

          // Create event — type selector
          GoRoute(
            path: 'create-event',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: EventTypePickerScreen(
                groupId: state.pathParameters['gid']!,
              ),
              transitionsBuilder: _sharedAxisTransition,
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
              ),
              transitionsBuilder: _sharedAxisTransition,
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
                      ),
                      transitionsBuilder: _sharedAxisTransition,
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
            ],
          ),
        ],
      ),

      // Profile (Phase 25)
      GoRoute(
        path: AppRoutes.profile,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const ProfileScreen(),
          transitionsBuilder: _sharedAxisTransition,
        ),
      ),

      // Cross-group activity (Phase 23)
      GoRoute(
        path: AppRoutes.activity,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const CrossGroupActivityScreen(),
          transitionsBuilder: _sharedAxisTransition,
        ),
      ),
    ],

    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.matchedLocation}')),
    ),
  );
});
