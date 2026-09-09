// Generates every app icon Glyph ships, with no packages and no downloads.
//
// Run from the repository root:
//
//   dart run tool/make_icons.dart
//
// There is no image library here on purpose. Pillow is not installed, nor is
// any SVG rasteriser, and an icon-generator package would be a download on a
// ~2.7 Mbps connection. Everything below is the Dart SDK: `dart:io`'s ZLibCodec
// supplies the deflate stream PNG wants, and the rest is a few hundred bytes of
// chunk framing and a CRC table.
//
// The mark is a geometric G drawn from five thick strokes with round caps,
// supersampled 4x4. Straight segments rather than curves because a distance
// function over line segments is a dozen lines and stays crisp at 48 px, which
// is the size that actually has to work.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

// ----------------------------------------------------------------- palette
// Drawn from lib/ui/theme.dart so the icon and the interface agree: the slate
// is the theme seed darkened for contrast, the green is the action colour.
const _Rgb _background = _Rgb(0x2F, 0x3E, 0x50);
const _Rgb _mark = _Rgb(0x3D, 0xD6, 0x8C);

/// Fraction of the canvas the mark's box occupies.
///
/// With the stroke's round caps the drawn extent is about 1.05 box widths, so
/// 0.58 lands at ~0.61 of the canvas. That clears an adaptive icon's 0.667 safe
/// zone and a maskable web icon's 0.8, so one value serves every target.
const double _markScale = 0.58;

/// Corner radius of the background square, as a fraction of the canvas.
const double _cornerRadius = 0.22;

void main() {
  final outputs = <String, Uint8List>{
    // Android legacy launcher icons.
    'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': _render(48),
    'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': _render(72),
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': _render(96),
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': _render(144),
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': _render(192),

    // Android adaptive icon foreground. Transparent: the background is a solid
    // colour resource, which is what lets the launcher animate the two layers
    // apart. 108dp at each density.
    'android/app/src/main/res/mipmap-mdpi/ic_launcher_foreground.png':
        _render(108, drawBackground: false),
    'android/app/src/main/res/mipmap-hdpi/ic_launcher_foreground.png':
        _render(162, drawBackground: false),
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher_foreground.png':
        _render(216, drawBackground: false),
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher_foreground.png':
        _render(324, drawBackground: false),
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png':
        _render(432, drawBackground: false),

    // Web.
    'web/favicon.png': _render(32),
    'web/icons/Icon-192.png': _render(192),
    'web/icons/Icon-512.png': _render(512),
    // Maskable icons are cropped to an arbitrary shape by the launcher, so the
    // background runs to the edge and the mark stays well inside.
    'web/icons/Icon-maskable-192.png': _render(192, squareBackground: true),
    'web/icons/Icon-maskable-512.png': _render(512, squareBackground: true),
  };

  outputs.forEach((path, bytes) {
    final file = File(path)..parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    stdout.writeln('${bytes.length.toString().padLeft(7)}  $path');
  });
  stdout.writeln('\n${outputs.length} files written.');
}

// ---------------------------------------------------------------- rendering

/// Renders one square icon at [size] pixels.
Uint8List _render(
  int size, {
  bool drawBackground = true,
  bool squareBackground = false,
}) {
  const samples = 4;
  final pixels = Uint8List(size * size * 4);
  final strokes = _glyphStrokes();
  final halfStroke = 0.17 / 2 * _markScale;

  for (var py = 0; py < size; py++) {
    for (var px = 0; px < size; px++) {
      // Averaged in premultiplied space; compositing straight RGBA would fringe
      // the edge of the mark with background colour.
      var rSum = 0.0, gSum = 0.0, bSum = 0.0, aSum = 0.0;

      for (var sy = 0; sy < samples; sy++) {
        for (var sx = 0; sx < samples; sx++) {
          final x = (px + (sx + 0.5) / samples) / size;
          final y = (py + (sy + 0.5) / samples) / size;

          _Rgb? colour;
          if (_distanceToStrokes(x, y, strokes) <= halfStroke) {
            colour = _mark;
          } else if (drawBackground &&
              (squareBackground || _insideRoundedSquare(x, y))) {
            colour = _background;
          }

          if (colour != null) {
            rSum += colour.r;
            gSum += colour.g;
            bSum += colour.b;
            aSum += 255;
          }
        }
      }

      const total = samples * samples;
      final alpha = aSum / total;
      final index = (py * size + px) * 4;
      if (alpha > 0) {
        // Un-premultiply: the sums already excluded transparent samples, so
        // dividing by the covered count recovers the colour.
        final covered = aSum / 255;
        pixels[index] = (rSum / covered).round().clamp(0, 255);
        pixels[index + 1] = (gSum / covered).round().clamp(0, 255);
        pixels[index + 2] = (bSum / covered).round().clamp(0, 255);
        pixels[index + 3] = alpha.round().clamp(0, 255);
      }
    }
  }

  return _encodePng(size, size, pixels);
}

