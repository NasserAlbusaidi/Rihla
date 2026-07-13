import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../extensions/build_context_l10n.dart';

String localeNameOf(BuildContext context) {
  final locale = Localizations.localeOf(context);
  final countryCode = locale.countryCode;
  return countryCode == null || countryCode.isEmpty
      ? locale.languageCode
      : '${locale.languageCode}_$countryCode';
}

// `useNativeDigits = false` on every DateFormat below enforces Western
// digits everywhere (DEC-5/#145): flutter_localizations' generated `ar`
// DateSymbols carry ZERODIGIT: '٠', which intl adopts by default per-locale,
// so without this flag every ar digit renders Arabic-Indic (#1215).

String formatShortMonthDay(BuildContext context, DateTime date) {
  return (DateFormat.MMMd(localeNameOf(context))..useNativeDigits = false)
      .format(date);
}

/// The same short month-day formatter as [formatShortMonthDay], but returned
/// once for reuse across a loop. Constructing a `DateFormat` parses the ICU
/// skeleton each time, so per-log calls in a day-grouping loop pay that cost N
/// times — hoist this out of the loop and call `.format(date)` per item (#634).
DateFormat shortMonthDayFormatter(BuildContext context) {
  return DateFormat.MMMd(localeNameOf(context))..useNativeDigits = false;
}

String formatShortMonthDayYear(BuildContext context, DateTime date) {
  return (DateFormat.yMMMd(localeNameOf(context))..useNativeDigits = false)
      .format(date);
}

/// Localized month + year, e.g. "Mar 2026" / "مارس 2026". Used for the recap
/// share-card caption stamp (#722).
String formatMonthYear(BuildContext context, DateTime date) {
  return (DateFormat.yMMM(localeNameOf(context))..useNativeDigits = false)
      .format(date);
}

String formatDateRangeShort(
  BuildContext context,
  DateTime? start,
  DateTime? end, {
  String? endOnlyPrefix,
}) {
  if (start != null && end != null) {
    return '${formatShortMonthDay(context, start)} '
        '${context.l10n.timelineRangeSeparator} '
        '${formatShortMonthDay(context, end)}';
  }
  if (start != null) return formatShortMonthDay(context, start);
  if (end != null) {
    final date = formatShortMonthDay(context, end);
    return endOnlyPrefix == null ? date : '$endOnlyPrefix $date';
  }
  return '';
}

String formatRelativeShort(BuildContext context, DateTime when) {
  final delta = DateTime.now().difference(when);
  if (delta.inMinutes < 1) return context.l10n.activityRelativeJustNow;
  if (delta.inHours < 1) {
    return context.l10n.activityRelativeMinutes(delta.inMinutes);
  }
  if (delta.inDays < 1) {
    return context.l10n.activityRelativeHours(delta.inHours);
  }
  return context.l10n.activityRelativeDays(delta.inDays);
}
