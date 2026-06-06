import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// Shares [text] via the platform share sheet, always supplying a non-zero
/// [Share.share] `sharePositionOrigin`.
///
/// iOS/iPadOS reject a zero-rect origin with
/// `PlatformException(sharePositionOrigin: argument must be set …)`, which
/// throws an unhandled exception and silently breaks every share path on iOS
/// (Android ignores the anchor entirely). Routing every share through this
/// helper guarantees the anchor is never omitted again — do NOT call
/// `Share.share` directly.
Future<void> shareText(BuildContext context, String text, {String? subject}) {
  return Share.share(
    text,
    subject: subject,
    sharePositionOrigin: _shareOrigin(context),
  );
}

/// A non-zero anchor rect for the share popover. Prefers the caller's own
/// render box (so the iPad popover points at the tapped control); falls back to
/// a 1×1 rect at the screen centre when the box is unavailable, so iOS always
/// receives a valid, non-zero origin.
Rect _shareOrigin(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box != null && box.hasSize) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  final size = MediaQuery.maybeOf(context)?.size ?? const Size(1, 1);
  return Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1);
}
