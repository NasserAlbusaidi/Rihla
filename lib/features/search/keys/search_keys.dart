import 'package:flutter/material.dart';

abstract final class SearchKeys {
  // Screen key
  static const screen = Key('search_screen');

  /// The always-visible search TextField.
  static const field = Key('search_field');

  /// The visible "Groups and events, including past events" scope line —
  /// rendered only once results exist (PR-5b Gate R2 P1 fix).
  static const scopeLabel = Key('search_scope_label');

  /// Zero-matches state for a non-empty query.
  static const emptyState = Key('search_empty_state');

  /// Pre-query guidance (muted icon + scope line) shown before the first
  /// keystroke (#1012, reverses the PR-5b empty-q blank-panel pin).
  static const preQueryGuidance = Key('search_pre_query_guidance');
}
