import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #292 — RTL hygiene guard for `lib/features`.
///
/// Non-directional horizontal alignments (`Alignment.centerLeft`,
/// `topRight`, …) pin a widget to the visual left/right regardless of locale,
/// so under Arabic RTL they land on the wrong edge. User-facing layouts must
/// use the directional APIs (`AlignmentDirectional.centerStart`, etc.) so the
/// app mirrors correctly. Vertically-biased / centered constants
/// (`center`, `topCenter`, `bottomCenter`) are horizontally symmetric and
/// therefore RTL-safe.
///
/// This guards the whole feature tree, not just the settle-up back button that
/// surfaced the bug, so the class can't quietly reappear.
void main() {
  const banned = [
    'Alignment.centerLeft',
    'Alignment.centerRight',
    'Alignment.topLeft',
    'Alignment.topRight',
    'Alignment.bottomLeft',
    'Alignment.bottomRight',
  ];

  test('lib/features uses directional alignment, not Alignment.<edge> (#292)', () {
    final offenders = <String>[];

    final dartFiles = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // `pw.Alignment.*` (the `package:pdf` widgets alignment) is ABSOLUTE
        // document layout — a generated PDF has no Directionality / RTL
        // auto-mirroring, so right-aligning a numeric column is deliberate and
        // locale-independent. Scrub that prefix so it isn't confused with the
        // Flutter `Alignment` this guard exists to catch (#704 Slice B PDF). A
        // bare `Alignment.centerLeft` still trips the guard.
        final line = lines[i].replaceAll('pw.Alignment.', 'pdfAbsAlign_');
        for (final token in banned) {
          if (line.contains(token)) {
            offenders.add('${file.path}:${i + 1}  ->  ${lines[i].trim()}');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Use AlignmentDirectional.* (start/end) for user-facing layouts so '
          'Arabic RTL mirrors correctly. Offenders:\n${offenders.join('\n')}',
    );
  });
}
