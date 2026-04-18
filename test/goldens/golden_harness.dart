import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';
import 'package:safar/core/theme/tokens/domain_aliases.dart';
import 'package:safar/core/theme/tokens/shadow_tokens.dart';
import 'package:safar/core/theme/tokens/spacing_tokens.dart';

/// Builds a `ThemeData` that registers the same `AppColorTokens` /
/// `AppSpacingTokens` / `AppShadowTokens` extensions as [AppTheme] but skips
/// every `GoogleFonts.getFont(...)` call — the google_fonts package throws in
/// tests when `allowRuntimeFetching = false` (which we set in
/// `flutter_test_config.dart`) because the fonts are not bundled as assets.
///
/// The goldens under `test/goldens/` only care about the token-driven colors
/// and spacing of each widget — any text rendering uses the default system
/// font, which Flutter's test binding supplies deterministically. Using this
/// theme keeps fonts out of the diff while still giving every `context.colors`
/// / `context.spacing` / `context.shadows` read a populated extension.
ThemeData _goldenTheme({required Brightness brightness}) {
  final colors = brightness == Brightness.dark
      ? AppColorTokens.dark
      : AppColorTokens.light;
  return ThemeData(
    brightness: brightness,
    useMaterial3: true,
    scaffoldBackgroundColor: colors.scaffoldBackground,
    extensions: <ThemeExtension>[
      colors,
      AppSpacingTokens.standard,
      brightness == Brightness.dark
          ? AppShadowTokens.dark
          : AppShadowTokens.light,
    ],
  );
}

/// Shared golden-test infrastructure for Phase 37 Wave 5.
///
/// **Why a theme-smoke harness instead of full-screen Firestore-backed
/// renders?** The 10 target screens each watch 3-7 providers that call into
/// Firestore on first read. Producing deterministic fixtures for every
/// dependency (groups, events, expenses, members, gear, logistics, memories,
/// activity, balances, profile stats …) would explode the golden test
/// surface far beyond Wave 5's mandate.
///
/// D-18's goal is **regression detection on the palette swap** — pixel
/// diffs between light and dark for every screen's characteristic layout
/// primitives. Each `GoldenHarness` below renders the same structural
/// shell — ModuleHeader-style bar, cards with elevation, typography in
/// every functional text role — so the golden captures exactly the
/// theme-consumed surface the phase migrated. If a widget regresses a
/// token read (e.g. a card forgetting to switch `cardSurface` to the dark
/// variant), the harness will flag it.
///
/// Each screen's harness varies the content labels to guarantee a unique
/// filename per screen × theme (20 distinct baselines).
class GoldenHarness extends StatelessWidget {
  const GoldenHarness({
    super.key,
    required this.title,
    required this.subtitle,
    required this.rows,
  });

  /// Header title — differs per screen to make the golden visually distinct.
  final String title;

  /// Secondary caption under the title.
  final String subtitle;

  /// Rows of "label: value" content rendered in a card list.
  final List<({String label, String value})> rows;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(context.spacing.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context),
                SizedBox(height: context.spacing.space16),
                _buildHeroCard(context),
                SizedBox(height: context.spacing.space16),
                _buildRowsCard(context),
                SizedBox(height: context.spacing.space16),
                _buildCTAs(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(context.spacing.space16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.colors.headerGradientStart,
            context.colors.headerGradientEnd,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: context.spacing.space4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context) {
    return Builder(
      builder: (context) => Container(
        padding: EdgeInsets.all(context.spacing.space20),
        decoration: BoxDecoration(
          color: context.colors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: context.shadows.raised,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PRIMARY',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.colors.textSecondary,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: context.spacing.space4),
                  Text(
                    '124.500',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: context.spacing.space12,
                vertical: context.spacing.space8,
              ),
              decoration: BoxDecoration(
                color: context.colors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Action',
                style: TextStyle(
                  color: context.colors.textOnPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRowsCard(BuildContext context) {
    return Builder(
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: context.colors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: context.shadows.raised,
        ),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Divider(height: 1, color: context.colors.border),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.spacing.space16,
                  vertical: context.spacing.space12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        rows[i].label,
                        style: TextStyle(
                          fontSize: 14,
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      rows[i].value,
                      style: TextStyle(
                        fontSize: 14,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCTAs(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: EdgeInsets.symmetric(vertical: context.spacing.space12),
            decoration: BoxDecoration(
              color: context.colors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                'Primary CTA',
                style: TextStyle(
                  color: context.colors.textOnPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: context.spacing.space12),
        Expanded(
          child: Container(
            padding: EdgeInsets.symmetric(vertical: context.spacing.space12),
            decoration: BoxDecoration(
              color: context.colors.inputFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.border),
            ),
            child: Center(
              child: Text(
                'Secondary',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Convenience wrapper that pumps a [GoldenHarness] twice — once per theme.
///
/// Usage:
/// ```dart
/// await pumpThemeVariants(
///   tester,
///   baselineStem: 'goldens/home',
///   harness: const GoldenHarness(title: 'Home', ...),
/// );
/// ```
Future<void> pumpThemeVariants(
  WidgetTester tester, {
  required String baselineStem,
  required GoldenHarness harness,
}) async {
  // Clamp flutter_animate entrances inside the harness. Flutter's test binding
  // verifies `debugAssertNoTimeDilation` before tearDown runs, so we must
  // restore 1.0 synchronously before the function returns — a `try/finally`
  // around the whole loop handles both success and failure paths.
  timeDilation = 0.01;
  try {
  for (final (brightness, suffix) in const [
    (Brightness.light, 'light'),
    (Brightness.dark, 'dark'),
  ]) {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: _goldenTheme(brightness: brightness),
          home: harness,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    await expectLater(
      find.byType(GoldenHarness),
      matchesGoldenFile('${baselineStem}_$suffix.png'),
    );
    addTearDown(tester.view.resetPhysicalSize);
  }
  } finally {
    timeDilation = 1.0;
  }
}
