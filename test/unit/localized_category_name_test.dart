import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/ledger/utils/localized_category_name.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('localizedCategoryName', () {
    test('returns the English ARB value for each known id', () async {
      final en = await AppLocalizations.delegate.load(const Locale('en'));

      expect(localizedCategoryName(id: 'food', l10n: en), en.categoryFood);
      expect(
        localizedCategoryName(id: 'transport', l10n: en),
        en.categoryTransport,
      );
      expect(
        localizedCategoryName(id: 'accommodation', l10n: en),
        en.categoryAccommodation,
      );
      expect(
        localizedCategoryName(id: 'activities', l10n: en),
        en.categoryActivities,
      );
      expect(
        localizedCategoryName(id: 'shopping', l10n: en),
        en.categoryShopping,
      );
      expect(localizedCategoryName(id: 'other', l10n: en), en.categoryOther);
    });

    test('returns Arabic ARB values distinct from English values', () async {
      final ar = await AppLocalizations.delegate.load(const Locale('ar'));
      final en = await AppLocalizations.delegate.load(const Locale('en'));

      for (final id in const [
        'food',
        'transport',
        'accommodation',
        'activities',
        'shopping',
        'other',
      ]) {
        expect(localizedCategoryName(id: id, l10n: ar), isNotEmpty);
        expect(
          localizedCategoryName(id: id, l10n: ar),
          isNot(localizedCategoryName(id: id, l10n: en)),
        );
      }
    });

    test(
      'returns fallbackName when id is null and fallbackName is set',
      () async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));

        expect(
          localizedCategoryName(fallbackName: 'Concert tickets', l10n: l10n),
          'Concert tickets',
        );
      },
    );

    test('returns fallbackName when id is unknown', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      expect(
        localizedCategoryName(
          id: 'wibble',
          fallbackName: 'Concert tickets',
          l10n: l10n,
        ),
        'Concert tickets',
      );
    });

    test(
      'returns categoryOther when id and fallbackName are missing',
      () async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));

        expect(localizedCategoryName(l10n: l10n), l10n.categoryOther);
      },
    );

    test('returns categoryOther when fallbackName is empty', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      expect(
        localizedCategoryName(id: 'wibble', fallbackName: '', l10n: l10n),
        l10n.categoryOther,
      );
    });
  });
}
