// Friction audit: the SUPPORT section was "wired but unbuilt" — AppLinks
// carried the PayPal URL, ProfileKeys.coffeeTile and all three l10n keys
// existed, but no widget rendered them. These tests pin the widget AND its
// mount on ProfileScreen, so it can't silently unmount again.

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safar/core/config/app_links.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/settings/keys/profile_keys.dart';
import 'package:safar/features/settings/providers/profile_stats_provider.dart'
    as profile_stats;
import 'package:safar/features/settings/screens/profile_screen.dart';
import 'package:safar/features/settings/widgets/profile_support_section.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockRecoveryService extends Mock implements AuthRecoveryService {}

class _MockUser extends Mock implements firebase_auth.User {}

void main() {
  const urlChannel = MethodChannel('plugins.flutter.io/url_launcher');
  final launched = <Map<dynamic, dynamic>>[];
  var launchResult = true;

  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  setUp(() {
    launched.clear();
    launchResult = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlChannel, (call) async {
          if (call.method == 'canLaunch' || call.method == 'launch') {
            launched.add(Map<dynamic, dynamic>.from(call.arguments as Map));
            return launchResult;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(urlChannel, null);
  });

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: ProfileSupportSection()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the SUPPORT header and the coffee tile', (tester) async {
    await pumpSection(tester);

    expect(find.text('SUPPORT'), findsOneWidget);
    expect(find.text('Buy me a coffee'), findsOneWidget);
    expect(find.byKey(ProfileKeys.coffeeTile), findsOneWidget);
  });

  testWidgets('tapping the tile launches the PayPal donate URL', (
    tester,
  ) async {
    await pumpSection(tester);

    await tester.tap(find.byKey(ProfileKeys.coffeeTile));
    await tester.pumpAndSettle();

    expect(launched, isNotEmpty);
    expect(launched.last['url'], AppLinks.paypalUrl);
  });

  testWidgets('a failed launch surfaces the PayPal-failed snack', (
    tester,
  ) async {
    launchResult = false;
    await pumpSection(tester);

    await tester.tap(find.byKey(ProfileKeys.coffeeTile));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't open PayPal"), findsOneWidget);
  });

  testWidgets('ProfileScreen mounts the support section', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings_device_name': 'Test User',
    });
    final prefs = await SharedPreferences.getInstance();
    final user = _MockUser();
    when(() => user.uid).thenReturn('anon-1');
    when(() => user.email).thenReturn(null);
    when(() => user.isAnonymous).thenReturn(true);
    when(() => user.providerData).thenReturn(const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authRecoveryServiceProvider.overrideWithValue(
            _MockRecoveryService(),
          ),
          authUserChangesProvider.overrideWith(
            (ref) => Stream<firebase_auth.User?>.value(user),
          ),
          firebaseUserProvider.overrideWith(
            (ref) => Stream<firebase_auth.User?>.value(user),
          ),
          userGroupsProvider.overrideWith(
            (ref) => Stream.value(const <Group>[]),
          ),
          profile_stats.profileStatsProvider.overrideWith(
            (ref) => const AsyncValue<profile_stats.ProfileStats>.data(
              (
                groupCount: 0,
                eventCount: 0,
                spentByCurrency: <profile_stats.CurrencySpend>[],
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(ProfileKeys.coffeeTile), findsOneWidget);
  });
}
