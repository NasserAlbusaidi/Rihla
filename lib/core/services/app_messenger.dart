import 'package:flutter/material.dart';

/// Global key for the root `ScaffoldMessenger`, mounted on `MaterialApp.router`
/// in `main.dart`. Lets services and providers surface user-visible feedback
/// (success/failure SnackBars) without owning a `BuildContext`.
///
/// Today's only caller is the email-link recovery bootstrap, which needs to
/// report completion outcome regardless of which screen the user is on when
/// the deep link arrives.
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
