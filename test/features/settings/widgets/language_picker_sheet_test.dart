import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/settings/widgets/language_picker_sheet.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// Pumps the LanguagePickerSheet inside an app with the requested [locale]
/// and returns a [ProviderContainer] callers can use to assert state.
Future<ProviderContainer> _pumpSheet(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  final prefs = await SharedPreferences.getInstance();
  late ProviderContainer container;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (ctx, ref, _) {
            container = ProviderScope.containerOf(ctx);
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => LanguagePickerSheet.show(ctx),
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('en: renders title + both language options without lock copy',
      (tester) async {
    await _pumpSheet(tester);

    expect(find.text('Language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);

    // Toggle unlock — no 'Coming soon' subtitle remains
    expect(find.text('Coming soon'), findsNothing);
  });

  testWidgets('en: tapping Arabic switches the language to ar',
      (tester) async {
    final container = await _pumpSheet(tester);

    expect(container.read(settingsProvider).languageCode, 'en');

    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).languageCode, 'ar');
  });

  testWidgets('ar: title renders in Arabic', (tester) async {
    await _pumpSheet(tester, locale: const Locale('ar'));

    expect(find.text('اللغة'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);
  });
}
