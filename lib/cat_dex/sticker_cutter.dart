/// Sticker cutter: turn one detector box on one photo into a sticker PNG.
///
/// Offline and deterministic — the same bytes plus the same id produce the same
/// sticker, which is what the Dex's "same cat, same name, same tilt" promise
/// rests on. `image` (already in pubspec) is the only image dependency: crop →
/// rounded-rect alpha cut-out → white sticker ring → tilt → PNG.
///
/// [storageDir] is injectable so tests can point at a temp dir instead of the
/// `path_provider` plugin (unavailable in a plain VM test).
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'cat_dex_models.dart';

class StickerCutter {
  /// [storageDir] `null` (the app default) → `getApplicationDocumentsDirectory()`.
  StickerCutter({this._storageDir});

  /// How far the detector box is grown on every side before cropping.
  static const double boxPadding = 0.15;

  /// Largest tilt applied, in degrees; the sign and size come from the id hash.
  static const double maxTiltDegrees = 5.0;

  static const double cornerRadiusFraction = 0.18;
  static const double ringFraction = 0.06;

  /// Sub-directory under the app documents dir that holds originals + stickers.
  static const String stickerDirName = 'cat_dex';

  final Directory? _storageDir;

  /// Crop, mask, ring and tilt the box at `(boxX, boxY, boxW, boxH)` out of
  /// [imageBytes], write the sticker to `<docs>/cat_dex/<id>.png` (and the
  /// source photo beside it) and return the resulting [CatSighting].
  ///
  /// [id] and [capturedAt] are optional so tests can pin both; without them the
  /// id is a microsecond stamp, exactly like the collection log's.
  Future<CatSighting> catchCat({
    required Uint8List imageBytes,
    required double boxX,
    required double boxY,
    required double boxW,
    required double boxH,
    required String label,
    required String precinct,
    required String source,
    String? id,
    String? name,
    DateTime? capturedAt,
  }) async {
    final sightingId = id ?? 'cat-${DateTime.now().microsecondsSinceEpoch}';
    final stickerBytes = cutStickerBytes(
      imageBytes: imageBytes,
      boxX: boxX,
      boxY: boxY,
      boxW: boxW,
      boxH: boxH,
      id: sightingId,
    );
    final base = _storageDir ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$stickerDirName');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final stickerFile = File('${dir.path}/$sightingId.png');
    await stickerFile.writeAsBytes(stickerBytes, flush: true);
    final originalFile = File('${dir.path}/$sightingId'
        '_src.${_extensionFor(imageBytes)}');
    await originalFile.writeAsBytes(imageBytes, flush: true);
    return CatSighting(
      id: sightingId,
      label: label,
      name: name ?? catDexNameFor(sightingId),
      capturedAt: capturedAt ?? DateTime.now(),
      precinct: precinct,
      source: source,
      originalPath: originalFile.path,
      stickerPath: stickerFile.path,
    );
  }

  /// Deterministic tilt in `[-maxTiltDegrees, +maxTiltDegrees]` for [id].
  static double tiltFor(String id) =>
      ((catDexHash(id) % 10001) / 10000.0 * 2.0 - 1.0) * maxTiltDegrees;

  /// The pure core: bytes in, PNG sticker bytes out. No filesystem, no plugins.
  ///
  /// Throws [FormatException] when [imageBytes] is not a decodable image.
  static Uint8List cutStickerBytes({
    required Uint8List imageBytes,
    required double boxX,
    required double boxY,
    required double boxW,
    required double boxH,
    required String id,
  }) {
    final src = img.decodeImage(imageBytes);
    if (src == null) {
      throw const FormatException('cat-dex: unsupported image bytes');
    }
    final r = _paddedRect(src, boxX, boxY, boxW, boxH);
    final crop = img.copyCrop(src,
        x: r.left, y: r.top, width: r.width, height: r.height);
    final ringed = _maskAndRing(crop);
    final tilted = img.copyRotate(ringed,
        angle: tiltFor(id), interpolation: img.Interpolation.linear);
    return img.encodePng(tilted, level: 6);
  }

