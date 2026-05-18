import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/ledger/models/expense_category_model.dart';
import 'package:safar/features/ledger/widgets/amount_input_section.dart';
import 'package:safar/features/ledger/widgets/category_selection_step.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

void main() {
  Widget wrap(Widget child, {Size size = const Size(390, 844)}) {
    return ProviderScope(
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );
  }

  testWidgets('amount keypad exposes a decimal-point key', (tester) async {
    final pressedKeys = <String>[];

    await tester.pumpWidget(
      wrap(
        AmountInputSection(
          amount: '0',
          currency: 'OMR',
          onKeyPress: pressedKeys.add,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Decimal point'));

    expect(pressedKeys, equals(['.']));
  });

  testWidgets('category grid tiles fit on a phone-width layout', (
    tester,
  ) async {
    final categories = [
      const ExpenseCategory(
        id: 'food',
        tripId: '',
        name: 'Food & Dining',
        icon: 'food',
      ),
      const ExpenseCategory(
        id: 'transport',
        tripId: '',
        name: 'Transport',
        icon: 'transport',
      ),
      const ExpenseCategory(
        id: 'accommodation',
        tripId: '',
        name: 'Accommodation',
        icon: 'lodging',
      ),
      const ExpenseCategory(id: 'activities', tripId: '', name: 'Activities'),
    ];

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 358,
          height: 390,
          child: CategorySelectionStep(
            categoriesAsync: AsyncValue.data(categories),
            selectedCategoryId: null,
            onCategorySelected: (_) {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
