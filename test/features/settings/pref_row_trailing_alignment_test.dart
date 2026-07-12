// QA-BUG-02 (#1184): Profile → PREFERENCES rows that carry a `trailingText:`
// (Language, Default split) rendered their value in the horizontal MIDDLE of
// the row instead of pinned to the trailing edge, because the value Text was
// wrapped in a bare `Flexible` (flex:1, loose) competing 50/50 with the
// `Expanded(label)` (flex:1). The loose Flexible sizes to the short value and
// is positioned right after the label's half — i.e. the row's centre.
//
// These tests measure geometry (position, not existence): the trailing value's
// trailing edge must sit within a couple px of the row's trailing edge, in both
// LTR (right edge) and RTL (left edge, proving the AlignmentDirectional mirror).

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/providers/shell_emptiness_gate.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/settings/providers/profile_stats_provider.dart'
    as profile_stats;
import 'package:safar/features/settings/screens/profile_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockRecoveryService extends Mock implements AuthRecoveryService {}

class _MockUser extends Mock implements firebase_auth.User {}

firebase_auth.User _anonUser() {
  final u = _MockUser();
  when(() => u.uid).thenReturn('anon-1');
  when(() => u.email).thenReturn(null);
  when(() => u.isAnonymous).thenReturn(true);
  when(() => u.providerData).thenReturn(const []);
  return u;
}

Future<Widget> _wrap({
  required _MockRecoveryService service,
  required String languageCode,
  required Locale locale,
}) async {
  SharedPreferences.setMockInitialValues({
    'settings_device_name': 'Test User',
    'settings_language': languageCode,
  });
  final prefs = await SharedPreferences.getInstance();

  final user = _anonUser();

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authRecoveryServiceProvider.overrideWithValue(service),
      authUserChangesProvider.overrideWith(
        (ref) => Stream<firebase_auth.User?>.value(user),
      ),
      firebaseUserProvider.overrideWith(
        (ref) => Stream<firebase_auth.User?>.value(user),
      ),
      shellEmptinessServerProbeProvider.overrideWithValue((_) async => false),
      userGroupsProvider.overrideWith((ref) => Stream.value(const [])),
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
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: GoRouter(
        initialLocation: '/profile',
        routes: [
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        ],
      ),
    ),
  );
}

void main() {
  late _MockRecoveryService service;

  setUp(() {
    service = _MockRecoveryService();
  });

  testWidgets(
    'LTR: Language row value is pinned to the row trailing (right) edge',
    (tester) async {
      await tester.pumpWidget(
        await _wrap(
          service: service,
          languageCode: 'en',
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      final valueFinder = find.text('English');
      await tester.ensureVisible(valueFinder);
      await tester.pumpAndSettle();

      final rowFinder = find
          .ancestor(of: valueFinder, matching: find.byType(Row))
          .first;

      final valueRect = tester.getRect(valueFinder);
      final rowRect = tester.getRect(rowFinder);

      // Trailing edge in LTR is the right edge: the value's right edge must sit
      // essentially at the row's right edge (was ~centre before the fix).
      expect(
        valueRect.right,
        closeTo(rowRect.right, 1.5),
        reason:
            'value right=${valueRect.right} vs row right=${rowRect.right} — '
            'the trailing value is not pinned to the row trailing edge',
      );
    },
  );

  testWidgets(
    'RTL: Language row value is pinned to the row trailing (left) edge',
    (tester) async {
      await tester.pumpWidget(
        await _wrap(
          service: service,
          languageCode: 'ar',
          locale: const Locale('ar'),
        ),
      );
      await tester.pumpAndSettle();

      final valueFinder = find.text('العربية');
      await tester.ensureVisible(valueFinder);
      await tester.pumpAndSettle();

      final rowFinder = find
          .ancestor(of: valueFinder, matching: find.byType(Row))
          .first;

      final valueRect = tester.getRect(valueFinder);
      final rowRect = tester.getRect(rowFinder);

      // Trailing edge in RTL is the left edge (AlignmentDirectional mirror).
      expect(
        valueRect.left,
        closeTo(rowRect.left, 1.5),
        reason:
            'value left=${valueRect.left} vs row left=${rowRect.left} — '
            'the trailing value did not mirror to the RTL trailing edge',
      );
    },
  );
}
