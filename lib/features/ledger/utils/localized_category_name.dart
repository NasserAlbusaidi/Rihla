import '../../../l10n/generated/app_localizations.dart';
import 'ledger_categories.dart';

/// Localized display name for a category. Known catalog ids (#689) resolve via
/// [categoryNameForId]; an unknown id falls back to [fallbackName], else Other.
String localizedCategoryName({
  String? id,
  String? fallbackName,
  required AppLocalizations l10n,
}) {
  if (id != null && kCategoryIds.contains(id)) {
    return categoryNameForId(id, l10n);
  }
  if (fallbackName != null && fallbackName.isNotEmpty) {
    return fallbackName;
  }
  return l10n.categoryOther;
}