  /// The detector box grown by [boxPadding] on every side, clamped to [src].
  static ({int left, int top, int width, int height}) _paddedRect(
      img.Image src, double boxX, double boxY, double boxW, double boxH) {
    final w = boxW.abs();
    final h = boxH.abs();
    var left = (boxX - w * boxPadding).round();
    var top = (boxY - h * boxPadding).round();
    var right = (boxX + w + w * boxPadding).round();
    var bottom = (boxY + h + h * boxPadding).round();
    // A degenerate box (0×0 row from a bad detection) still yields a square.
    if (right - left < 4) right = left + 4;
    if (bottom - top < 4) bottom = top + 4;
    left = left.clamp(0, math.max(0, src.width - 1));
    top = top.clamp(0, math.max(0, src.height - 1));
    right = right.clamp(left + 1, src.width);
    bottom = bottom.clamp(top + 1, src.height);
    return (left: left, top: top, width: right - left, height: bottom - top);
  }

  /// Rounded-rect alpha cut-out plus an opaque white ring hugging it, i.e. the
  /// classic sticker look: photo inside, white border, transparent outside.
  static img.Image _maskAndRing(img.Image crop) {
    final w = crop.width;
    final h = crop.height;
    final out = img.Image(width: w, height: h, numChannels: 4);
    final minSide = math.min(w, h).toDouble();
    final outerRadius = minSide * cornerRadiusFraction;
    final ring = math.max(1.0, math.min(minSide / 2 - 2.0, minSide * ringFraction));
    final innerRadius = math.max(1.0, outerRadius - ring);
    final innerLeft = ring;
    final innerTop = ring;
    final innerRight = w - ring;
    final innerBottom = h - ring;
    final hasInner = innerRight > innerLeft && innerBottom > innerTop;

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final outerA =
            _coverage(x.toDouble(), y.toDouble(), 0, 0, w.toDouble(), h.toDouble(), outerRadius);
        if (outerA <= 0) {
          out.setPixelRgba(x, y, 0, 0, 0, 0);
          continue;
        }
        final innerT = hasInner
            ? _coverage(x.toDouble(), y.toDouble(), innerLeft, innerTop,
                innerRight, innerBottom, innerRadius)
            : 0.0;
        final p = crop.getPixel(x, y);
        final photoA = innerT * (p.a / 255.0);
        final alpha =
            (outerA * (photoA + (1.0 - innerT))).clamp(0.0, 1.0);
        final inv = 1.0 - photoA;
        out.setPixelRgba(
          x,
          y,
          (p.r * photoA + 255 * inv).round().clamp(0, 255),
          (p.g * photoA + 255 * inv).round().clamp(0, 255),
          (p.b * photoA + 255 * inv).round().clamp(0, 255),
          (alpha * 255).round().clamp(0, 255),
        );
      }
    }
    return out;
  }

  /// 2×2 supersampled coverage of the rounded rect `[l,t]..[r,b]` over the
  /// pixel at `(x, y)`, in `0..1`. Edges are exclusive at `r`/`b`, so a rect of
  /// `0,0,w,h` covers the whole `w×h` image.
  static double _coverage(double x, double y, double l, double t, double r,
      double b, double radius) {
    var hits = 0;
    for (final dx in const [-0.25, 0.25]) {
      for (final dy in const [-0.25, 0.25]) {
        if (_insideRoundedRect(x + 0.5 + dx, y + 0.5 + dy, l, t, r, b, radius)) {
          hits++;
        }
      }
    }
    return hits / 4.0;
  }

  static bool _insideRoundedRect(double x, double y, double l, double t,
      double r, double b, double radius) {
    if (x < l || y < t || x > r || y > b) return false;
    final rr = radius.clamp(0.0, math.min(r - l, b - t) / 2);
    final cx = x < l + rr ? l + rr : (x > r - rr ? r - rr : x);
    final cy = y < t + rr ? t + rr : (y > b - rr ? b - rr : y);
    final dx = x - cx;
    final dy = y - cy;
    return dx * dx + dy * dy <= rr * rr;
  }

  /// JPEG bytes keep a `.jpg` name; anything else is written as `.png`.
  static String _extensionFor(Uint8List bytes) =>
      bytes.length > 1 && bytes[0] == 0xFF && bytes[1] == 0xD8 ? 'jpg' : 'png';
}
