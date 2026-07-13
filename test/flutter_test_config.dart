import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safar/core/services/draft_navigation_guard.dart';

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
  // #1208: ExpenseEditorBody.initState registers a DraftNavigationGuard, so
  // every editor-pumping test file touches the process-wide singleton — a
  // guard left registered by an incomplete dispose (e.g. a widget torn down
  // mid-transition) would otherwise leak into the next test in the same
  // file. Guard-focused test files ALSO reset in their own setUp/tearDown
  // for clarity; this is the whole-suite backstop.
  tearDown(DraftNavigationGuard.instance.reset);
  await testMain();
}
