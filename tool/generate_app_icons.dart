// Generates launcher-icon PNG sources from the Route mark painter.
//
// Run with: flutter test tool/generate_app_icons.dart
// (uses TestWidgetsFlutterBinding so dart:ui Canvas is available).
//
// Then fan out to per-platform sizes:
//   dart run flutter_launcher_icons
//
// Outputs:
//   assets/app_icon.png            — 1024×1024, paper bg, full-bleed mark.
//                                    Used by iOS and Android (legacy).
//   assets/app_icon_foreground.png — 1024×1024, transparent bg, mark scaled
//                                    into the 72/108 Android-adaptive safe
//                                    zone. Used as adaptive foreground.
//   assets/app_icon_monochrome.png — 1024×1024, transparent bg, mark in
//                                    white. Used as Android 13+ themed icon
//                                    (OS tints to wallpaper theme).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';

// Read the live tokens instead of mirroring them — the hardcoded copies
// drifted when Falaj remapped the palette (#935).
final _paper = AppColorTokens.light.scaffoldBackground;
final _ink = AppColorTokens.light.textPrimary;
final _pin = AppColorTokens.light.primary;

// Coordinates mirror lib/shared/widgets/route_mark.dart (200×200 viewBox).
const _canvasPx = 1024;
const _viewBox = 200.0;

void _paintRouteMark(Canvas canvas, Color foreground, Color pin) {
  canvas.drawCircle(const Offset(54, 146), 5.5, Paint()..color = foreground);
  canvas.drawCircle(
    const Offset(54, 146),
    11,
    Paint()
      ..color = foreground.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4,
  );

  final path = Path()
    ..moveTo(54, 146)
    ..cubicTo(102, 124, 100, 84, 146, 60);
  final dotPaint = Paint()..color = foreground;
  for (final metric in path.computeMetrics()) {
    for (double d = 0; d <= metric.length; d += 14) {
      final tangent = metric.getTangentForOffset(d);
      if (tangent == null) continue;
      canvas.drawCircle(tangent.position, 3.5, dotPaint);
    }
  }

  // Pin as a donut so the center hole is transparent — required for the
  // monochrome variant and harmless on the paper-bg variant.
  final pinPath = Path()
    ..addOval(Rect.fromCircle(center: const Offset(146, 60), radius: 20))
    ..addOval(Rect.fromCircle(center: const Offset(146, 60), radius: 7))
    ..fillType = PathFillType.evenOdd;
  canvas.drawPath(pinPath, Paint()..color = pin);
}

Future<void> _writeIcon(
  String path, {
  required Color foreground,
  required Color pin,
  Color? backgroundFill,
  required double scale,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  if (backgroundFill != null) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _canvasPx + 0.0, _canvasPx + 0.0),
      Paint()..color = backgroundFill,
    );
  }

  final renderSize = _viewBox * scale;
  final offset = (_canvasPx - renderSize) / 2;
  canvas.translate(offset, offset);
  canvas.scale(scale);
  _paintRouteMark(canvas, foreground, pin);

  final picture = recorder.endRecording();
  final image = await picture.toImage(_canvasPx, _canvasPx);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('Wrote $path (${bytes.lengthInBytes} bytes)');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate launcher icon sources', () async {
    // Master: mark fills the full canvas (iOS handles the squircle crop).
    const fullBleedScale = _canvasPx / _viewBox;
    await _writeIcon(
      'assets/app_icon.png',
      foreground: _ink,
      pin: _pin,
      backgroundFill: _paper,
      scale: fullBleedScale,
    );

    // Adaptive foreground: full-bleed mark. flutter_launcher_icons applies a
    // 16% inset in the generated XML, which places the mark in the 72/108 dp
    // safe zone — doing the inset here too would double-shrink it.
    await _writeIcon(
      'assets/app_icon_foreground.png',
      foreground: _ink,
      pin: _pin,
      scale: fullBleedScale,
    );

    // Themed icon: single-color (white) mark on transparent. Same full-bleed
    // scale as foreground for the same reason.
    await _writeIcon(
      'assets/app_icon_monochrome.png',
      foreground: Colors.white,
      pin: Colors.white,
      scale: fullBleedScale,
    );
  });
}
