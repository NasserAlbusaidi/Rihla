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

String formatShortMonthDay(BuildContext context, DateTime date) {
  return DateFormat.MMMd(localeNameOf(context)).format(date);
}

String formatShortMonthDayYear(BuildContext context, DateTime date) {
  return DateFormat.yMMMd(localeNameOf(context)).format(date);
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

String formatTimelineDayLabel(BuildContext context, DateTime ts, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(ts.year, ts.month, ts.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return context.l10n.timelineToday;
  if (diff == 1) return context.l10n.timelineYesterday;
  return formatShortMonthDay(context, ts);
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
