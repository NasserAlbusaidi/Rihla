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
}
