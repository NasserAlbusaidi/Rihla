import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shared GoRouter factory for widget tests.
///
/// Registers stub routes matching the app's full route tree (D-02 + D-07)
/// so that `context.push('/group/:gid/event/:eid/ledger')` resolves to a
/// simple Scaffold with identifying text — no real screen constructors needed.
///
/// Usage:
/// ```dart
/// final router = testRouter(initialLocation: '/group/g1/event/e1');
/// await tester.pumpWidget(
///   ProviderScope(
///     overrides: [...],
///     child: MaterialApp.router(routerConfig: router),
///   ),
/// );
/// ```
GoRouter testRouter({
  String initialLocation = '/home',
  List<RouteBase> extraRoutes = const [],
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, _) => const Scaffold(body: Text('Home')),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, _) => const Scaffold(body: Text('Profile')),
      ),
      GoRoute(
        path: '/create-group',
        builder: (context, _) => const Scaffold(body: Text('CreateGroup')),
      ),
      GoRoute(
        path: '/join-group',
        builder: (context, _) => const Scaffold(body: Text('JoinGroup')),
      ),
      GoRoute(
        path: '/group/:gid',
        builder: (_, state) => Scaffold(
          body: Text('GroupDetail:${state.pathParameters['gid']}'),
        ),
        routes: [
          GoRoute(
            path: 'settings',
            builder: (_, state) => Scaffold(
              body: Text('GroupSettings:${state.pathParameters['gid']}'),
            ),
          ),
          GoRoute(
            path: 'settle-up',
            builder: (_, state) => Scaffold(
              body: Text('GroupSettleUp:${state.pathParameters['gid']}'),
            ),
          ),
          GoRoute(
            path: 'activity',
            builder: (_, state) => Scaffold(
              body: Text('GroupActivity:${state.pathParameters['gid']}'),
            ),
          ),
          GoRoute(
            path: 'create-event',
            builder: (_, state) => Scaffold(
              body: Text('CreateEvent:${state.pathParameters['gid']}'),
            ),
          ),
          GoRoute(
            path: 'create-event/:type',
            builder: (_, state) => Scaffold(
              body: Text('CreateEventTyped:${state.pathParameters['type']}'),
            ),
          ),
          GoRoute(
            path: 'event/:eid',
            builder: (_, state) => Scaffold(
              body: Text('EventHub:${state.pathParameters['eid']}'),
            ),
            routes: [
              GoRoute(
                path: 'ledger',
                builder: (_, state) => Scaffold(
                  body: Text('Ledger:${state.pathParameters['eid']}'),
                ),
                routes: [
                  GoRoute(
                    path: 'add',
                    builder: (_, state) => Scaffold(
                      body: Text('AddExpense:${state.pathParameters['eid']}'),
                    ),
                  ),
                  GoRoute(
                    path: 'edit/:expId',
                    builder: (_, state) => Scaffold(
                      body: Text(
                          'EditExpense:${state.pathParameters['expId']}'),
                    ),
                  ),
                  GoRoute(
                    path: 'settle-up',
                    builder: (_, state) => Scaffold(
                      body: Text(
                          'EventSettleUp:${state.pathParameters['eid']}'),
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'gear',
                builder: (_, state) => Scaffold(
                  body: Text('Gear:${state.pathParameters['eid']}'),
                ),
              ),
              GoRoute(
                path: 'logistics',
                builder: (_, state) => Scaffold(
                  body: Text('Logistics:${state.pathParameters['eid']}'),
                ),
              ),
              GoRoute(
                path: 'vault',
                builder: (_, state) => Scaffold(
                  body: Text('Vault:${state.pathParameters['eid']}'),
                ),
              ),
              GoRoute(
                path: 'memories',
                builder: (_, state) => Scaffold(
                  body: Text('Memories:${state.pathParameters['eid']}'),
                ),
                routes: [
                  GoRoute(
                    path: ':memId',
                    builder: (_, state) => Scaffold(
                      body: Text(
                          'MemoryDetail:${state.pathParameters['memId']}'),
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'activity',
                builder: (_, state) => Scaffold(
                  body: Text('EventActivity:${state.pathParameters['eid']}'),
                ),
              ),
            ],
          ),
        ],
      ),
      ...extraRoutes,
    ],
  );
}
