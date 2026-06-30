import '../../l10n/generated/app_localizations.dart';

/// Builds the prefilled WhatsApp message for the post-record settle-up notify
/// (#367). Honest past tense — it is sent AFTER the settlement is recorded, as
/// pure courtesy (never a payment step).
///
/// Scope naming disambiguates a shared pair across groups: an EVENT settle names
/// the event AND its group; a GROUP settle spans events so it names only the
/// group. A null/empty [eventName] selects the group-scope template.
///
/// [amountDisplay] must already be the per-currency formatted figure (incl.
/// JPY×1) and stays LTR-Latin even inside the Arabic template.
String settleNotifyMessage({
  required AppLocalizations l10n,
  required String recipientName,
  required String amountDisplay,
  required String groupName,
  String? eventName,
}) {
  final event = eventName?.trim() ?? '';
  return event.isEmpty
      ? l10n.settleNotifyMessageGroup(recipientName, amountDisplay, groupName)
      : l10n.settleNotifyMessageEvent(
          recipientName,
          amountDisplay,
          event,
          groupName,
        );
}
