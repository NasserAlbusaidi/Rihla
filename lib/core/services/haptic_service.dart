import 'package:flutter/services.dart';

/// HapticService provides tactical feedback patterns for Safar.
/// Mimics "Outdoor Gear" tactile clicks and provides high-priority alerts.
class HapticService {
  /// Subtle "click" for keypad buttons to simulate tactical gear.
  static Future<void> lightClick() async {
    await HapticFeedback.lightImpact();
  }

  /// Double-tap vibration for successful actions (e.g., Claim, Payment).
  static Future<void> success() async {
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.mediumImpact();
  }

  /// Selection changed (for segmented controls or tabs).
  static Future<void> selection() async {
    await HapticFeedback.selectionClick();
  }

  /// Standard medium impact for general actions.
  static Future<void> medium() async {
    await HapticFeedback.mediumImpact();
  }
}
