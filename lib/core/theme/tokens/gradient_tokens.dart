import 'package:flutter/material.dart';

/// Named gradient pair — one [LinearGradient] per brightness.
///
/// See [AppGradients] for available pairs. Resolve for the active theme via
/// the `context.gradient(pair)` extension in `domain_aliases.dart`.
class AppGradientPair {
  const AppGradientPair({required this.light, required this.dark});

  final LinearGradient light;
  final LinearGradient dark;
}

/// Named gradient tokens with light + dark variants.
///
/// Usage:
/// ```dart
/// final gradient = context.gradient(AppGradients.terracotta);
/// ```
///
/// Every pair shares `begin` + `end` across brightnesses — only `colors`
/// differ. The `token_promotions_test.dart` test suite asserts this invariant.
class AppGradients {
  const AppGradients._();

  /// Terracotta — onboarding page 1, ledger hero.
  static const AppGradientPair terracotta = AppGradientPair(
    light: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      // design-token-justified: terracotta light gradient — onboarding + ledger hero
      colors: [Color(0xFFCC6B49), Color(0xFFE0896A)],
    ),
    dark: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      // design-token-justified: terracotta dark gradient — lightened for dark surfaces
      colors: [Color(0xFFEBA480), Color(0xFFF4B99A)],
    ),
  );

  /// Olive — onboarding page 2.
  static const AppGradientPair olive = AppGradientPair(
    light: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      // design-token-justified: olive light gradient — onboarding
      colors: [Color(0xFF7A8C5E), Color(0xFF8EA06E)],
    ),
    dark: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      // design-token-justified: olive dark gradient — lightened for dark surfaces
      colors: [Color(0xFFA8BA8A), Color(0xFFBCCB9E)],
    ),
  );

  /// Dusty teal — onboarding page 3.
  static const AppGradientPair teal = AppGradientPair(
    light: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      // design-token-justified: dusty teal light gradient — onboarding
      colors: [Color(0xFF0D7B74), Color(0xFF0A9187)],
    ),
    dark: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      // design-token-justified: teal dark gradient — teal 400-500
      colors: [Color(0xFF14B8A6), Color(0xFF2DD4BF)],
    ),
  );

  /// Warm brown — activity hero (non-ledger module accent per CLAUDE.md).
  static const AppGradientPair gray = AppGradientPair(
    light: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      // design-token-justified: warm brown gradient — activity hero
      colors: [Color(0xFFA67C5B), Color(0xFFC29A7A)],
    ),
    dark: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      // design-token-justified: warm brown dark gradient — lightened
      colors: [Color(0xFFC7A688), Color(0xFFDBBCA2)],
    ),
  );
}
