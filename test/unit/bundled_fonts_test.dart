import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the offline-branding contract from #103: the four brand faces are
/// bundled as app assets and resolved natively, never fetched from the Google
/// Fonts CDN. A drift here (renamed family, deleted .ttf, a reintroduced
/// `GoogleFonts.getFont`) would silently fall back to the platform font on an
/// offline first launch — exactly the bug this issue fixed.
void main() {
  String read(String path) => File(path).readAsStringSync();

  // family name -> the variable/static .ttf assets that must back it.
  const families = <String, List<String>>{
    'Geist': ['assets/fonts/Geist-Variable.ttf'],
    'Geist Mono': ['assets/fonts/GeistMono-Variable.ttf'],
    'Reem Kufi': ['assets/fonts/ReemKufi-Variable.ttf'],
    'Instrument Serif': [
      'assets/fonts/InstrumentSerif-Regular.ttf',
      'assets/fonts/InstrumentSerif-Italic.ttf',
    ],
  };

  const licenseAssets = [
    'assets/fonts/OFL-Geist.txt',
    'assets/fonts/OFL-GeistMono.txt',
    'assets/fonts/OFL-ReemKufi.txt',
    'assets/fonts/OFL-InstrumentSerif.txt',
  ];

  group('bundled brand fonts (#103)', () {
    final pubspec = read('pubspec.yaml');
    final tokens = read('lib/core/theme/tokens/typography_tokens.dart');

    test('every AppTypography family const is declared in pubspec fonts', () {
      // The const family literals the helpers use, byte-for-byte.
      expect(tokens, contains("static const String sansFamily = 'Geist';"));
      expect(tokens, contains("static const String monoFamily = 'Geist Mono';"));
      expect(tokens, contains("static const String reemKufiFamily = 'Reem Kufi';"));
      expect(
        tokens,
        contains("static const String displayFamily = 'Instrument Serif';"),
      );
      for (final family in families.keys) {
        expect(
          pubspec,
          contains('- family: $family'),
          reason:
              'pubspec.yaml flutter.fonts must declare family "$family" to match '
              'the AppTypography const, or that face silently falls back offline.',
        );
      }
    });

    test('every declared font asset exists, is non-empty, and is referenced', () {
      for (final assets in families.values) {
        for (final asset in assets) {
          final file = File(asset);
          expect(file.existsSync(), isTrue, reason: 'missing font asset: $asset');
          expect(file.lengthSync(), greaterThan(0), reason: 'empty font asset: $asset');
          expect(
            pubspec,
            contains('asset: $asset'),
            reason: 'pubspec.yaml must reference font asset: $asset',
          );
        }
      }
    });

    test('OFL licenses are bundled and registered for attribution', () {
      for (final license in licenseAssets) {
        final file = File(license);
        expect(file.existsSync(), isTrue, reason: 'missing license: $license');
        expect(file.readAsStringSync(), contains('SIL OPEN FONT LICENSE'));
        expect(pubspec, contains('- $license'),
            reason: 'license must be a bundled asset: $license');
      }
      final bootstrap = read('lib/core/theme/font_bootstrap.dart');
      expect(bootstrap, contains('LicenseRegistry.addLicense'));
      expect(bootstrap, contains('allowRuntimeFetching = false'));
      expect(read('lib/main.dart'), contains('configureBundledFonts()'));
    });

    test('no GoogleFonts.getFont remains in lib/ (CDN path is gone)', () {
      final offenders = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('GoogleFonts.getFont'))
          .map((f) => f.path)
          .toList();
      expect(
        offenders,
        isEmpty,
        reason:
            'GoogleFonts.getFont fetches from the CDN at runtime — breaks offline '
            'first-launch branding (#103). Use AppTypography helpers (native fonts).',
      );
    });
  });
}
