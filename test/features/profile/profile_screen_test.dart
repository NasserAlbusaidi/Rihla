// Widget tests for ProfileScreen — covers IDENT-01, IDENT-02, STATS-01, STATS-02,
// STATS-03. Tests are written first (RED) before implementing the widgets.
// Phase 26 tests cover NOTIF-01, NOTIF-02, INFO-01, INFO-02, INFO-03.

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/config/app_metadata.dart';
import 'package:safar/core/providers/app_bootstrap_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/notification_service.dart';
import 'package:safar/core/services/notification_settings_launcher.dart';
import 'package:safar/features/auth/providers/auth_email_link_bootstrap_provider.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/settings/keys/profile_keys.dart';
import 'package:safar/features/settings/providers/profile_stats_provider.dart';
import 'package:safar/features/settings/screens/profile_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/r_amount.dart';
import 'package:safar/shared/widgets/skeleton_loader.dart';

// ---------------------------------------------------------------------------
// Phase 26 mock classes
// ---------------------------------------------------------------------------

class MockNotificationService extends Mock implements NotificationService {}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

Widget _buildTestApp(
  Widget widget, {
  List<Override> overrides = const [],
  Locale? locale,
}) {
  final router = GoRouter(
    initialLocation: '/profile',
    routes: [GoRoute(path: '/profile', builder: (ctx, state) => widget)],
  );

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      locale: locale,
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

/// Build a [ProfileStats] AsyncValue with the given values.
AsyncValue<ProfileStats> _statsData({
  int groupCount = 0,
  int eventCount = 0,
  List<CurrencySpend> spentByCurrency = const [],
}) => AsyncValue.data((
  groupCount: groupCount,
  eventCount: eventCount,
  spentByCurrency: spentByCurrency,
));

/// Pump the widget tree and advance time enough for all flutter_animate
/// animations to complete (identity section delays up to 200ms; support
/// section delays up to 500ms).
Future<void> _pumpWithAnimations(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump();
}

Finder _textContaining(String value) {
  return find.byWidgetPredicate((widget) {
    if (widget is! Text) return false;
    return (widget.data?.contains(value) ?? false) ||
        (widget.textSpan?.toPlainText().contains(value) ?? false);
  });
}

/// Build overrides for Phase 26 tests. Includes SharedPreferences with
/// a device name, profile stats, notification status, app metadata, and
/// bootstrap no-op.
///
/// settingsProvider uses the REAL SettingsNotifier backed by the mocked
/// SharedPreferences instance. This works because SettingsNotifier reads/writes
/// via SettingsService which delegates to SharedPreferences — the mocked prefs
/// instance intercepts all reads/writes. No settingsProvider override is needed
/// because the sharedPreferencesProvider override propagates through the
/// dependency chain: sharedPreferencesProvider -> SettingsService -> SettingsNotifier.
List<Override> _phase26Overrides({
  SharedPreferences? prefs,
  NotificationStatus notifStatus = NotificationStatus.off,
  bool pushEnabled = false,
  String version = '2.2.0',
  OpenNotificationSettings? openSettings,
  MockNotificationService? notifService,
}) {
  final mockNotifService = notifService ?? MockNotificationService();
  when(mockNotifService.initialize).thenAnswer((_) async => true);
  when(mockNotifService.removeToken).thenAnswer((_) async {});

  return [
    if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
    profileStatsProvider.overrideWith((ref) => _statsData()),
    notificationStatusProvider.overrideWith((ref) => notifStatus),
    notificationServiceProvider.overrideWithValue(mockNotifService),
    if (openSettings != null)
      openNotificationSettingsProvider.overrideWithValue(openSettings),
    appBootstrapProvider.overrideWith((ref) {}),
    appMetadataProvider.overrideWith(
      (ref) => Future.value(
        AppMetadata(
          appName: 'Rihla',
          packageName: 'com.safar.safar',
          version: version,
          buildNumber: '1',
        ),
      ),
    ),
  ];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('profile stats async states (#488)', () {
    Future<void> pumpStats(
      WidgetTester tester, {
      required AsyncValue<ProfileStats> stats,
    }) async {
      SharedPreferences.setMockInitialValues({'settings_device_name': 'Sam'});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: [
            ..._phase26Overrides(prefs: prefs),
            profileStatsProvider.overrideWith((ref) => stats),
            // Durable suppresses the #487 anon back-up card so the stats grid
            // stays near the top, clear of the 800x600 fold.
            isDurableUserProvider.overrideWithValue(true),
            linkedEmailProvider.overrideWithValue('sam@example.com'),
            googleAccountProvider.overrideWithValue(null),
          ],
        ),
      );
    }

    testWidgets('loading shows a skeleton, not em-dashes (#488)', (
      tester,
    ) async {
      await pumpStats(tester, stats: const AsyncValue.loading());
      await _pumpWithAnimations(tester);

      expect(find.byType(SkeletonLoader), findsOneWidget);
      expect(find.text('—'), findsNothing);
    });

    testWidgets('error shows an explicit retry card, not em-dashes (#488)', (
      tester,
    ) async {
      await pumpStats(
        tester,
        stats: AsyncValue.error(Exception('boom'), StackTrace.empty),
      );
      await _pumpWithAnimations(tester);

      expect(find.byKey(ProfileKeys.statsErrorCard), findsOneWidget);
      expect(find.text('—'), findsNothing);
    });
  });

  group('identity hero backup state (#487)', () {
    Future<void> pumpHero(
      WidgetTester tester, {
      required bool durable,
      String? email,
    }) async {
      SharedPreferences.setMockInitialValues({'settings_device_name': 'Sam'});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: [
            ..._phase26Overrides(prefs: prefs),
            isDurableUserProvider.overrideWithValue(durable),
            linkedEmailProvider.overrideWithValue(email),
            googleAccountProvider.overrideWithValue(null),
          ],
        ),
      );
      await _pumpWithAnimations(tester);
    }

    testWidgets('anonymous user → hero shows "Not backed up"', (tester) async {
      await pumpHero(tester, durable: false);
      expect(find.text('Not backed up'), findsOneWidget);
      expect(find.text('Backed up'), findsNothing);
    });

    testWidgets('durable user → hero shows "Backed up"', (tester) async {
      await pumpHero(tester, durable: true, email: 'sam@example.com');
      expect(find.text('Backed up'), findsOneWidget);
      expect(find.text('Not backed up'), findsNothing);
    });

    testWidgets('anonymous user → "Back up this account" card is shown', (
      tester,
    ) async {
      await pumpHero(tester, durable: false);
      expect(find.byKey(ProfileKeys.backupAccountCard), findsOneWidget);
    });

    testWidgets('durable user → back-up card hidden', (tester) async {
      await pumpHero(tester, durable: true, email: 'sam@example.com');
      expect(find.byKey(ProfileKeys.backupAccountCard), findsNothing);
    });
  });

  testWidgets('direct profile back button routes home when showBack is true', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'settings_device_name': 'Alice'});
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/home',
          builder: (ctx, state) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(
          path: '/profile',
          builder: (ctx, state) => const ProfileScreen(showBack: true),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _phase26Overrides(prefs: prefs),
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await _pumpWithAnimations(tester);

    await tester.tap(find.byIcon(Iconsax.arrow_left));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });

  group('ProfileScreen — IDENT-01', () {
    testWidgets('shows display name when set', (tester) async {
      SharedPreferences.setMockInitialValues({'settings_device_name': 'Alice'});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            profileStatsProvider.overrideWith((ref) => _statsData()),
          ],
        ),
      );
      await _pumpWithAnimations(tester);

      expect(find.byKey(ProfileKeys.displayName), findsOneWidget);
      expect(find.text('Alice'), findsWidgets);
    });

    testWidgets('shows "Set your name" prompt when deviceName is empty', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            profileStatsProvider.overrideWith((ref) => _statsData()),
          ],
        ),
      );
      await _pumpWithAnimations(tester);

      expect(find.byKey(ProfileKeys.setNamePrompt), findsOneWidget);
      expect(find.text('Set your name'), findsOneWidget);
    });
  });

  group('ProfileScreen — IDENT handle (#163)', () {
    testWidgets(
      'no-name handle reads as a label, not a cut-off email (no "@traveller")',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        await tester.pumpWidget(
          _buildTestApp(
            const ProfileScreen(),
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              profileStatsProvider.overrideWith((ref) => _statsData()),
            ],
          ),
        );
        await _pumpWithAnimations(tester);

        // The '@traveller' fallback read like a truncated email ('traveller@').
        expect(find.text('@traveller'), findsNothing);
        expect(find.text('no name yet'), findsOneWidget);
      },
    );

    testWidgets('shows the @handle once a name is set', (tester) async {
      SharedPreferences.setMockInitialValues({'settings_device_name': 'Alice'});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            profileStatsProvider.overrideWith((ref) => _statsData()),
          ],
        ),
      );
      await _pumpWithAnimations(tester);

      expect(find.text('@alice'), findsOneWidget);
    });
  });

  group('ProfileScreen — InitialsCircle', () {
    testWidgets('shows correct initials for a single word name', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'settings_device_name': 'Alice'});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            profileStatsProvider.overrideWith((ref) => _statsData()),
          ],
        ),
      );
      await _pumpWithAnimations(tester);

      expect(find.byKey(ProfileKeys.initialsCircle), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
    });
  });

  group('ProfileScreen — IDENT-02', () {
    testWidgets('tapping name row opens edit bottom sheet', (tester) async {
      SharedPreferences.setMockInitialValues({'settings_device_name': 'Alice'});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            profileStatsProvider.overrideWith((ref) => _statsData()),
          ],
        ),
      );
      await _pumpWithAnimations(tester);

      // Tap on the name display row
      await tester.tap(find.byKey(ProfileKeys.displayName));
      await tester.pumpAndSettle();

      // The bottom sheet should show the name text field
      expect(find.byKey(ProfileKeys.nameTextField), findsOneWidget);
    });

    testWidgets('tapping "Set your name" opens edit bottom sheet', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            profileStatsProvider.overrideWith((ref) => _statsData()),
          ],
        ),
      );
      await _pumpWithAnimations(tester);

      await tester.tap(find.byKey(ProfileKeys.setNamePrompt));
      await tester.pumpAndSettle();

      expect(find.byKey(ProfileKeys.nameTextField), findsOneWidget);
    });

    testWidgets('edit name sheet rejects names outside Firestore rules', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'settings_device_name': 'Alice'});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            profileStatsProvider.overrideWith((ref) => _statsData()),
          ],
        ),
      );
      await _pumpWithAnimations(tester);

      await tester.tap(find.byKey(ProfileKeys.displayName));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(ProfileKeys.nameTextField),
        'A' * 33,
      );
      await tester.tap(find.byKey(ProfileKeys.saveNameButton));
      await tester.pump();

      expect(find.text('Keep it to 32 characters or fewer.'), findsOneWidget);
      expect(prefs.getString('settings_device_name'), 'Alice');
    });
  });

  group('ProfileScreen — STATS-01, STATS-02, STATS-03', () {
    testWidgets('shows group count in stat card', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            profileStatsProvider.overrideWith(
              (ref) => _statsData(
                groupCount: 3,
                eventCount: 5,
                spentByCurrency: [(currency: 'OMR', amount: Decimal.parse('42.500'))],
              ),
            ),
          ],
        ),
      );
      await _pumpWithAnimations(tester);

      // STATS-01: group count
      final groupsStat = find.byKey(ProfileKeys.statGroups);
      expect(groupsStat, findsOneWidget);
      expect(
        find.descendant(of: groupsStat, matching: find.text('3')),
        findsOneWidget,
      );
    });

    testWidgets('shows event count in stat card', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            profileStatsProvider.overrideWith(
              (ref) => _statsData(
                groupCount: 3,
                eventCount: 5,
                spentByCurrency: [(currency: 'OMR', amount: Decimal.parse('42.500'))],
              ),
            ),
          ],
        ),
      );
      await _pumpWithAnimations(tester);

      // STATS-02: event count
      final eventsStat = find.byKey(ProfileKeys.statEvents);
      expect(eventsStat, findsOneWidget);
      expect(
        find.descendant(of: eventsStat, matching: find.text('5')),
        findsOneWidget,
      );
    });

    testWidgets('shows formatted total spending in stat card', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            profileStatsProvider.overrideWith(
              (ref) => _statsData(
                groupCount: 3,
                eventCount: 5,
                spentByCurrency: [(currency: 'OMR', amount: Decimal.parse('42.500'))],
              ),
            ),
          ],
        ),
      );
      await _pumpWithAnimations(tester);

      // STATS-03: total spending formatted via AppFormatters
      final spentStat = find.byKey(ProfileKeys.statSpent);
      expect(spentStat, findsOneWidget);
      expect(
        find.descendant(of: spentStat, matching: _textContaining('42.500')),
        findsOneWidget,
      );
    });

    testWidgets(
      'STATS-03 #378: single non-OMR currency renders at its own precision',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        await tester.pumpWidget(
          _buildTestApp(
            const ProfileScreen(),
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              profileStatsProvider.overrideWith(
                (ref) => _statsData(
                  groupCount: 1,
                  eventCount: 2,
                  spentByCurrency: [
                    (currency: 'USD', amount: Decimal.parse('50.00')),
                  ],
                ),
              ),
            ],
          ),
        );
        await _pumpWithAnimations(tester);

        final spentStat = find.byKey(ProfileKeys.statSpent);
        // One amount, USD 2dp (NOT OMR's 3dp), code hidden for a single
        // unambiguous currency.
        final amounts = find.descendant(
          of: spentStat,
          matching: find.byType(RAmount),
        );
        expect(amounts, findsOneWidget);
        expect(tester.widget<RAmount>(amounts).currency, 'USD');
        expect(
          find.descendant(of: spentStat, matching: _textContaining('50.00')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'STATS-03 #378: two currencies render as two lines with codes shown',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        await tester.pumpWidget(
          _buildTestApp(
            const ProfileScreen(),
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              profileStatsProvider.overrideWith(
                (ref) => _statsData(
                  groupCount: 2,
                  eventCount: 4,
                  spentByCurrency: [
                    (currency: 'OMR', amount: Decimal.parse('10.000')),
                    (currency: 'USD', amount: Decimal.parse('20.00')),
                  ],
                ),
              ),
            ],
          ),
        );
        await _pumpWithAnimations(tester);

        final spentStat = find.byKey(ProfileKeys.statSpent);
        // Two RAmounts, both with showCurrency true → both codes visible.
        expect(
          find.descendant(of: spentStat, matching: find.byType(RAmount)),
          findsNWidgets(2),
        );
        expect(
          find.descendant(of: spentStat, matching: _textContaining('OMR')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: spentStat, matching: _textContaining('USD')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'STATS-03 #378: 3+ currencies cap at two lines with a +N overflow',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        await tester.pumpWidget(
          _buildTestApp(
            const ProfileScreen(),
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              profileStatsProvider.overrideWith(
                (ref) => _statsData(
                  groupCount: 3,
                  eventCount: 6,
                  spentByCurrency: [
                    (currency: 'OMR', amount: Decimal.parse('10.000')),
                    (currency: 'USD', amount: Decimal.parse('20.00')),
                    (currency: 'EUR', amount: Decimal.parse('30.00')),
                  ],
                ),
              ),
            ],
          ),
        );
        await _pumpWithAnimations(tester);

        final spentStat = find.byKey(ProfileKeys.statSpent);
        // Capped at two lines, EUR folded behind a "+1" overflow.
        expect(
          find.descendant(of: spentStat, matching: find.byType(RAmount)),
          findsNWidgets(2),
        );
        expect(
          find.descendant(of: spentStat, matching: _textContaining('+1')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: spentStat, matching: _textContaining('EUR')),
          findsNothing,
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Phase 26 tests — notification toggle + info tiles on ProfileScreen
  // ---------------------------------------------------------------------------

  group('ProfileScreen -- NOTIF-01', () {
    testWidgets(
      'shows notification toggle tile in OFF state when pushNotificationsEnabled is false',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'settings_device_name': 'TestUser',
        });
        final prefs = await SharedPreferences.getInstance();

        await tester.pumpWidget(
          _buildTestApp(
            const ProfileScreen(),
            overrides: _phase26Overrides(
              prefs: prefs,
              pushEnabled: false,
              notifStatus: NotificationStatus.off,
            ),
          ),
        );
        await _pumpWithAnimations(tester);

        expect(find.byKey(ProfileKeys.notificationToggleTile), findsOneWidget);
        final switchWidget = tester.widget<Switch>(
          find.byKey(ProfileKeys.notificationSwitch),
        );
        expect(switchWidget.value, isFalse);
      },
    );

    testWidgets(
      'permission-denied ROW tap deep-links to OS settings, never toggling the pref (#470)',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'settings_device_name': 'TestUser',
          'settings_push_notifications': true,
        });
        final prefs = await SharedPreferences.getInstance();

        var openedSettings = 0;
        await tester.pumpWidget(
          _buildTestApp(
            const ProfileScreen(),
            overrides: _phase26Overrides(
              prefs: prefs,
              notifStatus: NotificationStatus.permissionDenied,
              openSettings: () async => openedSettings++,
            ),
          ),
        );
        await _pumpWithAnimations(tester);

        // Hint still points the user at the recovery path.
        expect(find.text('Enable in device Settings'), findsOneWidget);
        // Switch reads OFF (the OS is blocking) — but is no longer a dead control.
        final switchWidget = tester.widget<Switch>(
          find.byKey(ProfileKeys.notificationSwitch),
        );
        expect(switchWidget.value, isFalse);

        await tester.ensureVisible(
          find.byKey(ProfileKeys.notificationToggleTile),
        );
        await tester.tap(find.byKey(ProfileKeys.notificationToggleTile));
        await tester.pumpAndSettle();

        // Tapping deep-links to OS settings, the only Android 13+ recovery path.
        expect(
          openedSettings,
          1,
          reason: 'denied tap must deep-link to OS notification settings',
        );
        // Profile-layer contract: the denied tap routes to settings, NOT through
        // onChanged — so it never flips the pref off. (The bootstrap force-reset
        // guard — that intent survives a denial — lives in
        // app_bootstrap_wiring_test.dart, where the reset code actually runs;
        // here appBootstrapProvider is a no-op stub.)
        expect(prefs.getBool('settings_push_notifications'), isTrue);
      },
    );

    testWidgets(
      'permission-denied SWITCH tap also deep-links to OS settings (#470)',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'settings_device_name': 'TestUser',
          'settings_push_notifications': true,
        });
        final prefs = await SharedPreferences.getInstance();

        var openedSettings = 0;
        await tester.pumpWidget(
          _buildTestApp(
            const ProfileScreen(),
            overrides: _phase26Overrides(
              prefs: prefs,
              notifStatus: NotificationStatus.permissionDenied,
              openSettings: () async => openedSettings++,
            ),
          ),
        );
        await _pumpWithAnimations(tester);

        // The Switch has its own onChanged closure, distinct from the row InkWell;
        // tapping the Switch directly must route to settings, not be a dead control.
        await tester.ensureVisible(find.byKey(ProfileKeys.notificationSwitch));
        await tester.tap(find.byKey(ProfileKeys.notificationSwitch));
        await tester.pumpAndSettle();

        expect(
          openedSettings,
          1,
          reason: 'denied switch tap must also deep-link to OS settings',
        );
        expect(prefs.getBool('settings_push_notifications'), isTrue);
      },
    );

    testWidgets(
      'registration-error state reads OFF with a retry hint, and tapping retries '
      'without flipping the pref (#482)',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'settings_device_name': 'TestUser',
          'settings_push_notifications': true,
        });
        final prefs = await SharedPreferences.getInstance();
        final notif = MockNotificationService();

        await tester.pumpWidget(
          _buildTestApp(
            const ProfileScreen(),
            overrides: _phase26Overrides(
              prefs: prefs,
              pushEnabled: true,
              notifStatus: NotificationStatus.error,
              notifService: notif,
            ),
          ),
        );
        await _pumpWithAnimations(tester);

        // The switch must NOT read a confident ON while delivery is failing.
        final switchWidget = tester.widget<Switch>(
          find.byKey(ProfileKeys.notificationSwitch),
        );
        expect(switchWidget.value, isFalse);
        expect(find.text("Couldn't register — tap to retry"), findsOneWidget);

        // Tapping the switch retries registration instead of toggling the pref.
        await tester.ensureVisible(find.byKey(ProfileKeys.notificationSwitch));
        await tester.tap(find.byKey(ProfileKeys.notificationSwitch));
        await tester.pumpAndSettle();

        verify(notif.initialize).called(1);
        expect(
          prefs.getBool('settings_push_notifications'),
          isTrue,
          reason: 'the error-state tap retries; it must not flip the pref off',
        );
      },
    );
  });

  group('ProfileScreen -- NOTIF-02', () {
    testWidgets('toggling switch ON calls setPushNotificationsEnabled(true)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'TestUser',
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: _phase26Overrides(
            prefs: prefs,
            pushEnabled: false,
            notifStatus: NotificationStatus.off,
          ),
        ),
      );
      await _pumpWithAnimations(tester);

      await tester.ensureVisible(find.byKey(ProfileKeys.notificationSwitch));
      await tester.tap(find.byKey(ProfileKeys.notificationSwitch));
      await tester.pumpAndSettle();

      final switchWidget = tester.widget<Switch>(
        find.byKey(ProfileKeys.notificationSwitch),
      );
      expect(switchWidget.value, isTrue);
    });

    testWidgets(
      'toggling switch OFF calls setPushNotificationsEnabled(false)',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'settings_device_name': 'TestUser',
          'settings_push_notifications': true,
        });
        final prefs = await SharedPreferences.getInstance();

        await tester.pumpWidget(
          _buildTestApp(
            const ProfileScreen(),
            overrides: _phase26Overrides(
              prefs: prefs,
              pushEnabled: true,
              notifStatus: NotificationStatus.enabled,
            ),
          ),
        );
        await _pumpWithAnimations(tester);

        await tester.ensureVisible(find.byKey(ProfileKeys.notificationSwitch));
        await tester.tap(find.byKey(ProfileKeys.notificationSwitch));
        await tester.pumpAndSettle();

        final switchWidget = tester.widget<Switch>(
          find.byKey(ProfileKeys.notificationSwitch),
        );
        expect(switchWidget.value, isFalse);
      },
    );

    testWidgets(
      'non-denied tap toggles the pref and does NOT open OS settings (#470)',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'settings_device_name': 'TestUser',
        });
        final prefs = await SharedPreferences.getInstance();

        var openedSettings = 0;
        await tester.pumpWidget(
          _buildTestApp(
            const ProfileScreen(),
            overrides: _phase26Overrides(
              prefs: prefs,
              notifStatus: NotificationStatus.off,
              openSettings: () async => openedSettings++,
            ),
          ),
        );
        await _pumpWithAnimations(tester);

        await tester.ensureVisible(find.byKey(ProfileKeys.notificationSwitch));
        await tester.tap(find.byKey(ProfileKeys.notificationSwitch));
        await tester.pumpAndSettle();

        // Off/enabled state: the toggle drives intent, never the settings deep-link.
        expect(
          openedSettings,
          0,
          reason: 'a non-denied tap must not open OS settings',
        );
        expect(prefs.getBool('settings_push_notifications'), isTrue);
      },
    );
  });

  group('ProfileScreen -- INFO-01', () {
    testWidgets('shows app version in version tile', (tester) async {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'TestUser',
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: _phase26Overrides(prefs: prefs, version: '2.2.0'),
        ),
      );
      await _pumpWithAnimations(tester);

      expect(find.byKey(ProfileKeys.versionTile), findsOneWidget);
      expect(find.textContaining('v2.2.0'), findsOneWidget);
    });

    testWidgets(
      'footer is an English brand lockup, NOT localized, even under Arabic '
      '(#162 — decision: brand lockup)',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'settings_device_name': 'مستخدم',
        });
        final prefs = await SharedPreferences.getInstance();

        await tester.pumpWidget(
          _buildTestApp(
            const ProfileScreen(),
            overrides: _phase26Overrides(prefs: prefs, version: '2.2.0'),
            locale: const Locale('ar'),
          ),
        );
        await _pumpWithAnimations(tester);

        // The brand lockup stays English on a fully-Arabic screen by design.
        // If a future change localizes the tagline, this fails on purpose —
        // reopen the #162 decision rather than silently flipping it.
        expect(_textContaining('RIHLA'), findsOneWidget);
        expect(_textContaining('BUILT FOR JOURNEYS'), findsOneWidget);
      },
    );
  });

  group('ProfileScreen -- INFO-02', () {
    testWidgets('shows feedback tile', (tester) async {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'TestUser',
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: _phase26Overrides(prefs: prefs),
        ),
      );
      await _pumpWithAnimations(tester);

      expect(find.byKey(ProfileKeys.feedbackTile), findsOneWidget);
      expect(find.text('Send feedback'), findsOneWidget);
    });
  });

  group('ProfileScreen -- INFO-03', () {
    testWidgets('shows licenses tile', (tester) async {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'TestUser',
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: _phase26Overrides(prefs: prefs),
        ),
      );
      await _pumpWithAnimations(tester);

      expect(find.byKey(ProfileKeys.licensesTile), findsOneWidget);
      expect(find.text('Terms & privacy'), findsOneWidget);
    });
  });

  group('ProfileScreen -- pending recovery banner', () {
    testWidgets('hidden when pendingEmailLinkProvider is null', (tester) async {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'TestUser',
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: _phase26Overrides(prefs: prefs),
        ),
      );
      await _pumpWithAnimations(tester);

      expect(find.byKey(ProfileKeys.pendingRecoveryBanner), findsNothing);
      expect(find.text('Finish account recovery'), findsNothing);
    });

    testWidgets('shown when pendingEmailLinkProvider is set', (tester) async {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'TestUser',
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: [
            ..._phase26Overrides(prefs: prefs),
            pendingEmailLinkProvider.overrideWith(
              (ref) => 'https://example.com/__/auth/links?oobCode=ABC',
            ),
          ],
        ),
      );
      await _pumpWithAnimations(tester);

      expect(find.byKey(ProfileKeys.pendingRecoveryBanner), findsOneWidget);
      expect(find.text('Finish account recovery'), findsOneWidget);
    });
  });

  group('ProfileScreen — currency removed (#61 OMR-only)', () {
    testWidgets('preferences show no currency row (Language still present)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'TestUser',
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _buildTestApp(
          const ProfileScreen(),
          overrides: _phase26Overrides(prefs: prefs),
        ),
      );
      await _pumpWithAnimations(tester);

      // 1.0 is OMR-only: the orphaned currency picker was removed (it wrote a
      // preference no write path ever read). The Preferences section still
      // renders — Language proves it — but there is no Currency affordance to
      // promise a non-OMR choice the app can't honour. Guards re-adding it
      // before the multi-currency follow-up solves currency-blind aggregation.
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Currency'), findsNothing);
    });
  });
}
