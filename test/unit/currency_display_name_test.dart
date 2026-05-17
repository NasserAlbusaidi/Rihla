import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/utils/currency_display_name.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/l10n/generated/app_localizations_ar.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';

void main() {
  group('currencyDisplayName', () {
    test('returns en localized name for every supported code', () {
      final AppLocalizations l10n = AppLocalizationsEn();
      expect(currencyDisplayName('OMR', l10n), 'Omani rial');
      expect(currencyDisplayName('AED', l10n), 'UAE dirham');
      expect(currencyDisplayName('SAR', l10n), 'Saudi riyal');
      expect(currencyDisplayName('USD', l10n), 'US dollar');
      expect(currencyDisplayName('EUR', l10n), 'Euro');
      expect(currencyDisplayName('GBP', l10n), 'British pound');
      expect(currencyDisplayName('QAR', l10n), 'Qatari riyal');
      expect(currencyDisplayName('KWD', l10n), 'Kuwaiti dinar');
      expect(currencyDisplayName('BHD', l10n), 'Bahraini dinar');
      expect(currencyDisplayName('JPY', l10n), 'Japanese yen');
    });

    test('returns ar localized name for every supported code', () {
      final AppLocalizations l10n = AppLocalizationsAr();
      expect(currencyDisplayName('OMR', l10n), 'ريال عُماني');
      expect(currencyDisplayName('AED', l10n), 'درهم إماراتي');
      expect(currencyDisplayName('SAR', l10n), 'ريال سعودي');
      expect(currencyDisplayName('USD', l10n), 'دولار أمريكي');
      expect(currencyDisplayName('EUR', l10n), 'يورو');
      expect(currencyDisplayName('GBP', l10n), 'جنيه إسترليني');
      expect(currencyDisplayName('QAR', l10n), 'ريال قطري');
      expect(currencyDisplayName('KWD', l10n), 'دينار كويتي');
      expect(currencyDisplayName('BHD', l10n), 'دينار بحريني');
      expect(currencyDisplayName('JPY', l10n), 'ين ياباني');
    });

    test('returns the code itself for unknown currencies', () {
      final AppLocalizations l10n = AppLocalizationsEn();
      expect(currencyDisplayName('XYZ', l10n), 'XYZ');
      expect(currencyDisplayName('', l10n), '');
      expect(currencyDisplayName('CAD', l10n), 'CAD');
    });
  });
}
