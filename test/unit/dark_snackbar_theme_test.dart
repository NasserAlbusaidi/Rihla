import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';

void main() {
  group('SnackBar theme parity (#419)', () {
    test('lightTheme snackbar is floating', () {
      expect(
        AppTheme.lightTheme.snackBarTheme.behavior,
        SnackBarBehavior.floating,
      );
    });

    test('darkTheme snackbar is floating (not the M3 fixed default)', () {
      expect(
        AppTheme.darkTheme.snackBarTheme.behavior,
        SnackBarBehavior.floating,
      );
    });
  });
}
