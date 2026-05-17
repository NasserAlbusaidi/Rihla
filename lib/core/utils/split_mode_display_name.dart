import '../../l10n/generated/app_localizations.dart';
import '../models/split_mode.dart';

/// Returns the localized display name for [mode].
///
/// Use this in UI surfaces instead of [SplitModeX.label] (which stays
/// English-only so the model file remains independent of `AppLocalizations`).
String splitModeDisplayName(SplitMode mode, AppLocalizations l10n) {
  return switch (mode) {
    SplitMode.equally => l10n.splitModeEqually,
    SplitMode.shares => l10n.splitModeShares,
    SplitMode.exact => l10n.splitModeExact,
    SplitMode.percent => l10n.splitModePercent,
  };
}
