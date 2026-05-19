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
