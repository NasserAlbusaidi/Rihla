import '../../features/ledger/models/expense_model.dart';
import '../../l10n/generated/app_localizations.dart';

String expenseScopeDisplayName(ExpenseScope scope, AppLocalizations l10n) {
  return switch (scope) {
    ExpenseScope.global => l10n.editorScopeGlobal,
    ExpenseScope.subGroup => l10n.editorScopeSubGroup,
    ExpenseScope.custom => l10n.editorScopeCustom,
    ExpenseScope.personal => l10n.editorScopePersonal,
  };
}
