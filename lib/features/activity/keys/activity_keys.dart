import 'package:flutter/material.dart';

abstract final class ActivityKeys {
  // Screen key
  static const screen = Key('activity_feed_screen');

  /// The paginated activity ListView (distinguishes it from the shimmer's ListView in tests).
  static const feedList = Key('activity_feed_list');

  /// EmptyStateView shown on a failed initial load (distinguishes error from the no-activity empty state).
  static const errorView = Key('activity_error_view');

  // #808 PR3 — cross-group Activity search.
  /// Top-bar toggle that opens/closes the inline search field.
  static const searchToggle = Key('activity_search_toggle');

  /// The inline search TextField shown between the filter strip and the list.
  static const searchField = Key('activity_search_field');

  /// The "search older activity" button (list footer + zero-match empty state).
  static const searchOlderButton = Key('activity_search_older');
}
