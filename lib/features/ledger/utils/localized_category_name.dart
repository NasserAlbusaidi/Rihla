import '../../../l10n/generated/app_localizations.dart';

String localizedCategoryName({
  String? id,
  String? fallbackName,
  required AppLocalizations l10n,
}) {
  switch (id) {
    case 'food':
      return l10n.categoryFood;
    case 'transport':
      return l10n.categoryTransport;
    case 'accommodation':
      return l10n.categoryAccommodation;
    case 'activities':
      return l10n.categoryActivities;
    case 'shopping':
      return l10n.categoryShopping;
    case 'other':
      return l10n.categoryOther;
  }
  if (fallbackName != null && fallbackName.isNotEmpty) {
    return fallbackName;
  }
  return l10n.categoryOther;
}
