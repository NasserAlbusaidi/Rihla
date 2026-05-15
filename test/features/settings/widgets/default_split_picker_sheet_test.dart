import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/settings/widgets/default_split_picker_sheet.dart';

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
                onPressed: () => DefaultSplitPickerSheet.show(ctx),
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

  testWidgets('renders all four split mode options', (tester) async {
    await _pumpWithSheet(tester);

    expect(find.text('Default split'), findsOneWidget);
    expect(find.text('Equal'), findsOneWidget);
    expect(find.text('Shares'), findsOneWidget);
    expect(find.text('Exact amounts'), findsOneWidget);
    expect(find.text('Percent'), findsOneWidget);
  });

  testWidgets('tapping Shares persists and dismisses', (tester) async {
    await _pumpWithSheet(tester);

    await tester.tap(find.text('Shares'));
    await tester.pumpAndSettle();

    expect(find.text('Default split'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings_default_split_mode'), 'shares');
  });

  testWidgets('tapping Exact amounts updates the provider state',
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
                    onPressed: () => DefaultSplitPickerSheet.show(ctx),
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
    await tester.tap(find.text('Exact amounts'));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).defaultSplitMode,
        SplitMode.exact);
  });
}
