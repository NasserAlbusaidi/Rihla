/// How an expense total is divided across its participants.
///
/// All four modes are wired end-to-end: the data layer round-trips through
/// `Expense.splitMode`/`splitDistribution`, `BalanceCalculator` allocates
/// each mode, and the custom-split sheet edits them (T4.N shipped 2026-05).
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

  /// Whether this mode is functional today. All four modes ship in T4.N;
  /// kept as a getter so callers don't have to depend on the enum directly.
  bool get isAvailable => true;
}

SplitMode splitModeFromStorage(String? raw) {
  for (final mode in SplitMode.values) {
    if (mode.storageKey == raw) return mode;
  }
  return SplitMode.equally;
}
