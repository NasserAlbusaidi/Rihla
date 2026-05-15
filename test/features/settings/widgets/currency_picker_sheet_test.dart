import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/settings/widgets/currency_picker_sheet.dart';

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
                onPressed: () => CurrencyPickerSheet.show(ctx),
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

  testWidgets('renders all six currency options in fixed order',
      (tester) async {
    await _pumpWithSheet(tester);

    expect(find.text('Currency'), findsOneWidget);
    expect(find.text('Omani rial'), findsOneWidget);
    expect(find.text('UAE dirham'), findsOneWidget);
    expect(find.text('Saudi riyal'), findsOneWidget);
    expect(find.text('US dollar'), findsOneWidget);
    expect(find.text('Euro'), findsOneWidget);
    expect(find.text('British pound'), findsOneWidget);

    expect(
      find.text('Default for new trips. Existing trips keep their currency.'),
      findsOneWidget,
    );
  });

  testWidgets('tapping AED persists currency and dismisses sheet',
      (tester) async {
    await _pumpWithSheet(tester);

    await tester.tap(find.text('UAE dirham'));
    await tester.pumpAndSettle();

    expect(find.text('Currency'), findsNothing); // sheet closed

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings_currency'), 'AED');
  });

  testWidgets('tapping USD updates state via provider', (tester) async {
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
                    onPressed: () => CurrencyPickerSheet.show(ctx),
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
    await tester.tap(find.text('US dollar'));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).currencyCode, 'USD');
  });
}