/// The mark: a geometric G, as five segments in canvas coordinates.
List<_Segment> _glyphStrokes() {
  // Laid out in a 0..1 box, then mapped onto the centred square of side
  // [_markScale]. Keeping the design in box coordinates means the proportions
  // survive every size and every safe zone.
  const a = 0.06, z = 0.94, mid = 0.50, inner = 0.52;
  const box = <_Segment>[
    _Segment(a, a, z, a), // top bar
    _Segment(a, a, a, z), // left upright
    _Segment(a, z, z, z), // bottom bar
    _Segment(z, z, z, mid), // right upright, lower half only
    _Segment(inner, mid, z, mid), // the G's inward bar
  ];

  final offset = (1 - _markScale) / 2;
  double map(double v) => offset + v * _markScale;
  return <_Segment>[
    for (final s in box)
      _Segment(map(s.x1), map(s.y1), map(s.x2), map(s.y2)),
  ];
}

double _distanceToStrokes(double x, double y, List<_Segment> strokes) {
  var best = double.infinity;
  for (final s in strokes) {
    final d = _distanceToSegment(x, y, s);
    if (d < best) best = d;
  }
  return best;
}

double _distanceToSegment(double px, double py, _Segment s) {
  final dx = s.x2 - s.x1;
  final dy = s.y2 - s.y1;
  final lengthSquared = dx * dx + dy * dy;
  // Round caps: clamping t to [0,1] makes the distance field a capsule.
  final t = lengthSquared == 0
      ? 0.0
      : (((px - s.x1) * dx + (py - s.y1) * dy) / lengthSquared).clamp(0.0, 1.0);
  final cx = s.x1 + t * dx;
  final cy = s.y1 + t * dy;
  return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
}

/// Signed-distance test for a rounded square filling the canvas.
bool _insideRoundedSquare(double x, double y) {
  const half = 0.5 - _cornerRadius;
  final qx = (x - 0.5).abs() - half;
  final qy = (y - 0.5).abs() - half;
  final outerX = math.max(qx, 0.0);
  final outerY = math.max(qy, 0.0);
  final distance = math.sqrt(outerX * outerX + outerY * outerY) +
      math.min(math.max(qx, qy), 0.0);
  return distance <= _cornerRadius;
}

// ------------------------------------------------------------- PNG encoding

/// Encodes 8-bit RGBA [pixels] as a non-interlaced PNG.
Uint8List _encodePng(int width, int height, Uint8List pixels) {
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // filter type 0 (None), per scanline
    raw.add(Uint8List.sublistView(pixels, y * width * 4, (y + 1) * width * 4));
  }

  final ihdr = BytesBuilder()
    ..add(_uint32(width))
    ..add(_uint32(height))
    ..addByte(8) // bit depth
    ..addByte(6) // colour type 6 = truecolour with alpha
    ..addByte(0) // deflate
    ..addByte(0) // adaptive filtering
    ..addByte(0); // no interlace

  return Uint8List.fromList(<int>[
    // PNG signature.
    137, 80, 78, 71, 13, 10, 26, 10,
    ..._chunk('IHDR', ihdr.toBytes()),
    // ZLibCodec emits a zlib stream -- header, deflate data and Adler-32 --
    // which is exactly what IDAT holds.
    ..._chunk('IDAT', Uint8List.fromList(zlib.encode(raw.toBytes()))),
    ..._chunk('IEND', Uint8List(0)),
  ]);
}

List<int> _chunk(String type, Uint8List data) {
  final typeBytes = type.codeUnits;
  final body = <int>[...typeBytes, ...data];
  return <int>[..._uint32(data.length), ...body, ..._uint32(_crc32(body))];
}

List<int> _uint32(int value) => <int>[
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];

final Uint32List _crcTable = _buildCrcTable();

Uint32List _buildCrcTable() {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final byte in bytes) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

// --------------------------------------------------------------- value types

class _Rgb {
  const _Rgb(this.r, this.g, this.b);
  final int r, g, b;
}

class _Segment {
  const _Segment(this.x1, this.y1, this.x2, this.y2);
  final double x1, y1, x2, y2;
}
