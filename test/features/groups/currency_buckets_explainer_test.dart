import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/widgets/currency_buckets_explainer.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

Future<void> _pump(
  WidgetTester tester, {
  required SharedPreferences prefs,
  required int bucketCount,
  Locale? locale,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: CurrencyBucketsExplainer(bucketCount: bucketCount),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('shown when there are 2 buckets and the flag is unseen', (
    tester,
  ) async {
    await _pump(tester, prefs: prefs, bucketCount: 2);

    expect(find.byKey(GroupKeys.currencyExplainerCard), findsOneWidget);
    expect(find.byKey(GroupKeys.currencyExplainerGotIt), findsOneWidget);
  });

  testWidgets('absent when there is only 1 bucket', (tester) async {
    await _pump(tester, prefs: prefs, bucketCount: 1);

    expect(find.byKey(GroupKeys.currencyExplainerCard), findsNothing);
  });

  testWidgets('absent once the seen flag is set', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings_currency_explainer_seen': true,
    });
    prefs = await SharedPreferences.getInstance();

    await _pump(tester, prefs: prefs, bucketCount: 2);

    expect(find.byKey(GroupKeys.currencyExplainerCard), findsNothing);
  });

  testWidgets('Got it dismisses the card and persists the flag', (
    tester,
  ) async {
    await _pump(tester, prefs: prefs, bucketCount: 2);
    expect(find.byKey(GroupKeys.currencyExplainerCard), findsOneWidget);

    await tester.tap(find.byKey(GroupKeys.currencyExplainerGotIt));
    await tester.pumpAndSettle();

    expect(find.byKey(GroupKeys.currencyExplainerCard), findsNothing);
    expect(prefs.getBool('settings_currency_explainer_seen'), isTrue);
  });

  // The card renders on every device; its body + button must never
  // RenderFlex-overflow at narrow widths, including the long Arabic copy.
  for (final (name, locale) in const [
    ('English', Locale('en')),
    ('Arabic', Locale('ar')),
  ]) {
    for (final width in const [360.0, 320.0]) {
      testWidgets('does not overflow at ${width.toInt()}px in $name', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 720);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pump(tester, prefs: prefs, bucketCount: 2, locale: locale);

        expect(find.byKey(GroupKeys.currencyExplainerCard), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
