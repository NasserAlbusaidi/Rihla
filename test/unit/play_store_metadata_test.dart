import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('English Play listing leads with the Oman/Gulf acquisition wedge', () {
    final description = File(
      'fastlane/metadata/android/en-US/full_description.txt',
    ).readAsStringSync();

    expect(description, contains('Oman and the Gulf'));
    expect(description, contains('WhatsApp'));
    expect(description, contains('No signup required'));
    expect(description, contains('Optionally link an email'));
    expect(description, isNot(contains('No account, no email')));
  });

  test('Arabic Play listing explains no-signup plus optional recovery', () {
    final description = File(
      'fastlane/metadata/android/ar/full_description.txt',
    ).readAsStringSync();

    expect(description, contains('عمان والخليج'));
    expect(description, contains('واتساب'));
    expect(description, contains('دون تسجيل إجباري'));
    expect(description, contains('استعادة اختيارية عبر البريد الإلكتروني'));
    expect(description, isNot(contains('دون حساب ولا بريد إلكتروني')));
  });

  test('Play listing descriptions stay within Google Play limits', () {
    final descriptions = [
      File('fastlane/metadata/android/en-US/full_description.txt'),
      File('fastlane/metadata/android/ar/full_description.txt'),
    ];

    for (final file in descriptions) {
      expect(file.readAsStringSync().runes.length, lessThanOrEqualTo(4000));
    }
  });

  test(
    'Play listing titles and short descriptions stay within visible limits',
    () {
      final titles = [
        File('fastlane/metadata/android/en-US/title.txt'),
        File('fastlane/metadata/android/ar/title.txt'),
      ];
      final shortDescriptions = [
        File('fastlane/metadata/android/en-US/short_description.txt'),
        File('fastlane/metadata/android/ar/short_description.txt'),
      ];

      for (final file in titles) {
        expect(
          file.readAsStringSync().trim().runes.length,
          lessThanOrEqualTo(30),
        );
      }
      for (final file in shortDescriptions) {
        expect(
          file.readAsStringSync().trim().runes.length,
          lessThanOrEqualTo(80),
        );
      }
    },
  );

  test('Play listing keeps localized screenshot sets and feature graphic', () {
    final englishScreenshots = Directory(
      'fastlane/metadata/android/en-US/images/phoneScreenshots',
    ).listSync().whereType<File>().toList(growable: false);
    final arabicScreenshots = Directory(
      'fastlane/metadata/android/ar/images/phoneScreenshots',
    ).listSync().whereType<File>().toList(growable: false);
    final featureGraphic = File(
      'fastlane/metadata/android/en-US/images/featureGraphic.png',
    );

    expect(englishScreenshots, hasLength(greaterThanOrEqualTo(4)));
    expect(arabicScreenshots, hasLength(greaterThanOrEqualTo(4)));
    expect(featureGraphic.existsSync(), isTrue);
  });
}
