/// MobileNet v3 (small) image embedder + local kNN classifier.
///
/// Closes the COCO blind spots (can / battery / cardboard / tissue have no
/// COCO class) with a fully offline embedding search: the app embeds the
/// capture into a 1024-d vector and asks the Go core for the nearest
/// labelled reference embeddings.
///
/// Seed references ship inside the APK (assets/knn/seed) and are embedded on
/// first use, then cached to the app documents dir. Residents add more
/// reference photos by simply using the app (later: managed ref library).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../types.dart';
import 'township_core.dart';

class KnnItem {
  final String label;
  final Float32List embedding;
  KnnItem(this.label, this.embedding);
}

class KnnResult {
  final String label;
  final double cosine;
  const KnnResult(this.label, this.cosine);
}

class Embedder {
  static const inputSize = 224;
  /// Adopt the kNN identity when the best cosine clears this. Validated on the
  /// seed set: cross-class cosine max 0.146, reframe hits 0.78–0.91 — so
  /// anything in [0.35, 0.9] is a safe, wide corridor.
  static const adoptThreshold = 0.35;
  /// Above this the item identity is strong evidence (labels merge as ~0.9).
  static const strongThreshold = 0.6;

  Interpreter? _interpreter;
  List<KnnItem> _refs = [];

  bool get ready => _interpreter != null && _refs.isNotEmpty;

  Future<void> load() async {
    if (_interpreter != null) return;
    _interpreter = await Interpreter.fromAsset(
      'assets/models/mobilenet_v3_small_embedder.tflite',
      options: InterpreterOptions()..threads = 2,
    );
    await _loadRefs();
  }

  Future<void> _loadRefs() async {
    // 1) persisted cache (computed on a previous launch)
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/knn_refs.json');
      if (await f.exists()) {
        final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final labels = (data['labels'] as List).cast<String>();
        final bytes = base64Decode(data['db'] as String);
        final floats = Float32List.view(bytes.buffer);
        if (floats.length == labels.length * 1024) {
          _refs = [
            for (var i = 0; i < labels.length; i++)
              KnnItem(labels[i], Float32List.sublistView(floats, i * 1024, (i + 1) * 1024)),
          ];
          return;
        }
      }
    } catch (_) {/* fall through to recompute */}

    // 2) embed the seed photos bundled in the APK
    final manifest = jsonDecode(await rootBundle.loadString('assets/knn/seed/seed.json'))
        as List<dynamic>;
    final refs = <KnnItem>[];
    for (final e in manifest) {
      final entry = e as Map<String, dynamic>;
      final bytes = await rootBundle.load('assets/${entry['file']}');
      final vec = embedImageBytes(bytes.buffer.asUint8List());
      if (vec != null) refs.add(KnnItem(entry['label'] as String, vec));
    }
    _refs = refs;

    // 3) persist for next launch
    try {
      final dir = await getApplicationDocumentsDirectory();
      final db = Float32List(refs.length * 1024);
      for (var i = 0; i < refs.length; i++) {
        db.setRange(i * 1024, (i + 1) * 1024, refs[i].embedding);
      }
      final f = File('${dir.path}/knn_refs.json');
      await f.writeAsString(jsonEncode({
        'labels': [for (final r in refs) r.label],
        'db': base64Encode(db.buffer.asUint8List()),
      }));
    } catch (_) {/* cache is an optimisation, not a requirement */}
  }

  /// Embed a whole image (JPEG/PNG bytes) → L2-normalised 1024-d vector.
  Float32List? embedImageBytes(Uint8List bytes) {
    final interp = _interpreter;
    if (interp == null) return null;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final small = img.copyResize(decoded, width: inputSize, height: inputSize);
    final input = Float32List(inputSize * inputSize * 3);
    var o = 0;
    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final p = small.getPixel(x, y);
        input[o++] = p.r / 255.0;
        input[o++] = p.g / 255.0;
        input[o++] = p.b / 255.0;
      }
    }
    final inBytes = TownshipCore.f32Bytes(input);
    final outBytes = Uint8List(1024 * 4);
    interp.runForMultipleInputs([inBytes], {0: outBytes.buffer});
    final out = Float32List.view(outBytes.buffer);
    var norm = 0.0;
    for (final v in out) {
      norm += v * v;
    }
    norm = out.isEmpty || norm == 0 ? 1.0 : _sqrt(norm);
    for (var i = 0; i < out.length; i++) {
      out[i] /= norm;
    }
    return out;
  }

  static double _sqrt(double x) {
    var g = x, last = 0.0;
    while (g != last) { last = g; g = (g + x / g) / 2; }
    return g;
  }

  /// Resident-taught references live on top of the seed set.
  final List<KnnItem> _runtimeRefs = [];

  void addRuntimeRef(String label, Float32List vec) {
    _runtimeRefs.add(KnnItem(label, vec));
  }

  /// Nearest labelled item for [vec] — served by the Go core.
  Future<KnnResult?> nearest(Float32List vec) async {
    if (_refs.isEmpty) return null;
    final db = Float32List(_refs.length * 1024);
    for (var i = 0; i < _refs.length; i++) {
      db.setRange(i * 1024, (i + 1) * 1024, _refs[i].embedding);
    }
    final matches = await TownshipCore.knnSearch(
        vec, db, [for (final r in _refs) r.label], 3);
    if (matches.isEmpty) return null;
    return KnnResult(matches.first.label, matches.first.score);
  }

  /// kNN evidence as a VisionLabel the keyword classifier can consume.
  /// Strength is a rescaled cosine in [0, 0.95].
  VisionLabel? asLabel(KnnResult? r) {
    if (r == null || r.cosine < adoptThreshold) return null;
    final strength = ((r.cosine - adoptThreshold) / (1 - adoptThreshold)).clamp(0.0, 0.95);
    return VisionLabel(r.label, strength);
  }

  void dispose() => _interpreter?.close();
}
