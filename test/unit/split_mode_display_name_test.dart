import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/utils/split_mode_display_name.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/l10n/generated/app_localizations_ar.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';

void main() {
  group('splitModeDisplayName', () {
    test('returns en localized name for each enum value', () {
      final AppLocalizations l10n = AppLocalizationsEn();
      expect(splitModeDisplayName(SplitMode.equally, l10n), 'Equal');
      expect(splitModeDisplayName(SplitMode.shares, l10n), 'Shares');
      expect(splitModeDisplayName(SplitMode.exact, l10n), 'Exact amounts');
      expect(splitModeDisplayName(SplitMode.percent, l10n), 'Percent');
    });

    test('returns ar localized name for each enum value', () {
      final AppLocalizations l10n = AppLocalizationsAr();
      expect(splitModeDisplayName(SplitMode.equally, l10n), 'بالتساوي');
      expect(splitModeDisplayName(SplitMode.shares, l10n), 'حصص');
      expect(splitModeDisplayName(SplitMode.exact, l10n), 'مبالغ محدّدة');
      expect(splitModeDisplayName(SplitMode.percent, l10n), 'نسبة مئوية');
    });

    test('handles all SplitMode values exhaustively (compile-time check)', () {
      final AppLocalizations l10n = AppLocalizationsEn();
      for (final mode in SplitMode.values) {
        expect(splitModeDisplayName(mode, l10n), isNotEmpty);
      }
    });
  });
}
