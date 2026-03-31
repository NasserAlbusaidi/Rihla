/// Generates a 32x32 tileable noise PNG for the grain texture overlay.
///
/// Run once: dart run tool/generate_grain.dart
///
/// Output: assets/textures/grain.png
///
/// The PNG has a transparent background with ~20% of pixels set to white
/// at varying opacity levels. The result is a subtle paper grain texture
/// that looks natural at 3-5% opacity.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

void main() {
  final grain = generateGrainPng(
    width: 32,
    height: 32,
    seed: 42,
    density: 0.20,
  );

  final outputPath = 'assets/textures/grain.png';
  File(outputPath).writeAsBytesSync(grain);
  stdout.writeln('Written: $outputPath (${grain.length} bytes)');
}

/// Generate a 32x32 RGBA noise PNG.
///
/// [density] controls what fraction of pixels are non-transparent (0.0–1.0).
/// Uses a fixed [seed] so output is reproducible.
Uint8List generateGrainPng({
  required int width,
  required int height,
  int seed = 42,
  double density = 0.20,
}) {
  final rng = Random(seed);

  // Build raw RGBA pixel data (4 bytes per pixel)
  // Row by row, left to right
  final List<List<int>> rows = List.generate(height, (y) {
    final row = <int>[];
    for (int x = 0; x < width; x++) {
      if (rng.nextDouble() < density) {
        // Grain pixel: white with varying alpha for natural variation
        final alpha = 100 + rng.nextInt(155); // 100-254 range
        row.addAll([255, 255, 255, alpha]); // RGBA white
      } else {
        row.addAll([0, 0, 0, 0]); // Fully transparent
      }
    }
    return row;
  });

  return _encodePng(width, height, rows);
}

/// Encode RGBA pixel data as a valid PNG file.
Uint8List _encodePng(int width, int height, List<List<int>> rows) {
  // PNG signature
  final signature = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);

  // IHDR chunk: width, height, bit depth=8, color type=6 (RGBA), compression=0, filter=0, interlace=0
  final ihdrData = ByteData(13);
  ihdrData.setUint32(0, width);
  ihdrData.setUint32(4, height);
  ihdrData.setUint8(8, 8); // bit depth
  ihdrData.setUint8(9, 6); // color type: RGBA
  ihdrData.setUint8(10, 0); // compression method
  ihdrData.setUint8(11, 0); // filter method
  ihdrData.setUint8(12, 0); // interlace method
  final ihdrBytes = ihdrData.buffer.asUint8List();

  // Build raw filtered image data
  // Each row is preceded by filter type byte 0 (None)
  final rawData = <int>[];
  for (final row in rows) {
    rawData.add(0); // filter type None
    rawData.addAll(row);
  }

  // Compress with zlib
  final compressed = zlib.encode(rawData);

  // Assemble chunks
  final chunks = <int>[];
  chunks.addAll(signature);
  chunks.addAll(_makeChunk('IHDR', ihdrBytes));
  chunks.addAll(_makeChunk('IDAT', Uint8List.fromList(compressed)));
  chunks.addAll(_makeChunk('IEND', Uint8List(0)));

  return Uint8List.fromList(chunks);
}

/// Create a PNG chunk: length(4) + type(4) + data(n) + crc(4).
List<int> _makeChunk(String type, Uint8List data) {
  final typeBytes = type.codeUnits;

  // Length
  final lengthBytes = ByteData(4);
  lengthBytes.setUint32(0, data.length);

  // CRC over type + data
  final crcInput = [...typeBytes, ...data];
  final crc = _crc32(crcInput);
  final crcBytes = ByteData(4);
  crcBytes.setUint32(0, crc);

  return [
    ...lengthBytes.buffer.asUint8List(),
    ...typeBytes,
    ...data,
    ...crcBytes.buffer.asUint8List(),
  ];
}

/// Standard CRC-32 as used by PNG.
int _crc32(List<int> data) {
  // Pre-compute CRC table
  final table = List<int>.filled(256, 0);
  for (int n = 0; n < 256; n++) {
    int c = n;
    for (int k = 0; k < 8; k++) {
      if (c & 1 != 0) {
        c = 0xEDB88320 ^ (c >> 1);
      } else {
        c >>= 1;
      }
    }
    table[n] = c;
  }

  int crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc = table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
