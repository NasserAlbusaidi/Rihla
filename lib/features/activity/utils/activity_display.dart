import '../../../l10n/generated/app_localizations.dart';
import '../../../core/services/money_serializer.dart';
import '../../groups/models/group_activity_log_model.dart';
import '../models/activity_log_model.dart';

String localizedEventActivityText(AppLocalizations l10n, ActivityLog log) {
  final category = log.category.toUpperCase();
  final action = log.eventType.toUpperCase();
  return switch ((category, action)) {
    ('MONEY', 'CREATE') => l10n.activityEventMoneyCreated,
    ('MONEY', 'UPDATE') => l10n.activityEventMoneyUpdated,
    ('MONEY', 'DELETE') => l10n.activityEventMoneyDeleted,
    ('GEAR', 'CREATE') => l10n.activityEventGearCreated,
    ('GEAR', 'UPDATE') => l10n.activityEventGearUpdated,
    ('GEAR', 'DELETE') => l10n.activityEventGearDeleted,
    ('DOCS', 'CREATE') => l10n.activityEventDocsCreated,
    ('DOCS', 'UPDATE') => l10n.activityEventDocsUpdated,
    ('DOCS', 'DELETE') => l10n.activityEventDocsDeleted,
    _ => log.logText,
  };
}

String localizedGroupActivityText(AppLocalizations l10n, GroupActivityLog log) {
  final eventName = log.metadata['eventName'] as String?;
  final memberName = log.metadata['memberName'] as String?;
  final memberAction = log.metadata['memberAction'] as String?;
  return switch (log.type) {
    'group_settlement' => l10n.activityGroupSettlementDescription,
    'event_created' =>
      eventName == null || eventName.isEmpty
          ? l10n.activityGroupEventCreatedGeneric
          : l10n.activityGroupEventCreated(eventName),
    'event_deleted' =>
      eventName == null || eventName.isEmpty
          ? l10n.activityGroupEventDeletedGeneric
          : l10n.activityGroupEventDeleted(eventName),
    'member_joined' => l10n.activityGroupMemberJoined,
    'member_left' =>
      memberAction == 'removed'
          ? (memberName == null || memberName.isEmpty
                ? log.description
                : l10n.activityGroupMemberRemoved(memberName))
          : l10n.activityGroupMemberLeft,
    _ => log.description,
  };
}
/// Currency for an amount-bearing group-activity row (#382 PR-4).
///
/// Settlement logs stamp `metadata.currency` with the bucket currency the
/// settlement was recorded in; legacy rows lack the key. The metadata map is
/// client-written by any member, so an unsupported value also falls back to
/// the group currency rather than driving display precision.
String activityAmountCurrency(GroupActivityLog log, String fallback) {
  final raw = log.metadata['currency'];
  if (raw is String && MoneySerializer.supportedCurrencies.contains(raw)) {
    return raw;
  }
  return fallback;
}
