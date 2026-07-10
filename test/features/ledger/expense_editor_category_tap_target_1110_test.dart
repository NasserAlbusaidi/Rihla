import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/ledger/models/expense_category_model.dart';
import 'package:safar/features/ledger/widgets/expense_editor/category_strip.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('#1110 expense category chip meets the 44dp tap-target floor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CategoryStrip(
            categoriesAsync: const AsyncValue.data([
              ExpenseCategory(id: 'food', tripId: 'event-1', name: 'Food'),
            ]),
            selectedCategoryId: 'food',
            onCategorySelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final target = find.byType(InkWell).first;
    final paintedPill = find
        .descendant(
          of: target,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.decoration is BoxDecoration &&
                (widget.decoration! as BoxDecoration).borderRadius != null,
          ),
        )
        .first;
    expect(tester.getSize(paintedPill).height, 42);

    final size = tester.getSize(target);
    expect(size.width, greaterThanOrEqualTo(44), reason: 'width ${size.width}');
    expect(
      size.height,
      greaterThanOrEqualTo(44),
      reason: 'Category chip effective hit target height ${size.height}dp',
    );
    expect(
      tester
          .widget<Icon>(
            find.descendant(of: target, matching: find.byType(Icon)),
          )
          .size,
      11,
    );
  });
}
