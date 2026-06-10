// Widget tests for the soft in-app notification rationale sheet (#352).
//
// The sheet is shown *before* the OS permission dialog. It must render its EN
// and AR copy, return `true` on [Turn on], and `false` on [Not now] or a
// barrier dismiss. The orchestration around it (when it fires, the once-only
// contract) is unit-tested in notification_prompt_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/extensions/build_context_l10n.dart';
import 'package:safar/core/services/notification_rationale_sheet.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

void main() {
  bool? result;

  setUp(() => result = null);

  Widget harness(Locale locale) {
    return MaterialApp(
      locale: locale,
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showNotificationRationaleSheet(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  Future<AppLocalizations> open(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(harness(locale));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l10n = tester.element(find.text('open')).l10n;
    return l10n;
  }

  testWidgets('EN: renders title, body, and both actions', (tester) async {
    final l10n = await open(tester, const Locale('en'));
    expect(find.text(l10n.notificationRationaleTitle), findsOneWidget);
    expect(find.text(l10n.notificationRationaleBody), findsOneWidget);
    expect(find.text(l10n.notificationRationaleNotNow), findsOneWidget);
    expect(find.text(l10n.notificationRationaleTurnOn), findsOneWidget);
  });

  testWidgets('AR: renders the localized title and actions', (tester) async {
    final l10n = await open(tester, const Locale('ar'));
    // Locale-resolved strings prove the AR translations render (no hard-coded
    // Arabic literals to drift against the ARB).
    expect(find.text(l10n.notificationRationaleTitle), findsOneWidget);
    expect(find.text(l10n.notificationRationaleTurnOn), findsOneWidget);
    expect(find.text(l10n.notificationRationaleNotNow), findsOneWidget);
  });

  testWidgets('[Turn on] resolves true', (tester) async {
    final l10n = await open(tester, const Locale('en'));
    await tester.tap(find.text(l10n.notificationRationaleTurnOn));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('[Not now] resolves false', (tester) async {
    final l10n = await open(tester, const Locale('en'));
    await tester.tap(find.text(l10n.notificationRationaleNotNow));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('barrier dismiss resolves false (never null)', (tester) async {
    await open(tester, const Locale('en'));
    // Tap the scrim above the sheet to dismiss without choosing.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
