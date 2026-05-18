import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/ledger/utils/ledger_categories.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ledgerCategoryName', () {
    test('returns English bucket names from l10n keys', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      expect(ledgerCategoryName(1, l10n), l10n.ledgerBucketFood);
      expect(ledgerCategoryName(2, l10n), l10n.ledgerBucketLodging);
      expect(ledgerCategoryName(3, l10n), l10n.ledgerBucketTransit);
      expect(ledgerCategoryName(4, l10n), l10n.ledgerBucketGroceries);
      expect(ledgerCategoryName(5, l10n), l10n.ledgerBucketActivities);
      expect(ledgerCategoryName(6, l10n), l10n.ledgerBucketOther);
    });

    test('returns Arabic bucket names distinct from English names', () async {
      final ar = await AppLocalizations.delegate.load(const Locale('ar'));
      final en = await AppLocalizations.delegate.load(const Locale('en'));

      for (var bucket = 1; bucket <= 6; bucket++) {
        expect(ledgerCategoryName(bucket, ar), isNotEmpty);
        expect(
          ledgerCategoryName(bucket, ar),
          isNot(ledgerCategoryName(bucket, en)),
        );
      }
    });

    test('falls back to Other for out-of-range buckets', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      expect(ledgerCategoryName(99, l10n), l10n.ledgerBucketOther);
      expect(ledgerCategoryName(0, l10n), l10n.ledgerBucketOther);
    });
  });
}
