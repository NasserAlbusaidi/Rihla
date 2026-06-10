import 'package:url_launcher/url_launcher.dart';

/// Builds the canonical WhatsApp deep link that opens a chat composer prefilled
/// with [message].
///
/// Uses the custom `whatsapp://send` scheme rather than the `https://wa.me`
/// web wrapper on purpose: only the scheme lets [canLaunchUrl] detect whether
/// WhatsApp is actually installed (an `https://wa.me` URL resolves to true
/// whenever any browser exists, which would defeat the not-installed fallback).
/// `queryParameters` URL-encodes [message] — which already embeds the
/// `rihla-safar.web.app/join/<code>` invite link (#354).
Uri whatsAppInviteUri(String message) {
  return Uri(
    scheme: 'whatsapp',
    host: 'send',
    queryParameters: {'text': message},
  );
}

/// Opens WhatsApp prefilled with [message], falling back to [fallback] (the OS
/// share sheet) when WhatsApp isn't installed or the launch can't complete.
///
/// [fallback] also runs if the probe or launch throws, so the invite path can
/// never silently dead-end. Requires the WhatsApp package/scheme to be declared
/// in the Android `<queries>` block and iOS `LSApplicationQueriesSchemes` —
/// without those allow-lists [canLaunchUrl] returns false even when WhatsApp is
/// present.
Future<void> shareInviteViaWhatsApp(
  String message, {
  required Future<void> Function() fallback,
}) async {
  final uri = whatsAppInviteUri(message);
  try {
    if (await canLaunchUrl(uri)) {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (launched) return;
    }
  } catch (_) {
    // Fall through to the share-sheet fallback below.
  }
  await fallback();
}
