import 'package:flutter/material.dart' show MaterialLocalizations;
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

/// #1227 — `showDatePicker`'s own chrome (header date, year-list entries,
/// month/year title, the compact "yyyy/mm/dd" input field) is rendered by
/// `MaterialLocalizations`, not by any app-owned `DateFormat` call site.
/// #1226/#1215 forced `useNativeDigits = false` at every app `DateFormat`
/// construction, but that fix cannot reach here: `GlobalMaterialLocalizations
/// .delegate.load('ar')` builds ITS OWN internal `DateFormat`s (via
/// `intl.DateFormat.y('ar')` etc., inside flutter_localizations) with
/// `useNativeDigits` defaulting to true — the generated `ar` `DateSymbols`
/// carry `ZERODIGIT: '٠'` — and hands them to the generated
/// `MaterialLocalizationAr`, which the app never constructs directly.
/// DEC-5/#145 is Western digits everywhere.
///
/// Fix: a locale-scoped delegate, `ar` only, that builds the SAME
/// `MaterialLocalizationAr` class Flutter ships (via the public
/// `getMaterialTranslation` router in `generated_material_localizations
/// .dart`), but with `useNativeDigits = false` forced on every `DateFormat`
/// it hands to that constructor. Registered BEFORE
/// `GlobalMaterialLocalizations.delegate` in `AppLocalizations
/// .localizationsDelegates` (`lib/l10n/generated/app_localizations.dart`) —
/// the first delegate that supports a locale wins, so this one alone
/// answers for `ar` `MaterialLocalizations` and `GlobalMaterialLocalizations
/// .delegate` never gets asked to load `ar`.
///
/// `formatDecimal` (the calendar day-of-month grid, e.g. "19") is
/// deliberately NOT touched: it's backed by an intl `NumberFormat`, and
/// `intl`'s `NumberSymbols` has no native-digit field at all (verified
/// against the installed intl 0.20.2 — `NumberFormat.decimalPattern('ar')`
/// already renders `19`, never `١٩`) — the day grid was never affected by
/// this bug, so `decimalFormat`/`twoDigitZeroPaddedFormat` below are passed
/// straight through unmodified.
///
/// Month/weekday names and RTL layout are untouched: this only overrides
/// which `DateFormat` instances back the digit-bearing `format*` members —
/// `MaterialLocalizationAr`'s non-date-format members (RTL-affecting
/// strings, `narrowWeekdays`, `firstDayOfWeekIndex`) come from the same
/// locale data either way.
class WesternDigitsArMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const WesternDigitsArMaterialLocalizationsDelegate();

  static const String _localeName = 'ar';

  @override
  bool isSupported(Locale locale) => locale.languageCode == _localeName;

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    // Loads flutter_localizations' REAL `ar` DateSymbols (month/weekday
    // names, ZERODIGIT, …) into intl's global registry via Flutter's own
    // (private, unexported) loader — the same data
    // `GlobalMaterialLocalizations.delegate` would have used. Constructing
    // an `intl.DateFormat` for a locale whose data isn't loaded yet throws
    // `LocaleDataException`, so this must run first; the returned instance
    // itself is discarded — only its data-loading side effect is needed.
    //
    // Deliberately NOT `async`/`await`: `GlobalMaterialLocalizations.delegate
    // .load()` returns a `SynchronousFuture`, whose `.then()` runs its
    // callback IMMEDIATELY and stays synchronous if the callback returns a
    // plain value (`SynchronousFuture.then`, flutter/foundation). An `async`
    // function ALWAYS wraps its return in a real (microtask-scheduled)
    // `Future`, even when every awaited value is synchronous — that broke
    // `Localizations`' single-frame resolution for `ar` (an extra pending
    // frame `pumpRihlaApp`'s fixed pump budget doesn't cover), which
    // regressed `event_recap_screen_test.dart`'s ar-locale assertions until
    // caught by re-running the full suite. Chaining via `.then()` here
    // preserves the synchronous-resolution contract Flutter's own delegates
    // rely on.
    return GlobalMaterialLocalizations.delegate.load(locale).then((_) {
      // Mirrors the private pattern selection in flutter_localizations'
      // `_MaterialLocalizationsDelegate.load()` (material_localizations.dart)
      // for the `intl.DateFormat.localeExists(localeName)` branch — the one
      // 'ar' always takes, since the awaited load above guarantees its data
      // is loaded. `..useNativeDigits = false` is the identical mechanism
      // #1226 uses at every app-owned DateFormat site (DEC-5/#145).
      final fullYearFormat = intl.DateFormat.y(_localeName)
        ..useNativeDigits = false;
      final compactDateFormat = intl.DateFormat.yMd(_localeName)
        ..useNativeDigits = false;
      final shortDateFormat = intl.DateFormat.yMMMd(_localeName)
        ..useNativeDigits = false;
      final mediumDateFormat = intl.DateFormat.MMMEd(_localeName)
        ..useNativeDigits = false;
      final longDateFormat = intl.DateFormat.yMMMMEEEEd(_localeName)
        ..useNativeDigits = false;
      final yearMonthFormat = intl.DateFormat.yMMMM(_localeName)
        ..useNativeDigits = false;
      final shortMonthDayFormat = intl.DateFormat.MMMd(_localeName)
        ..useNativeDigits = false;

      // NumberFormat has no native-digit concept (see class doc) — passed
      // through exactly as flutter_localizations builds it.
      final decimalFormat = intl.NumberFormat.decimalPattern(_localeName);
      final twoDigitZeroPaddedFormat = intl.NumberFormat('00', _localeName);

      return getMaterialTranslation(
        locale,
        fullYearFormat,
        compactDateFormat,
        shortDateFormat,
        mediumDateFormat,
        longDateFormat,
        yearMonthFormat,
        shortMonthDayFormat,
        decimalFormat,
        twoDigitZeroPaddedFormat,
      )!;
    });
  }

  @override
  bool shouldReload(WesternDigitsArMaterialLocalizationsDelegate old) =>
      false;
}
