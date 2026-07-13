import 'package:flutter/widgets.dart';

import '../core/utils/ar_western_digits_material_localizations.dart';
import 'generated/app_localizations.dart';

/// The app's localization delegates, with the #1227 Western-digits `ar`
/// `MaterialLocalizations` override (calendar/date-picker chrome) prepended.
///
/// [WesternDigitsArMaterialLocalizationsDelegate] MUST come before
/// `GlobalMaterialLocalizations.delegate` — `Localizations` resolves, per
/// requested delegate type, the FIRST delegate in the list whose
/// `isSupported` returns true (`_loadAll` in
/// `flutter/src/widgets/localizations.dart`), so ordering here is the
/// mechanism, not a convenience.
///
/// Use this constant everywhere the app reaches for
/// `AppLocalizations.localizationsDelegates` — every `MaterialApp`/
/// `MaterialApp.router` construction site in `main.dart`, and the
/// `pumpRihlaApp` test helper (which exists specifically to mirror the real
/// boot chain). `AppLocalizations.localizationsDelegates` itself lives in a
/// `flutter gen-l10n`-generated file and gets overwritten on every
/// regeneration, so the override can't be added there.
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates = [
  WesternDigitsArMaterialLocalizationsDelegate(),
  ...AppLocalizations.localizationsDelegates,
];
