// tool/check_arb_completeness.dart
//
// Compares ARB key sets across locales. Run via:
//   dart run tool/check_arb_completeness.dart
//
// Exits 0 on match, 1 with a list of missing/extra keys on mismatch.
// Wired into readiness_check.yml CI.

import 'dart:convert';
import 'dart:io';

class CompareResult {
  CompareResult({required this.missingInAr, required this.extraInAr});
  final List<String> missingInAr;
  final List<String> extraInAr;
  bool get ok => missingInAr.isEmpty && extraInAr.isEmpty;
}

bool _isMetadata(String key) => key.startsWith('@');

CompareResult compare({
  required Map<String, dynamic> en,
  required Map<String, dynamic> ar,
}) {
  final enKeys = en.keys.where((k) => !_isMetadata(k)).toSet();
  final arKeys = ar.keys.where((k) => !_isMetadata(k)).toSet();
  return CompareResult(
    missingInAr: enKeys.difference(arKeys).toList()..sort(),
    extraInAr: arKeys.difference(enKeys).toList()..sort(),
  );
}

Future<void> main(List<String> args) async {
  final enPath = 'lib/l10n/app_en.arb';
  final arPath = 'lib/l10n/app_ar.arb';
  final enJson =
      jsonDecode(await File(enPath).readAsString()) as Map<String, dynamic>;
  final arJson =
      jsonDecode(await File(arPath).readAsString()) as Map<String, dynamic>;
  final result = compare(en: enJson, ar: arJson);
  if (result.ok) {
    // Count user-facing keys only — `@@locale` and `@<key>` metadata don't
    // count. `enJson.length - 1` looks right (subtract `@@locale`) but
    // double-counts every `@key` metadata entry. Filter through the same
    // metadata predicate `compare` uses.
    final matchedCount =
        enJson.keys.where((k) => !_isMetadata(k)).length;
    stdout.writeln('ARB completeness: OK ($matchedCount keys matched)');
    exit(0);
  }
  if (result.missingInAr.isNotEmpty) {
    stderr.writeln('Keys present in en but missing in ar:');
    for (final k in result.missingInAr) {
      stderr.writeln('  - $k');
    }
  }
  if (result.extraInAr.isNotEmpty) {
    stderr.writeln('Keys present in ar but missing in en:');
    for (final k in result.extraInAr) {
      stderr.writeln('  - $k');
    }
  }
  exit(1);
}
