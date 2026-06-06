/// Validation helpers for user-entered display / group / event names.
///
/// Mirrors the server-side rules check `isValidDisplayName` in
/// `security/firestore.rules`: 1–32 characters after trim, no control
/// characters (U+0000–U+001F or U+007F). Validating client-side gives the
/// user a friendly inline error instead of an opaque `permission-denied`
/// when the rules reject the write.
library;

const int kDisplayNameMaxLength = 32;
const String _reservedFormerMemberSuffix =
    ' (former '
    'member)';

/// True if [s] contains any C0 control character (U+0000–U+001F) or DEL
/// (U+007F). Allowing these in display names lets attackers smuggle
/// newlines into UI rendering and confuses downstream tooling
/// (logs, push notification bodies). Every printable Unicode code point
/// including non-Latin scripts is accepted.
bool _hasControlChar(String s) {
  for (final cu in s.codeUnits) {
    if (cu < 0x20 || cu == 0x7F) return true;
  }
  return false;
}

enum DisplayNameValidationError {
  empty,
  tooLong,
  controlCharacter,
  reservedWording,
}

/// Returns the validation error for [input], or `null` if it is valid.
DisplayNameValidationError? displayNameValidationError(String? input) {
  final raw = input ?? '';
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return DisplayNameValidationError.empty;
  }
  if (trimmed.length > kDisplayNameMaxLength) {
    return DisplayNameValidationError.tooLong;
  }
  if (_hasControlChar(raw)) {
    return DisplayNameValidationError.controlCharacter;
  }
  if (trimmed.endsWith(_reservedFormerMemberSuffix)) {
    return DisplayNameValidationError.reservedWording;
  }
  return null;
}

/// Returns a user-facing English error message, or `null` if [input] is valid.
///
/// Suitable for direct use as a `TextFormField.validator` in non-localized
/// contexts. Localized widgets should use `validateDisplayNameLocalized`.
String? validateDisplayName(String? input) {
  return switch (displayNameValidationError(input)) {
    DisplayNameValidationError.empty => "Name can't be empty.",
    DisplayNameValidationError.tooLong =>
      'Keep it to $kDisplayNameMaxLength characters or fewer.',
    DisplayNameValidationError.controlCharacter =>
      'Remove line breaks or special characters.',
    DisplayNameValidationError.reservedWording =>
      'That name uses reserved wording.',
    null => null,
  };
}

/// Collapses runs of internal whitespace and trims edges. Use before
/// persisting — the validator does not normalize for you.
String normalizeDisplayName(String input) {
  return input.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Max length for user free text (expense description/note, etc.).
///
/// Mirrors the server-side `validFreeText` check in `security/firestore.rules`
/// (#194): `value.size() <= 280`.
const int kFreeTextMaxLength = 280;

enum FreeTextValidationError {
  tooLong,
  controlCharacter,
}

/// Returns the validation error for free-text [input], or `null` if valid.
///
/// Mirrors the server `validFreeText` rule: empty is allowed (no minimum),
/// `<= 280` chars, and no C0/DEL control characters. The check runs on the
/// trimmed value because the write path persists `controller.text.trim()`
/// (empty becomes `null`), so the trimmed string is what the server validates.
FreeTextValidationError? freeTextValidationError(String? input) {
  final value = (input ?? '').trim();
  if (value.length > kFreeTextMaxLength) {
    return FreeTextValidationError.tooLong;
  }
  if (_hasControlChar(value)) {
    return FreeTextValidationError.controlCharacter;
  }
  return null;
}

/// Returns a user-facing English error message, or `null` if [input] is valid.
///
/// For localized widgets use `validateFreeTextLocalized`.
String? validateFreeText(String? input) {
  return switch (freeTextValidationError(input)) {
    FreeTextValidationError.tooLong =>
      'Keep it to $kFreeTextMaxLength characters or fewer.',
    FreeTextValidationError.controlCharacter =>
      'Remove line breaks or special characters.',
    null => null,
  };
}
