import 'package:flutter/material.dart';

import '../../features/events/models/event_model.dart';

/// Two-band procedural cover art used wherever the saffron direction calls
/// for "scenery without photos" — journey ticket cards, group covers, event
/// row thumbnails. Sky gradient + sun + two land paths.
class CoverArt extends StatelessWidget {
  const CoverArt({super.key, required this.palette});

  /// Color palette controlling the sky, mid, land, and sun fills.
  final CoverPalette palette;

  /// Convenience constructor for an event-type-driven palette.
  factory CoverArt.forEventType(EventType type, {Key? key}) {
    return CoverArt(key: key, palette: CoverPalette.forEventType(type));
  }

  /// Convenience constructor for a hash-derived palette — used when the
  /// caller has no event type in hand (e.g. group covers seeded by name).
  factory CoverArt.fromSeed(String seed, {Key? key}) {
    return CoverArt(key: key, palette: CoverPalette.fromSeed(seed));
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: CoverArtPainter(palette));
  }
}

/// Four-color palette for [CoverArt]. Five built-in variants cover the
/// app's full needs; pick deterministically via the factory helpers.
@immutable
class CoverPalette {
  const CoverPalette({
    required this.sky,
    required this.mid,
    required this.land,
    required this.sun,
  });

  final Color sky;
  final Color mid;
  final Color land;
  final Color sun;

  static const _trip = CoverPalette(
    // design-token-justified: procedural cover art palette is decorative artwork.
    sky: Color(0xFF3E4A63),
    mid: Color(0xFF9E6B78),
    land: Color(0xFF26303F),
    sun: Color(0xFFE8C77A),
  );
  static const _camping = CoverPalette(
    // design-token-justified: procedural cover art palette is decorative artwork.
    sky: Color(0xFFAEC4A6),
    mid: Color(0xFF5E8A5A),
    land: Color(0xFF234A2C),
    sun: Color(0xFFDDE8D2),
  );
  static const _travel = CoverPalette(
    // design-token-justified: procedural cover art palette is decorative artwork.
    sky: Color(0xFF6E9AB8),
    mid: Color(0xFFC3CDD2),
    land: Color(0xFF3A566A),
    sun: Color(0xFFC9962F),
  );
  static const _night = CoverPalette(
    // design-token-justified: procedural cover art palette is decorative artwork.
    sky: Color(0xFF26264A),
    mid: Color(0xFF38466E),
    land: Color(0xFF14182C),
    sun: Color(0xFFD9A845),
  );
  static const _custom = CoverPalette(
    // design-token-justified: procedural cover art palette is decorative artwork.
    sky: Color(0xFF7FB0AE),
    mid: Color(0xFF2E6E66),
    land: Color(0xFF1C4A45),
    sun: Color(0xFFDCE2DA),
  );

  static const _all = [_trip, _camping, _travel, _night, _custom];

  /// Mapping that mirrors the journey-card palette set, one per [EventType].
  static CoverPalette forEventType(EventType t) {
    return switch (t) {
      EventType.trip => _trip,
      EventType.camping => _camping,
      EventType.travel => _travel,
      EventType.nightDayOut => _night,
      EventType.custom => _custom,
    };
  }

  /// Pick a palette deterministically from any seed string. Useful for
  /// group covers where there's no event type to pivot off.
  static CoverPalette fromSeed(String seed) {
    if (seed.isEmpty) return _trip;
    var h = 0;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) & 0xffffffff;
    }
    return _all[h.abs() % _all.length];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CoverPalette &&
          sky == other.sky &&
          mid == other.mid &&
          land == other.land &&
          sun == other.sun);

  @override
  int get hashCode => Object.hash(sky, mid, land, sun);
}

/// Procedural painter for [CoverArt]. Sky gradient → sun disk → distant
/// ridge → near land. Renders at any size; coordinates are size-relative.
class CoverArtPainter extends CustomPainter {
  const CoverArtPainter(this.palette);
  final CoverPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Sky gradient.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.sky, palette.mid],
        ).createShader(rect),
    );
    // Sun disk.
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.25),
      size.width * 0.055,
      Paint()..color = palette.sun.withValues(alpha: 0.85),
    );
    // Distant ridge.
    final ridge = Path()
      ..moveTo(0, size.height * 0.68)
      ..quadraticBezierTo(
        size.width * 0.18,
        size.height * 0.55,
        size.width * 0.36,
        size.height * 0.64,
      )
      ..quadraticBezierTo(
        size.width * 0.55,
        size.height * 0.72,
        size.width * 0.72,
        size.height * 0.59,
      )
      ..quadraticBezierTo(
        size.width * 0.88,
        size.height * 0.50,
        size.width,
        size.height * 0.66,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      ridge,
      Paint()..color = palette.land.withValues(alpha: 0.55),
    );
    // Near land.
    final near = Path()
      ..moveTo(0, size.height * 0.82)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.70,
        size.width * 0.50,
        size.height * 0.80,
      )
      ..quadraticBezierTo(
        size.width * 0.75,
        size.height * 0.90,
        size.width,
        size.height * 0.78,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(near, Paint()..color = palette.land);
  }

  @override
  bool shouldRepaint(covariant CoverArtPainter old) => old.palette != palette;
}
