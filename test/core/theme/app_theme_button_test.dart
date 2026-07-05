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

  testWidgets('rendered button labels leave bottom descender clearance', (
    tester,
  ) async {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      await _pumpDescenderButtons(tester, theme);
      _expectRenderedLabelClearance(
        tester,
        buttonKey: _elevatedButtonKey,
        labelKey: _elevatedLabelKey,
        minBottomGap: 12,
      );
      _expectRenderedLabelClearance(
        tester,
        buttonKey: _filledButtonKey,
        labelKey: _filledLabelKey,
        minBottomGap: 12,
      );
      _expectRenderedLabelClearance(
        tester,
        buttonKey: _outlinedButtonKey,
        labelKey: _outlinedLabelKey,
        minBottomGap: 12,
      );
      _expectRenderedLabelClearance(
        tester,
        buttonKey: _textButtonKey,
        labelKey: _textLabelKey,
        minBottomGap: 9,
      );
    }
  });

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
        final zeroMinimumSizePattern = RegExp(
          r'minimumSize:\s*(?:const\s+)?Size\.zero',
        );
        for (var i = 0; i < lines.length; i++) {
          final match = minimumSizePattern.firstMatch(lines[i]);
          if (zeroMinimumSizePattern.hasMatch(lines[i])) {
            offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
            continue;
          }

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
            'Material buttons below 40dp can clip Zain descenders; use the '
            'theme defaults or a compact 40dp+ override with explicit line height.',
      );
    },
  );
}

const _elevatedButtonKey = ValueKey('descender-elevated-button');
const _elevatedLabelKey = ValueKey('descender-elevated-label');
const _filledButtonKey = ValueKey('descender-filled-button');
const _filledLabelKey = ValueKey('descender-filled-label');
const _outlinedButtonKey = ValueKey('descender-outlined-button');
const _outlinedLabelKey = ValueKey('descender-outlined-label');
const _textButtonKey = ValueKey('descender-text-button');
const _textLabelKey = ValueKey('descender-text-label');

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

Future<void> _pumpDescenderButtons(WidgetTester tester, ThemeData theme) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                key: _elevatedButtonKey,
                onPressed: () {},
                child: const Text('gypjq', key: _elevatedLabelKey),
              ),
              FilledButton(
                key: _filledButtonKey,
                onPressed: () {},
                child: const Text('gypjq', key: _filledLabelKey),
              ),
              OutlinedButton(
                key: _outlinedButtonKey,
                onPressed: () {},
                child: const Text('gypjq', key: _outlinedLabelKey),
              ),
              TextButton(
                key: _textButtonKey,
                onPressed: () {},
                child: const Text('gypjq', key: _textLabelKey),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void _expectRenderedLabelClearance(
  WidgetTester tester, {
  required Key buttonKey,
  required Key labelKey,
  required double minBottomGap,
}) {
  final buttonRect = tester.getRect(find.byKey(buttonKey));
  final labelRect = tester.getRect(find.byKey(labelKey));

  expect(labelRect.top, greaterThanOrEqualTo(buttonRect.top));
  expect(labelRect.bottom, lessThanOrEqualTo(buttonRect.bottom));
  expect(
    buttonRect.bottom - labelRect.bottom,
    greaterThanOrEqualTo(minBottomGap),
  );
}
