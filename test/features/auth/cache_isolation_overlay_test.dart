import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/router/app_router.dart';
import 'package:safar/core/services/cache_isolation_controller.dart';
import 'package:safar/main.dart';

void main() {
  testWidgets(
    'engaged isolation short-circuits SafarApp to the overlay before the router '
    'is ever built (#45 §3.7)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cacheIsolationProvider.overrideWith((ref) => true),
            // If the short-circuit (build) or the post-frame guard failed,
            // SafarApp would read routerProvider and this throw would surface
            // the regression.
            routerProvider.overrideWith(
              (ref) => throw StateError('router must not build while isolated'),
            ),
          ],
          child: const SafarApp(),
        ),
      );
      // One frame only — the splash's indeterminate progress bar never settles.
      await tester.pump();

      expect(
        find.byKey(const Key('cache-isolation-overlay')),
        findsOneWidget,
      );
    },
  );
}
