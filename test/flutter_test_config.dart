import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Global flutter_test harness.
///
/// Disables google_fonts runtime fetching — tests run without network and the
/// runtime loader throws if it attempts to fetch. Golden tests under
/// `test/goldens/` rely on this being set for the whole suite.
///
/// `timeDilation` is left at the default here (1.0) and is clamped per-test
/// inside the golden harness: Flutter's test binding verifies
/// `timeDilation == 1.0` between tests, so setting it globally leaks and
/// trips `debugAssertNoTimeDilation`.
///
/// Per Phase 37 Wave 5 RESEARCH §"Code Patterns 3".
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await testMain();
}
