import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Rasterizes the [RepaintBoundary] identified by [boundaryKey] to PNG bytes.
///
/// [pixelRatio] scales the logical card up — a 360-logical-wide card at the
/// default 3.0 becomes a 1080px-wide image (the #722 recap poster target).
///
/// Captures the user-visible, settled boundary of the recap preview sheet, so by
/// the time this runs the boundary is already laid out and painted. As a guard
/// against the "image captured while unpainted" race, in debug we await one frame
/// iff the boundary still needs paint (`debugNeedsPaint` — debug-only; it throws
/// in release, and `kDebugMode` strips this branch there entirely). Returns null
/// if the boundary isn't mounted or PNG encoding yields no bytes — callers surface
/// a friendly error, never crash.
Future<Uint8List?> captureBoundaryPng(
  GlobalKey boundaryKey, {
  double pixelRatio = 3.0,
}) async {
  final object = boundaryKey.currentContext?.findRenderObject();
  if (object is! RenderRepaintBoundary) return null;

  if (kDebugMode && object.debugNeedsPaint) {
    await WidgetsBinding.instance.endOfFrame;
  }

  final image = await object.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
