import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/screens/splash_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// Wraps [SplashScreen] in a MaterialApp carrying the localization delegates,
/// mirroring how main.dart's three boot MaterialApps now wire l10n (#286).
Widget _boot({
  required Locale locale,
  bool hasError = false,
  Object? error,
  VoidCallback? onRetry,
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: SplashScreen(hasError: hasError, error: error, onRetry: onRetry),
  );
}

void main() {
  // Never pumpAndSettle: the loading body's indeterminate LinearProgressIndicator
  // never settles.

  testWidgets('loading splash uses the localized tagline (en)', (tester) async {
    await tester.pumpWidget(_boot(locale: const Locale('en')));
    await tester.pump();
    expect(find.text('your shared journey'), findsOneWidget);
  });

  testWidgets('loading splash renders Arabic under an ar locale', (tester) async {
    await tester.pumpWidget(_boot(locale: const Locale('ar')));
    await tester.pump();
    expect(find.text('رحلتك المشتركة'), findsOneWidget);
    expect(find.text('your shared journey'), findsNothing);
  });

  testWidgets('error splash localizes title, body and retry (ar)', (tester) async {
    await tester.pumpWidget(
      _boot(locale: const Locale('ar'), hasError: true, onRetry: () {}),
    );
    await tester.pump();
    expect(find.text('حدث خطأ ما'), findsOneWidget);
    expect(find.text('تعذّر تشغيل التطبيق.'), findsOneWidget);
    expect(find.text('حاول مرة أخرى'), findsOneWidget);
  });

  testWidgets('error splash retry button fires onRetry (en)', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      _boot(
        locale: const Locale('en'),
        hasError: true,
        onRetry: () => retried = true,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });

  testWidgets('offline boot error (network-request-failed) shows offline copy, not generic (en) (#838)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _boot(
        locale: const Locale('en'),
        hasError: true,
        error: FirebaseAuthException(code: 'network-request-failed'),
        onRetry: () {},
      ),
    );
    await tester.pump();
    expect(find.text("You're offline"), findsOneWidget);
    expect(
      find.text(
        'Rihla needs an internet connection the first time it starts. Connect and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text("Something's off"), findsNothing);
    expect(find.text("We couldn't start the app."), findsNothing);
  });

  testWidgets('generic boot error (StateError) shows the existing generic copy, not offline (en) (#838)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _boot(
        locale: const Locale('en'),
        hasError: true,
        error: StateError('boom'),
        onRetry: () {},
      ),
    );
    await tester.pump();
    expect(find.text("Something's off"), findsOneWidget);
    expect(find.text("We couldn't start the app."), findsOneWidget);
    expect(find.text("You're offline"), findsNothing);
  });

  testWidgets('offline boot error renders the Arabic offline body under an ar locale (#838)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _boot(
        locale: const Locale('ar'),
        hasError: true,
        error: FirebaseAuthException(code: 'network-request-failed'),
        onRetry: () {},
      ),
    );
    await tester.pump();
    expect(find.text('لا يوجد اتصال'), findsOneWidget);
    expect(
      find.text(
        'يحتاج رحلة إلى اتصال بالإنترنت عند تشغيله لأول مرة. اتصل بالإنترنت وحاول مرة أخرى.',
      ),
      findsOneWidget,
    );
  });
}
