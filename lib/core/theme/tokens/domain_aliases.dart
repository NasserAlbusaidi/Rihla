import 'package:flutter/material.dart';

import 'color_tokens.dart';
import 'gradient_tokens.dart';
import 'shadow_tokens.dart';
import 'spacing_tokens.dart';

/// BuildContext extension methods for terse token access.
///
/// Usage:
/// ```dart
/// final primary = context.colors.primary;
/// final gap = context.spacing.space16;
/// final shadow = context.shadows.raised;
/// final gradient = context.gradient(AppGradients.terracotta);
/// ```
///
/// These use `!` (not `?.`) — extensions are registered at app startup
/// and their absence indicates a real programmer error (missing ThemeExtension
/// registration in ThemeData), not a recoverable runtime condition.
extension AppThemeExtensions on BuildContext {
  /// Access color tokens — [AppColorTokens].
  AppColorTokens get colors => Theme.of(this).extension<AppColorTokens>()!;

  /// Access spacing tokens — [AppSpacingTokens].
  AppSpacingTokens get spacing => Theme.of(this).extension<AppSpacingTokens>()!;

  /// Access shadow tokens — [AppShadowTokens].
  AppShadowTokens get shadows => Theme.of(this).extension<AppShadowTokens>()!;

  /// Resolve a named gradient pair for the active brightness.
  ///
  /// `context.gradient(AppGradients.terracotta)` returns `.light` on light
  /// theme and `.dark` on dark theme.
  LinearGradient gradient(AppGradientPair pair) =>
      Theme.of(this).brightness == Brightness.dark ? pair.dark : pair.light;
}
