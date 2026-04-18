import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WCAG 2.1 relative luminance.
///
/// Shared across [design_tokens_test.dart] and [dark_theme_contrast_test.dart]
/// (Phase 37 Wave 5) so both suites use an identical algorithm.
double relativeLuminance(Color color) {
  double linearize(double channel) {
    return channel <= 0.03928
        ? channel / 12.92
        : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = linearize(color.r);
  final g = linearize(color.g);
  final b = linearize(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// WCAG 2.1 contrast ratio between a foreground and background color.
///
/// Returns a value in [1.0, 21.0]. AA threshold: 4.5:1 for normal text,
/// 3.0:1 for large text / UI elements. AAA threshold: 7.0:1.
double contrastRatio(Color foreground, Color background) {
  final l1 = relativeLuminance(foreground);
  final l2 = relativeLuminance(background);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}
