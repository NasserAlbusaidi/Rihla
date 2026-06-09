import 'dart:async';

import 'package:flutter/services.dart';

/// HapticService provides tactical feedback patterns for Safar.
/// Mimics "Outdoor Gear" tactile clicks and provides high-priority alerts.
///
/// All methods are fire-and-forget (`void`): haptic feedback is UI garnish that
/// must never block a caller, and no call site awaits it. Returning `void`
/// keeps the ~18 call sites free of `unawaited_futures` noise (#350); the single
/// detached future lives here.
class HapticService {
  /// Subtle "click" for keypad buttons to simulate tactical gear.
  static void lightClick() {
    unawaited(HapticFeedback.lightImpact());
  }

  /// Double-tap vibration for successful actions (e.g., Claim, Payment).
  static void success() {
    unawaited(_success());
  }

  static Future<void> _success() async {
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.mediumImpact();
  }

  /// Selection changed (for segmented controls or tabs).
  static void selection() {
    unawaited(HapticFeedback.selectionClick());
  }

  /// Standard medium impact for general actions.
  static void medium() {
    unawaited(HapticFeedback.mediumImpact());
  }
}
