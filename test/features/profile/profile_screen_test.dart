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
import 'package:safar/features/auth/providers/auth_email_link_bootstrap_provider.dart';
import 'package:safar/features/settings/keys/profile_keys.dart';
import 'package:safar/features/settings/providers/profile_stats_provider.dart';
import 'package:safar/features/settings/screens/profile_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Phase 26 mock classes
// ---------------------------------------------------------------------------

class MockNotificationService extends Mock implements NotificationService {}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

Widget _buildTestApp(Widget widget, {List<Override> overrides = const []}) {
  final router = GoRouter(
    initialLocation: '/profile',
    routes: [GoRoute(path: '/profile', builder: (ctx, state) => widget)],
  );

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
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
  Decimal? totalSpent,
}) => AsyncValue.data((
  groupCount: groupCount,
  eventCount: eventCount,
  totalSpent: totalSpent ?? Decimal.zero,
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
}) {
  final mockNotifService = MockNotificationService();
  when(mockNotifService.initialize).thenAnswer((_) async => true);
  when(mockNotifService.removeToken).thenAnswer((_) async {});
  when(() => mockNotifService.isInitialized).thenReturn(false);

  return [
    if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
    profileStatsProvider.overrideWith((ref) => _statsData()),
    notificationStatusProvider.overrideWith((ref) => notifStatus),
    notificationServiceProvider.overrideWithValue(mockNotifService),
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
                totalSpent: Decimal.parse('42.500'),
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
                totalSpent: Decimal.parse('42.500'),
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
                totalSpent: Decimal.parse('42.500'),
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
  });

  // ---------------------------------------------------------------------------
  // Phase 26 tests — TDD RED phase
  // These tests assert on widgets that do not exist yet. They will fail until
  // Plan 01 (Wave 2) adds ProfileNotificationsSection, ProfileAboutSection,
  // and ProfileSupportSection to ProfileScreen.
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
      'shows notification toggle in disabled state with subtitle when permission denied',
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
              notifStatus: NotificationStatus.permissionDenied,
            ),
          ),
        );
        await _pumpWithAnimations(tester);

        expect(find.text('Enable in device Settings'), findsOneWidget);
        final switchWidget = tester.widget<Switch>(
          find.byKey(ProfileKeys.notificationSwitch),
        );
        expect(switchWidget.onChanged, isNull);
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

        await tester.tap(find.byKey(ProfileKeys.notificationSwitch));
        await tester.pumpAndSettle();

        final switchWidget = tester.widget<Switch>(
          find.byKey(ProfileKeys.notificationSwitch),
        );
        expect(switchWidget.value, isFalse);
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
}
