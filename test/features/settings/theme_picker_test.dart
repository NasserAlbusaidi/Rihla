import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/models/app_settings_model.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/settings/widgets/theme_picker_sheet.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpWithSheet(WidgetTester tester) async {
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
                  onPressed: () => ThemePickerSheet.show(ctx),
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

  testWidgets('renders System / Light / Dark radio options', (tester) async {
    await pumpWithSheet(tester);

    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);

    // Subtitles — one-line descriptions per D-06.
    expect(find.text('Follow device setting'), findsOneWidget);
    expect(find.text('Always light'), findsOneWidget);
    expect(find.text('Always dark'), findsOneWidget);
  });

  testWidgets('tapping Dark updates settingsProvider and persists', (tester) async {
    await pumpWithSheet(tester);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    // Sheet dismissed.
    expect(find.text('System'), findsNothing);

    // Persistence round-trip via the same SharedPreferences instance.
    final prefs = await SharedPreferences.getInstance();
    // SettingsService stores AppThemeMode.index under 'settings_theme'.
    expect(prefs.getInt('settings_theme'), equals(AppThemeMode.dark.index));
  });

  testWidgets('tapping Light updates settingsProvider state', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer capturedContainer;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Consumer(
            builder: (ctx, ref, _) {
              capturedContainer = ProviderScope.containerOf(ctx);
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => ThemePickerSheet.show(ctx),
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

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    final settings = capturedContainer.read(settingsProvider);
    expect(settings.themeMode, equals(AppThemeMode.light));
  });
}
