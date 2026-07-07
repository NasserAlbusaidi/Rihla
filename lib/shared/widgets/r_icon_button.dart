import 'package:flutter/material.dart';

import '../../core/theme/tokens/domain_aliases.dart';

/// Visual treatment for [RIconButton].
enum RIconButtonVariant {
  /// Filled paper circle with a soft elevation — for headers that sit OVER
  /// content/imagery, where the icon needs contrast against a busy backdrop
  /// (group hero, ledger band, event command center).
  paper,

  /// Transparent bare circle — for headers on a plain scaffold background
  /// (settings, activity, join/create), where a filled chip would read heavy.
  ghost,
}

/// The shared header icon button — back, close, share, settings, search…
///
/// Consolidates the hand-rolled `_PaperIconButton` (×3), `_GhostIconButton`,
/// `_BackButton`, the filled-square `IconButton`, and the Material
/// `BackButton`/`CloseButton` that had drifted across the nav screens (#490).
///
/// The caller passes its own [onTap] verbatim, so each screen keeps its exact
/// back-guard (`canPop() ? pop()` / `canPop() ? pop() : go('/home')` / action
/// callback) — this widget changes only the chrome, never the navigation.
class RIconButton extends StatelessWidget {
  const RIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.variant = RIconButtonVariant.paper,
    this.tooltip,
    this.semanticLabel,
    this.iconSize,
  });

  final IconData icon;
  final VoidCallback onTap;
  final RIconButtonVariant variant;

  /// Hover/long-press tooltip (was carried by the paper variant call sites).
  final String? tooltip;

  /// Accessibility label for screen readers (was carried by the share/invite
  /// paper buttons via `Semantics`).
  final String? semanticLabel;

  /// Overrides the per-variant default glyph size (paper 18, ghost 20).
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isPaper = variant == RIconButtonVariant.paper;
    final glyph = Icon(
      icon,
      size: iconSize ?? (isPaper ? 18 : 20),
      color: colors.textPrimary,
    );

    // The visible chip: a paper-filled circle (elevated) for headers over
    // content, or a bare glyph on a plain background.
    final Widget visible = isPaper
        ? Material(
            color: colors.cardSurface.withValues(alpha: 0.94),
            shape: const CircleBorder(),
            elevation: 1,
            child: SizedBox(width: 36, height: 36, child: Center(child: glyph)),
          )
        : SizedBox(width: 40, height: 40, child: Center(child: glyph));

    // Hit target: 48dp over content (Material a11y minimum, pinned by
    // group_detail_navigation_test); 44dp on plain headers — the DESIGN.md
    // §4 floor ("never ship a tap target under 44dp") — which fits exactly
    // inside the 44dp settings/join top bars (a 48dp box would overflow
    // them).
    final double hitSize = isPaper ? 48 : 44;
    Widget result = SizedBox(
      width: hitSize,
      height: hitSize,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkResponse(
          onTap: onTap,
          radius: hitSize / 2,
          customBorder: const CircleBorder(),
          child: Center(child: visible),
        ),
      ),
    );

    if (semanticLabel != null) {
      result = Semantics(button: true, label: semanticLabel, child: result);
    }
    if (tooltip != null) {
      result = Tooltip(message: tooltip!, child: result);
    }
    return result;
  }
}
