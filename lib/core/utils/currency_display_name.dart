import '../../l10n/generated/app_localizations.dart';

/// Returns the localized human-readable name for an ISO 4217 [code], or the
/// code itself if it is not recognized.
///
/// Backed by per-currency ARB keys (`currencyOMR`, `currencyAED`, …). Add a
/// new entry to both ARB files and extend the switch below when introducing
/// support for an additional currency in the picker.
String currencyDisplayName(String code, AppLocalizations l10n) {
  switch (code) {
    case 'OMR':
      return l10n.currencyOMR;
    case 'AED':
      return l10n.currencyAED;
    case 'SAR':
      return l10n.currencySAR;
    case 'USD':
      return l10n.currencyUSD;
    case 'EUR':
      return l10n.currencyEUR;
    case 'GBP':
      return l10n.currencyGBP;
    case 'QAR':
      return l10n.currencyQAR;
    case 'KWD':
      return l10n.currencyKWD;
    case 'BHD':
      return l10n.currencyBHD;
    case 'JPY':
      return l10n.currencyJPY;
    default:
      return code;
  }
}
