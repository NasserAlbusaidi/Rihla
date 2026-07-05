import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/theme/tokens/motion_tokens.dart';
import 'package:safar/features/ledger/widgets/ledger_hero_block.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/animations/stamp_entrance.dart';

/// Wires the `StampMotion` seal-settle entrance onto the ledger's settled
/// ("All square") badge: it should press in — scale `beginScale`->1.0,
/// unrotate `beginTurns`->0 — driven by `context.motion.stamp`, and degrade
/// to an opacity-only fade under `MediaQuery.disableAnimations`.
void main() {
  Future<void> pumpSettled(
    WidgetTester tester, {
    bool disableAnimations = false,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: LedgerHeroStatement(
              kind: LedgerHeroKind.settled,
              amount: Decimal.zero,
              currency: 'OMR',
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('settled badge stamps in: scale/rotation animate then settle', (
    tester,
  ) async {
    await pumpSettled(tester);
    await tester.pump();

    expect(find.text('All square.'), findsOneWidget);
    expect(find.text('SETTLED'), findsOneWidget);

    // Scope to StampEntrance's own descendants — MaterialApp's Android
    // ZoomPageTransitionsBuilder wraps the whole route in its own
    // (unrelated) ScaleTransition, so an unscoped find.byType would
    // over-match.
    final stampFinder = find.byType(StampEntrance);
    final scaleFinder = find.descendant(
      of: stampFinder,
      matching: find.byType(ScaleTransition),
    );
    final rotationFinder = find.descendant(
      of: stampFinder,
      matching: find.byType(RotationTransition),
    );
    expect(scaleFinder, findsOneWidget);
    expect(rotationFinder, findsOneWidget);

    // First frame (t=0, curve(0)==0) — pins the animation to the exact
    // `StampMotion.base` token values, not just "some" animated numbers.
    const stamp = StampMotion.base;
    expect(
      tester.widget<ScaleTransition>(scaleFinder).scale.value,
      closeTo(stamp.beginScale, 1e-6),
    );
    expect(
      tester.widget<RotationTransition>(rotationFinder).turns.value,
      closeTo(stamp.beginTurns, 1e-6),
    );

    // Half of the 300ms stamp duration — mid-flight, not yet settled.
    await tester.pump(const Duration(milliseconds: 150));
    final midScale = tester.widget<ScaleTransition>(scaleFinder).scale.value;
    final midTurns = tester
        .widget<RotationTransition>(rotationFinder)
        .turns
        .value;
    expect(midScale, isNot(1.0));
    expect(midTurns, isNot(0.0));

    await tester.pumpAndSettle();
    final endScale = tester.widget<ScaleTransition>(scaleFinder).scale.value;
    final endTurns = tester
        .widget<RotationTransition>(rotationFinder)
        .turns
        .value;
    expect(endScale, closeTo(1.0, 0.0001));
    expect(endTurns, closeTo(0.0, 0.0001));
  });

  testWidgets('reduced motion: opacity-only fade, no scale/rotation transform', (
    tester,
  ) async {
    await pumpSettled(tester, disableAnimations: true);
    await tester.pump();

    final stampFinder = find.byType(StampEntrance);
    expect(
      find.descendant(of: stampFinder, matching: find.byType(ScaleTransition)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: stampFinder,
        matching: find.byType(RotationTransition),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: stampFinder, matching: find.byType(FadeTransition)),
      findsOneWidget,
    );

    await tester.pumpAndSettle();
    expect(find.text('SETTLED'), findsOneWidget);
  });
}
