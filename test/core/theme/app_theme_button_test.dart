import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safar/core/theme/app_theme.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    'Material buttons reserve enough vertical room for label descenders',
    (tester) async {
      _suppressFontErrors(() {
        for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
          _expectProminentStyle(theme.elevatedButtonTheme.style);
          _expectProminentStyle(theme.filledButtonTheme.style);
          _expectProminentStyle(theme.outlinedButtonTheme.style);
          _expectTextStyle(theme.textButtonTheme.style);
        }
      });
    },
  );

  test(
    'local Material button overrides do not go below 40dp minimum heights',
    () {
      final offenders = <String>[];
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;

        final content = file.readAsStringSync();
        if (!content.contains('Button.styleFrom')) continue;

        final lines = content.split('\n');
        final minimumSizePattern = RegExp(
          r'minimumSize:\s*const Size\([^,]+,\s*([0-9]+(?:\.[0-9]+)?)\)',
        );
        for (var i = 0; i < lines.length; i++) {
          final match = minimumSizePattern.firstMatch(lines[i]);
          if (match == null) continue;

          final height = double.parse(match.group(1)!);
          if (height < 40) {
            offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Material buttons below 40dp can clip Geist descenders; use the '
            'theme defaults or a compact 40dp+ override with explicit line height.',
      );
    },
  );
}

T _suppressFontErrors<T>(T Function() body) {
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('google_fonts')) return;
    originalOnError?.call(details);
  };
  try {
    return body();
  } finally {
    FlutterError.onError = originalOnError;
  }
}

void _expectProminentStyle(ButtonStyle? style) {
  expect(style, isNotNull);
  expect(
    style!.minimumSize?.resolve(const <WidgetState>{}),
    const Size(64, 52),
  );
  expect(
    style.padding?.resolve(const <WidgetState>{}),
    const EdgeInsetsDirectional.fromSTEB(24, 14, 24, 16),
  );
  _expectLabelStyle(style, fontSize: 15);
}

void _expectTextStyle(ButtonStyle? style) {
  expect(style, isNotNull);
  expect(
    style!.minimumSize?.resolve(const <WidgetState>{}),
    const Size(48, 44),
  );
  expect(
    style.padding?.resolve(const <WidgetState>{}),
    const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 12),
  );
  _expectLabelStyle(style, fontSize: 13);
}

void _expectLabelStyle(ButtonStyle style, {required double fontSize}) {
  final textStyle = style.textStyle?.resolve(const <WidgetState>{});
  expect(textStyle, isNotNull);
  expect(textStyle!.fontSize, fontSize);
  expect(textStyle.height, 1.22);
  expect(textStyle.leadingDistribution, TextLeadingDistribution.even);
}
