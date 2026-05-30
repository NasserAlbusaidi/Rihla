import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart';

/// Maps each bundled font license asset to the family names it covers.
const Map<String, List<String>> _fontLicenseAssets = {
  'assets/fonts/OFL-Geist.txt': ['Geist'],
  'assets/fonts/OFL-GeistMono.txt': ['Geist Mono'],
  'assets/fonts/OFL-ReemKufi.txt': ['Reem Kufi'],
  'assets/fonts/OFL-InstrumentSerif.txt': ['Instrument Serif'],
};

/// Brand faces (Geist / Geist Mono / Reem Kufi / Instrument Serif) are bundled
/// as app assets and resolved natively by the Flutter font engine, so no font
/// is ever fetched at runtime (#103).
///
/// This disables `google_fonts` runtime CDN fetching as a regression guard —
/// any stray runtime google-fonts lookup that slips back in will throw loudly
/// in dev instead of silently hitting `gstatic.com` (and breaking offline
/// first-launch branding) — and registers the SIL OFL 1.1 license for each
/// bundled face so it appears in the app's open-source licenses page.
void configureBundledFonts() {
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(() async* {
    for (final entry in _fontLicenseAssets.entries) {
      try {
        final text = await rootBundle.loadString(entry.key);
        yield LicenseEntryWithLineBreaks(entry.value, text);
      } catch (error) {
        if (kDebugMode) {
          debugPrint('Font license load failed for ${entry.key}: $error');
        }
      }
    }
  });
}
