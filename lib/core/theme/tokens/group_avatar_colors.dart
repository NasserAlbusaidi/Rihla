import 'package:flutter/material.dart';

/// Deterministic group avatar color slots.
///
/// Group ID → stable hash → slot index → color (theme-aware via
/// `context.colors.groupAvatarSlot(String groupId)` on [AppColorTokens]).
///
/// 5 slots per brightness. Dart's `String.hashCode` is NOT guaranteed
/// stable across Dart versions — callers rely on the `_stableGroupHash`
/// helper in `color_tokens.dart` which folds `codeUnits` with a fixed
/// constant so the slot assignment persists across app upgrades.
class AppGroupAvatarColors {
  const AppGroupAvatarColors._();

  static const List<Color> lightSlots = [
    // design-token-justified: avatar slot 0 light — primary teal
    Color(0xFF0D7B74),
    // design-token-justified: avatar slot 1 light — terracotta (focusBorderWarm)
    Color(0xFFCC6B49),
    // design-token-justified: avatar slot 2 light — success emerald
    Color(0xFF10B981),
    // design-token-justified: avatar slot 3 light — warning amber
    Color(0xFFF59E0B),
    // design-token-justified: avatar slot 4 light — warm umber
    Color(0xFF7C6E5A),
  ];

  static const List<Color> darkSlots = [
    // design-token-justified: avatar slot 0 dark — teal 400 lightened for WCAG 3:1 on Slate 800
    Color(0xFF14B8A6),
    // design-token-justified: avatar slot 1 dark — terracotta lightened
    Color(0xFFEBA480),
    // design-token-justified: avatar slot 2 dark — emerald 400
    Color(0xFF34D399),
    // design-token-justified: avatar slot 3 dark — amber 400
    Color(0xFFFBBF24),
    // design-token-justified: avatar slot 4 dark — warm umber lightened
    Color(0xFFA89A82),
  ];
}
