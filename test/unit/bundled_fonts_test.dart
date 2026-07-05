import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safar/core/theme/font_bootstrap.dart';

/// Guards the offline-branding contract from #103 and the bundle-size contract
/// from #636: brand faces are bundled as app assets and resolved natively, never
/// fetched from the Google Fonts CDN. The Arabic wordmark uses a deliberately
/// small Reem Kufi subset, not the full variable face.
void main() {
  String read(String path) => File(path).readAsStringSync();

  // family name -> the variable/static .ttf assets that must back it.
  const families = <String, List<String>>{
    'Bricolage Grotesque': [
      'assets/fonts/BricolageGrotesque-600.ttf',
      'assets/fonts/BricolageGrotesque-700.ttf',
      'assets/fonts/BricolageGrotesque-800.ttf',
    ],
    'Zain': [
      'assets/fonts/Zain-400.ttf',
      'assets/fonts/Zain-700.ttf',
      'assets/fonts/Zain-800.ttf',
    ],
    'Spline Sans Mono': [
      'assets/fonts/SplineSansMono-400.ttf',
      'assets/fonts/SplineSansMono-500.ttf',
      'assets/fonts/SplineSansMono-700.ttf',
    ],
    'Rihla Arabic Display': ['assets/fonts/ReemKufi-RihlaWordmark.ttf'],
  };

  const licenseAssets = [
    'assets/fonts/OFL-Bricolage.txt',
    'assets/fonts/OFL-Zain.txt',
    'assets/fonts/OFL-SplineSansMono.txt',
    'assets/fonts/OFL-ReemKufi.txt',
  ];

  group('bundled brand fonts (#103)', () {
    final pubspec = read('pubspec.yaml');
    final tokens = read('lib/core/theme/tokens/typography_tokens.dart');

    test('every AppTypography family const is declared in pubspec fonts', () {
      // The const family literals the helpers use, byte-for-byte.
      expect(tokens, contains("static const String sansFamily = 'Zain';"));
      expect(
        tokens,
        contains("static const String monoFamily = 'Spline Sans Mono';"),
      );
      expect(
        tokens,
        contains(
          "static const String arabicDisplayFamily = 'Rihla Arabic Display';",
        ),
      );
      expect(
        tokens,
        contains(
          "static const String displayFamily = 'Bricolage Grotesque';",
        ),
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

    test(
      'every declared font asset exists, is non-empty, and is referenced',
      () {
        for (final assets in families.values) {
          for (final asset in assets) {
            final file = File(asset);
            expect(
              file.existsSync(),
              isTrue,
              reason: 'missing font asset: $asset',
            );
            expect(
              file.lengthSync(),
              greaterThan(0),
              reason: 'empty font asset: $asset',
            );
            expect(
              pubspec,
              contains('asset: $asset'),
              reason: 'pubspec.yaml must reference font asset: $asset',
            );
          }
        }
      },
    );

    test('OFL licenses are bundled and registered for attribution', () {
      for (final license in licenseAssets) {
        final file = File(license);
        expect(file.existsSync(), isTrue, reason: 'missing license: $license');
        expect(file.readAsStringSync(), contains('SIL OPEN FONT LICENSE'));
        expect(
          pubspec,
          contains('- $license'),
          reason: 'license must be a bundled asset: $license',
        );
      }
      final bootstrap = read('lib/core/theme/font_bootstrap.dart');
      expect(bootstrap, contains('LicenseRegistry.addLicense'));
      expect(bootstrap, contains('allowRuntimeFetching = false'));
      expect(read('lib/main.dart'), contains('configureBundledFonts()'));
    });

    test('Arabic wordmark does not ship the full Reem Kufi variable face', () {
      expect(
        pubspec,
        isNot(contains('assets/fonts/ReemKufi-Variable.ttf')),
        reason:
            'The full Reem Kufi variable font is not tree-shaken by Flutter and '
            'must not be bundled for the single Arabic wordmark use case (#636).',
      );

      final fullFace = File('assets/fonts/ReemKufi-Variable.ttf');
      expect(
        fullFace.existsSync(),
        isFalse,
        reason:
            'Keep the full Reem Kufi source font out of the app asset tree; '
            'regenerate the bounded wordmark subset from source control history '
            'if the Arabic logo text changes.',
      );

      final subset = File('assets/fonts/ReemKufi-RihlaWordmark.ttf');
      expect(subset.existsSync(), isTrue);
      expect(
        subset.lengthSync(),
        lessThanOrEqualTo(24 * 1024),
        reason:
            'The Reem Kufi asset should stay a tiny wordmark subset, not drift '
            'back toward the 127KB full variable face (#636).',
      );
    });

    test('Arabic display subset is only used for the wordmark', () {
      final offenders = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('arabicDisplay('))
          .map((f) => f.path)
          .where(
            (path) =>
                path != 'lib/shared/widgets/wordmark_logo.dart' &&
                path != 'lib/core/theme/tokens/typography_tokens.dart',
          )
          .toList();

      expect(
        offenders,
        isEmpty,
        reason:
            'AppTypography.arabicDisplay is backed by a wordmark-only font '
            'subset. Add a proper Arabic text font strategy before using it for '
            'general UI copy.',
      );
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

    test('configureBundledFonts disables google_fonts runtime fetching', () {
      GoogleFonts.config.allowRuntimeFetching = true;

      configureBundledFonts();

      expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
    });

    test('configureBundledFonts registers bundled OFL licenses', () async {
      configureBundledFonts();

      final seenPackages = <String>{};
      await for (final entry in LicenseRegistry.licenses) {
        seenPackages.addAll(entry.packages);
        if (families.keys.every(seenPackages.contains)) {
          break;
        }
      }

      expect(seenPackages, containsAll(families.keys));
    });
  });
}
