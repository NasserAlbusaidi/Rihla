import 'package:flutter/material.dart';

abstract final class ActivityKeys {
  // Screen key
  static const screen = Key('activity_feed_screen');

  /// The paginated activity ListView (distinguishes it from the shimmer's ListView in tests).
  static const feedList = Key('activity_feed_list');

  /// EmptyStateView shown on a failed initial load (distinguishes error from the no-activity empty state).
  static const errorView = Key('activity_error_view');
}
