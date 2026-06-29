import '../../../l10n/generated/app_localizations.dart';

/// The app-authored correction-note sentinel
/// ([AppLocalizations.settleUpCorrectionNote]) in EVERY supported locale. A
/// reversing settlement (#283) carries this note in the CORRECTOR's locale, so
/// recognizing it on read must not assume the viewer's locale matches. Computed
/// once. (#567)
final Set<String> _correctionNoteSentinels = {
  for (final locale in AppLocalizations.supportedLocales)
    lookupAppLocalizations(locale).settleUpCorrectionNote,
};

/// True when [note] marks a #283/#567 reversing correction — so the settle-up
/// history can render it as a correction (not another payment) and the #753
/// logical regroup/write can tell originals from their reverses across locales.
bool isCorrectionNote(String? note) =>
    note != null && _correctionNoteSentinels.contains(note);
