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
/// Scope of the back-arrow rule is `arrow_left*` per #348; the forward
/// disclosure chevron (`arrow_right_3`) is guarded by the second test below.
void main() {
  Iterable<File> libFeatureDartFiles() => Directory('lib/features')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  test('lib/features wraps back arrows in DirectionalIcon, not bare Icon (#348)',
      () {
    final banned = RegExp(r'\bIcon\(\s*Iconsax\.arrow_left');
    final offenders = <String>[];

    for (final file in libFeatureDartFiles()) {
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

  /// #348 follow-up — the forward disclosure chevron must mirror in RTL too.
  ///
  /// `arrow_right_3` is the codebase's "go / next / disclosure" glyph (profile
  /// rows, the paid-by row, the success dialog, the create-event button). A bare
  /// `Icon(Iconsax.arrow_right_3)` points **→** in every locale, so under Arabic
  /// RTL it points away from the start edge. Route it through [DirectionalIcon].
  ///
  /// The match is whole-file (not per-line) so a multi-line
  /// `Icon(\n  Iconsax.arrow_right_3,\n  …)` is caught, not just the one-liner.
  /// `\bIcon\(` skips `DirectionalIcon(` (the 'l' before 'Icon' kills the word
  /// boundary) and the `Iconsax` immediately after `(` skips RTL-aware ternaries
  /// like `Icon(rtl ? Iconsax.arrow_left : Iconsax.arrow_right_3)`. The thinner
  /// `arrow_right_1`/`arrow_right_2` direction glyphs are intentionally out of
  /// scope (e.g. the settlement transfer arrow).
  test('lib/features routes the forward chevron through DirectionalIcon (#348)',
      () {
    final banned = RegExp(r'\bIcon\(\s*Iconsax\.arrow_right_3');
    final offenders = <String>[];

    for (final file in libFeatureDartFiles()) {
      if (banned.hasMatch(file.readAsStringSync())) {
        offenders.add(file.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Wrap the forward chevron in DirectionalIcon(Iconsax.arrow_right_3) so '
          'Arabic RTL mirrors it. Offending files:\n${offenders.join('\n')}',
    );
  });
}
