import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';

/// Ghost-variant icon button used in the home top bar. No background fill —
/// just an icon in a 44×44 tap target (#1077 §4 floor; the wireframe's 40×40
/// sat under it). The wireframe shows this as the notifications affordance on
/// the right of the top bar.
class IconCircle extends StatelessWidget {
  const IconCircle({
    super.key,
    required this.icon,
    required this.onTap,
    required this.badgeKey,
    this.showBadge = false,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;

  // #840 PR-4: drives the unread-dot Badge wrapping the icon below — the
  // Badge itself is always present (mirroring bottom_nav_shell.dart's
  // NavigationDestination icon) so `isLabelVisible` alone toggles the dot.
  final bool showBadge;
  final String? semanticLabel;

  // PR-5b: the internal Badge's key is per-instance now (was hardcoded to
  // HomeKeys.bellUnreadBadge) — a second IconCircle (the search button)
  // would otherwise collide on that key and break `find.byKey`/
  // `tester.widget<Badge>` lookups for BOTH icons.
  final Key badgeKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 44,
          height: 44,
          // Center, not a bare tight box: with the dot visible Badge wraps
          // its child in a Stack whose default alignment is topStart, so
          // under tight 44×44 constraints the glyph pinned to the top-start
          // corner — 10px off the badge-less glyph's centre-line. Centering
          // sizes the Badge to the glyph and hugs the dot to its corner,
          // matching bottom_nav_shell's NavigationDestination look.
          child: Center(
            child: Badge(
              key: badgeKey,
              isLabelVisible: showBadge,
              smallSize: 8,
              backgroundColor: colors.primary,
              child: Icon(icon, size: 20, color: colors.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
