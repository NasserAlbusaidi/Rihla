import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// DESIGN.md §1 (Falaj): "no italic anywhere in the system." Bricolage
/// Grotesque ships no italic cut, so any `FontStyle.italic` in `lib/`
/// synthesizes a fake slant — and on joined Arabic script it is doubly
/// forbidden. The ONLY sanctioned occurrence is the guarded `italic` parameter
/// inside `AppTypography` (`typography_tokens.dart`), which defaults off and is
/// suppressed entirely for Arabic by `displayOf`. Any other match is pre-Falaj
/// serif-era residue (#956) — route display text through
/// `AppTypography.displayOf(...)` instead of a raw italic `TextStyle`.
void main() {
  test('no synthetic FontStyle.italic in lib/ outside the typography helper', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // The one sanctioned site: the guarded `italic ? ... : ...` helper param.
      if (entity.path.endsWith('typography_tokens.dart')) continue;
      if (entity.readAsStringSync().contains('FontStyle.italic')) {
        offenders.add(entity.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'DESIGN.md §1 forbids italic anywhere (Bricolage has no italic cut → '
          'synthetic slant; Arabic joined script doubly so). Use '
          'AppTypography.displayOf(...) instead of a raw italic TextStyle.',
    );
  });
}
