import 'package:flutter/widgets.dart';

import '../extensions/build_context_l10n.dart';
import 'name_validators.dart';

String? validateDisplayNameLocalized(BuildContext context, String? input) {
  return switch (displayNameValidationError(input)) {
    DisplayNameValidationError.empty => context.l10n.nameValidationEmpty,
    DisplayNameValidationError.tooLong => context.l10n.nameValidationTooLong(
      kDisplayNameMaxLength,
    ),
    DisplayNameValidationError.controlCharacter =>
      context.l10n.nameValidationControlChars,
    DisplayNameValidationError.reservedWording =>
      context.l10n.nameValidationReserved,
    null => null,
  };
}

/// Localized free-text validator for expense description/note fields (#220).
///
/// Reuses the surface-agnostic name-validation copy ("Keep it to N characters
/// or fewer." / "Remove line breaks or special characters.") since the messages
/// are identical; only the cap differs ([kFreeTextMaxLength]).
String? validateFreeTextLocalized(BuildContext context, String? input) {
  return switch (freeTextValidationError(input)) {
    FreeTextValidationError.tooLong => context.l10n.nameValidationTooLong(
      kFreeTextMaxLength,
    ),
    FreeTextValidationError.controlCharacter =>
      context.l10n.nameValidationControlChars,
    null => null,
  };
}
