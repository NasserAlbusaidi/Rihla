import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/settings/widgets/language_picker_sheet.dart';

Future<void> _pumpWithSheet(WidgetTester tester) async {
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => LanguagePickerSheet.show(ctx),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders English and Arabic-coming-soon options', (tester) async {
    await _pumpWithSheet(tester);

    expect(find.text('Language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
  });

  testWidgets('Arabic option is disabled and does not change setting',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
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

    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();

    // Sheet stays open, language unchanged.
    expect(find.text('Language'), findsOneWidget);
    expect(container.read(settingsProvider).languageCode, 'en');
  });

  testWidgets('English is the default selected language', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
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

    expect(container.read(settingsProvider).languageCode, 'en');
    expect(find.text('English'), findsOneWidget);
  });
}
