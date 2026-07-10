import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// Announces a blocking validation error to assistive tech (#1080).
///
/// Single chokepoint on [SemanticsService.sendAnnouncement] —
/// `SemanticsService.announce` is deprecated (multi-window incompatible), so
/// every screen routes through here rather than re-deriving the view/direction
/// boilerplate.
void announceValidationError(BuildContext context, String message) {
  unawaited(
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
      assertiveness: Assertiveness.assertive,
    ),
  );
}
