import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #348 — RTL hygiene guard for navigational back-arrow glyphs.
///
/// Iconsax `IconData` ships without `matchTextDirection: true`, so a bare
/// `Icon(Iconsax.arrow_left*)` renders the same glyph in every locale and
/// points **←** under Arabic RTL instead of mirroring to the start edge.
/// Back arrows must go through [DirectionalIcon] (the sanctioned RTL flip).
///
/// The boundary `\b` before `Icon` is load-bearing: it lets the fixed
/// `DirectionalIcon(Iconsax.arrow_left_2)` and ternary selectors
/// (`Icon(rtl ? Iconsax.arrow_left : …)`) pass — only the bare wrap matches.
///
/// Scope is `arrow_left*` per the issue; a stray bare `Icon(Iconsax.arrow_right…)`
/// (forward chevron) is tracked separately.
void main() {
  final banned = RegExp(r'\bIcon\(\s*Iconsax\.arrow_left');

  test('lib/features wraps back arrows in DirectionalIcon, not bare Icon (#348)',
      () {
    final offenders = <String>[];

    final dartFiles = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (banned.hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1}  ->  ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Wrap navigational back arrows in DirectionalIcon(Iconsax.arrow_left_2) '
          'so Arabic RTL mirrors them to the start edge. Offenders:\n'
          '${offenders.join('\n')}',
    );
  });
}
