import 'package:decimal/decimal.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../core/services/money_serializer.dart';
import '../../../core/utils/formatters.dart';
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

/// Every metadata read in this file goes through a value-domain guard, never a
/// raw cast: the map is client-forgeable (`firestore.rules` checks only
/// `metadata is map`), and activityMatchesQuery runs these helpers over EVERY
/// loaded entry in the parent build — one forged value would ErrorWidget the
/// whole Activity tab (same class as the amountFils/legacy-amount guards).
/// A non-String value reads as absent → the existing generic/fallback path.
String? _metadataString(GroupActivityLog log, String key) {
  final value = log.metadata[key];
  return value is String ? value : null;
}

String localizedGroupActivityText(AppLocalizations l10n, GroupActivityLog log) {
  final eventName = _metadataString(log, 'eventName');
  final memberName = _metadataString(log, 'memberName');
  final memberAction = _metadataString(log, 'memberAction');
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
    // #808 PR2: server-fan-in expense entries. GENERIC by design (D-PR2-1) —
    // metadata carries no expense label, so we localize by type + eventName and
    // show the amount separately (via activityAmount); the English fan-in
    // description (with the embedded label) is intentionally not surfaced.
    'expense_added' =>
      eventName == null || eventName.isEmpty
          ? l10n.activityGroupExpenseAddedGeneric
          : l10n.activityGroupExpenseAdded(eventName),
    'expense_edited' =>
      eventName == null || eventName.isEmpty
          ? l10n.activityGroupExpenseEditedGeneric
          : l10n.activityGroupExpenseEdited(eventName),
    'expense_deleted' =>
      eventName == null || eventName.isEmpty
          ? l10n.activityGroupExpenseDeletedGeneric
          : l10n.activityGroupExpenseDeleted(eventName),
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

/// The amount + currency to display for an activity row, from either the #808
/// server-fan-in shape (`amountFils` integer subunits + `currency`) or the
/// legacy settlement shape (`amount` decimal-units string/num).
///
/// Single chokepoint — replaces the two private `_coerceAmount` copies in the
/// activity screens. Contract:
///
/// - `amountFils` is an int AND `currency` is a supported code →
///   `MoneySerializer.fromSubunits(amountFils, currency)` in that currency.
/// - `amountFils` is present but the currency is missing/unsupported → `null`.
///   `amountFils` is integer SUBUNITS; converting it with a guessed scale would
///   render a 10×/1000× lie (10500 fils shown as 10,500). It must NEVER flow
///   through the legacy decimal-units path — so a fils entry without a trusted
///   currency shows no amount rather than a wrong one.
/// - otherwise fall back to the legacy `amount` (num/string) with the currency
///   resolved by [activityAmountCurrency].
/// - neither key present → `null`.
({Decimal value, String currency})? activityAmount(
  GroupActivityLog log,
  String fallbackCurrency,
) {
  final fils = log.metadata['amountFils'];
  // `is num`, not `is int`: Firestore number deserialization can yield a Dart
  // double for this field. Subunits are integers by contract, so a malformed
  // fraction truncates via .toInt() — exactly like the sibling reader of the
  // same field (ExpenseAuditSnap.tryParse, expense_audit_diff.dart). isFinite
  // guards NaN/±infinity — forgeable via client-writable group_settlement
  // metadata (rules check only `is map`) and .toInt() on them THROWS in
  // build; non-finite falls through to the legacy path like the pre-num gate.
  if (fils is num && fils.isFinite) {
    final raw = log.metadata['currency'];
    if (raw is String && MoneySerializer.supportedCurrencies.contains(raw)) {
      return (
        value: MoneySerializer.fromSubunits(fils.toInt(), raw),
        currency: raw,
      );
    }
    return null;
  }

  final legacy = _coerceLegacyAmount(log.metadata['amount']);
  if (legacy == null) return null;
  return (value: legacy, currency: activityAmountCurrency(log, fallbackCurrency));
}

/// Legacy settlement amounts arrive as a stringified `Decimal`
/// (`GroupSettleUpScreen.logGroupEvent` writes `amount.toString()`) or a num.
/// Coerce both WITHOUT forcing a currency precision — [RAmount] applies the
/// row's own currency scale (#380).
Decimal? _coerceLegacyAmount(Object? raw) {
  // Non-finite → null: Decimal.parse('NaN') THROWS, the metadata map is
  // client-forgeable (rules check only `is map`), and activityMatchesQuery
  // runs this over EVERY loaded entry in the parent build — one forged row
  // would ErrorWidget the whole tab (client half of the #814 legacy-NaN note).
  if (raw is num) return raw.isFinite ? Decimal.parse(raw.toString()) : null;
  if (raw is String) return Decimal.tryParse(raw);
  return null;
}

/// #808 PR3 — pure client-side match for the cross-group Activity search.
///
/// Case-insensitive `contains` over the fields a user can see on a row:
/// the raw `description` (keeps the fan-in expense label searchable even though
/// the localized phrase is generic per D-PR2-1), the LOCALIZED display text,
/// the actor name, the group name, `metadata.eventName`, and — only when the
/// row actually shows an amount ([activityAmount] non-null) — the formatted
/// amount string as rendered (code-first, e.g. `OMR 10.500`). An empty or
/// whitespace-only query matches everything, so callers can pass the live query
/// unconditionally. The parameter is the [CrossGroupActivityEntry] record shape;
/// typed structurally to keep this util free of the providers layer.
bool activityMatchesQuery(
  ({GroupActivityLog log, String groupName, String groupId, String currency})
  entry,
  String query,
  AppLocalizations l10n,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;

  final log = entry.log;
  final haystacks = <String?>[
    log.description,
    localizedGroupActivityText(l10n, log),
    log.actorName,
    entry.groupName,
    _metadataString(log, 'eventName'),
  ];

  final amount = activityAmount(log, entry.currency);
  if (amount != null) {
    haystacks.add(
      AppFormatters.formatCurrency(amount.value.abs(), amount.currency),
    );
  }

  return haystacks.any((h) => h != null && h.toLowerCase().contains(needle));
}
