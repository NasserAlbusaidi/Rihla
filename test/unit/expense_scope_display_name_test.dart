import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/utils/expense_scope_display_name.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('expenseScopeDisplayName', () {
    test('returns English labels for each ExpenseScope', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      expect(expenseScopeDisplayName(ExpenseScope.global, l10n), 'Everyone');
      expect(
        expenseScopeDisplayName(ExpenseScope.subGroup, l10n),
        'Group split',
      );
      expect(expenseScopeDisplayName(ExpenseScope.custom, l10n), 'Custom');
      expect(expenseScopeDisplayName(ExpenseScope.personal, l10n), 'Personal');
    });

    test('returns Arabic labels distinct from English labels', () async {
      final ar = await AppLocalizations.delegate.load(const Locale('ar'));
      final en = await AppLocalizations.delegate.load(const Locale('en'));

      for (final scope in ExpenseScope.values) {
        expect(expenseScopeDisplayName(scope, ar), isNotEmpty);
        expect(
          expenseScopeDisplayName(scope, ar),
          isNot(expenseScopeDisplayName(scope, en)),
        );
      }
    });
  });
}
