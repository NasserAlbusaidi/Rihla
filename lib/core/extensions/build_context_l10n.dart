import 'package:flutter/widgets.dart';

import '../../l10n/generated/app_localizations.dart';

/// Shorthand for `AppLocalizations.of(context)`.
///
/// Throws if no [AppLocalizations] is registered above [context] (i.e., the
/// widget tree has no `localizationsDelegates` configured). All app-booting
/// production paths and `pumpRihlaApp` test helper wire delegates by default,
/// so a missing delegate indicates a misconfigured test.
extension BuildContextL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
