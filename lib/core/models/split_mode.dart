/// How an expense total is divided across its participants.
///
/// Only [equally] is wired through `BalanceCalculator` and the custom-split
/// sheet today. [shares], [exact], and [percent] exist so the picker UI and
/// the user's stored preference round-trip; the actual distribution editors
/// land with T4.N (`docs/plans/coming-soon-implementations.md`).
enum SplitMode { equally, shares, exact, percent }

extension SplitModeX on SplitMode {
  /// Stable string used for SharedPreferences persistence. Keep these values
  /// frozen — they're stored on user devices.
  String get storageKey => switch (this) {
    SplitMode.equally => 'equally',
    SplitMode.shares => 'shares',
    SplitMode.exact => 'exact',
    SplitMode.percent => 'percent',
  };

  /// Short label shown in pickers and trailing rows.
  String get label => switch (this) {
    SplitMode.equally => 'Equal',
    SplitMode.shares => 'Shares',
    SplitMode.exact => 'Exact amounts',
    SplitMode.percent => 'Percent',
  };

  /// Whether this mode is functional today. Non-equal modes are surfaced in
  /// the picker but locked behind T4.N.
  bool get isAvailable => this == SplitMode.equally;
}

SplitMode splitModeFromStorage(String? raw) {
  for (final mode in SplitMode.values) {
    if (mode.storageKey == raw) return mode;
  }
  return SplitMode.equally;
}
