/// Single-scan vision pipeline: photo → **YOLO** boxes (primary) → legacy
/// EfficientDet-Lite0 boxes (fallback) → ML Kit labels → kNN item identity →
/// six-stream decision. Everything on-device.
///
/// Isolation policy: the JPEG decode, the 640-px downscale that the label and
/// kNN stages consume, and the YOLO preprocess + inference all run in a worker
/// isolate ([Isolate.run]) so the camera preview never blocks on them. The
/// worker is handed the root-isolate token, which is what lets `rootBundle`
/// (and therefore `Interpreter.fromAsset`) work off the main isolate; if a
/// platform refuses the worker, detection retries on the main isolate instead
/// of failing the scan.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../types.dart';
import 'efficientdet.dart';
import 'embedder.dart';
import 'recycle_classifier.dart';
import 'waste_classifier.dart';
import 'yolo_detector.dart';

/// Longest side of the copy every non-YOLO stage sees. The full-resolution
/// capture is only ever used for the resident-facing photo, never for a model.
const _scanSide = 640;

/// Decode + downscale result, carried as plain bytes so it can cross an isolate
/// boundary (the detector rebuilds an `img.Image` from it on the far side).
class _ScanImage {
  final int width;
  final int height;

  /// Interleaved 8-bit RGB, `width * height * 3` bytes.
  final Uint8List rgb;

  /// JPEG of the same copy — what ML Kit and the kNN embedder consume.
  final Uint8List jpeg;

  const _ScanImage(this.width, this.height, this.rgb, this.jpeg);

  img.Image toImage() => img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgb.buffer,
        bytesOffset: rgb.offsetInBytes,
        numChannels: 3,
        order: img.ChannelOrder.rgb,
      );
}

/// Decode the capture and downscale the longest side to [_scanSide] (smaller
/// captures are left alone — never upscaled). Runs in a worker isolate.
_ScanImage? _decodeAndDownscale(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  final longest = math.max(decoded.width, decoded.height);
  final img.Image small;
  if (longest > _scanSide) {
    final scale = _scanSide / longest;
    small = img.copyResize(
      decoded,
      width: math.max(1, (decoded.width * scale).round()),
      height: math.max(1, (decoded.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
  } else {
    small = decoded;
  }

  final rgb = Uint8List(small.width * small.height * 3);
  var o = 0;
  for (var y = 0; y < small.height; y++) {
    for (var x = 0; x < small.width; x++) {
      final p = small.getPixel(x, y);
      rgb[o++] = p.r.toInt();
      rgb[o++] = p.g.toInt();
      rgb[o++] = p.b.toInt();
    }
  }
  return _ScanImage(
      small.width, small.height, rgb, img.encodeJpg(small, quality: 85));
}

/// Detector instance owned by the worker isolate.
///
/// [Isolate.run] spawns a fresh isolate per call, so the interpreter is brought
/// up inside the worker on first use and dies with it; the main-isolate
/// instance on [VisionPipeline.detector] stays warm for the fallback path.
YoloDetector? _workerDetector;

/// Worker-isolate half of the primary detection stage: preprocess + inference.
Future<List<YoloDetection>> _detectInWorker(
    _ScanImage scan, RootIsolateToken? token) async {
  // Without this the worker isolate has no binary messenger, so `rootBundle`
  // (and therefore `Interpreter.fromAsset`) throws there.
  if (token != null) {
    try {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    } catch (e) {
      debugPrint('TWP:ERROR background messenger: $e');
    }
  }
  final detector = _workerDetector ??= YoloDetector();
  await detector.load();
  return detector.detect(scan.toImage());
}

class ScanResult {
  final ClassificationOutcome outcome;
  final List<Detection> detections;
  final List<VisionLabel> mlkitLabels;
  final KnnResult? knn;
  final int totalMs;

  /// Primary-stage output: every YOLO box with its stream mapping. Kept
  /// alongside [detections] (the legacy normalised-box list the stream
  /// classifier consumes) so existing consumers compile and behave unchanged.
  final List<DetectedObject> objects;

  const ScanResult(
    this.outcome,
    this.detections,
    this.mlkitLabels,
    this.knn,
    this.totalMs, {
    this.objects = const [],
  });
}

class VisionPipeline {
  /// PRIMARY detection stage: YOLO over the 640-px copy (COCO-80).
  final YoloDetector detector = YoloDetector();

  /// Legacy stage — kept wired as the fallback engine and still shipped
  /// (`lib/services/efficientdet.dart`), used only when YOLO returns no boxes.
  final EfficientDetDetector efficientDet = EfficientDetDetector();

  final Embedder embedder = Embedder();
  ImageLabeler? _labeler;

  bool _yoloReady = false;
  bool _warnedWorkerFallback = false;

  /// Diagnostics for the last scan: which stage produced the boxes, and whether
  /// the YOLO call really ran off the main isolate.
  String lastDetectionStage = 'none';
  bool lastYoloIsolated = false;

  /// Ready to scan as soon as one detector and the embedder are up: a missing
  /// YOLO asset degrades to EfficientDet rather than disabling the scanner.
  bool get ready => (_yoloReady || efficientDet.ready) && embedder.ready;

  Future<void> load() async {
    try {
      await detector.load();
      _yoloReady = true;
    } catch (e, st) {
      _yoloReady = false;
      debugPrint('TWP:ERROR yolo load: $e\n$st');
    }
    await embedder.load();
    try {
      await efficientDet.load();
    } catch (e) {
      debugPrint('TWP:ERROR efficientdet load: $e');
    }
  }

  Future<ScanResult?> analyseFile(String path) async {
    final sw = Stopwatch()..start();
    try {
      final bytes = await File(path).readAsBytes();

      // 1) Decode + downscale off the main isolate. Everything downstream —
      //    detector, labeller, embedder — works on this 640-px copy.
      final scan = await Isolate.run(() => _decodeAndDownscale(bytes));
      if (scan == null) return null;

      // 2) PRIMARY: YOLO boxes (decode-adjacent preprocess + inference in the
      //    worker isolate).
      final yolo = await _yoloDetect(scan);
      final objects = _toObjects(yolo);

      // 3) Boxes for the stream decision: YOLO first, legacy EfficientDet only
      //    when YOLO found nothing.
      var detections = _toDetections(yolo, scan);
      if (detections.isNotEmpty) {
        lastDetectionStage = 'yolo';
      } else if (efficientDet.ready) {
        detections = efficientDet.detect(_prepare320(scan));
        lastDetectionStage = detections.isEmpty ? 'labels' : 'efficientdet';
      } else {
        lastDetectionStage = 'labels';
      }

      // 4) Legacy parity: the whole-image labeller runs on EVERY scan, not just
      //    when boxes are weak — its 400+ label vocabulary is what keeps the
      //    scan general instead of seed-specific. Boxes + labels + kNN all vote.
      final mlkitLabels = await _mlkitLabels(scan.jpeg);

      // 5) kNN item identity over the same downscaled copy.
      final vec = embedder.embedImageBytes(scan.jpeg);
      final knn = vec == null ? null : await embedder.nearest(vec);
      final knnLabel = embedder.asLabel(knn);

      final extra = <VisionLabel>[...mlkitLabels, ?knnLabel];
      final knnTrust = (knn?.cosine ?? 0.0) >= Embedder.strongThreshold;
      final outcome = detections.isEmpty
          ? classifyLabels(extra, knnItem: knnLabel?.text ?? '')
          : classifyDetections(detections, extra,
              knnItem: knnLabel?.text ?? '', knnTrust: knnTrust);

      final total = sw.elapsedMilliseconds;
      debugPrint('TWP:RESULT ${_toJson(outcome, detections, mlkitLabels, knn, total, objects)}');
      return ScanResult(outcome, detections, mlkitLabels, knn, total,
          objects: objects);
    } catch (e, st) {
      debugPrint('TWP:ERROR analyse failed: $e\n$st');
      return null;
    }
  }

  /// Primary detection, off the main isolate when the platform allows it.
  Future<List<YoloDetection>> _yoloDetect(_ScanImage scan) async {
    lastYoloIsolated = false;
    try {
      final token = ServicesBinding.rootIsolateToken;
      final found = await Isolate.run(() => _detectInWorker(scan, token));
      lastYoloIsolated = true;
      return found;
    } catch (e) {
      if (!_warnedWorkerFallback) {
        _warnedWorkerFallback = true;
        debugPrint('TWP:yolo worker isolate unavailable ($e) — '
            'running detection on the main isolate');
      }
    }
    if (!_yoloReady) {
      await detector.load();
      _yoloReady = true;
    }
    return detector.detect(scan.toImage());
  }

  /// YOLO boxes → [DetectedObject], each tagged with its stream.
  List<DetectedObject> _toObjects(List<YoloDetection> yolo) {
    final objects = [
      for (final d in yolo)
        DetectedObject(
          label: d.label,
          confidence: d.confidence,
          category: categoriseCocoLabel(d.label),
          wasteRelevant: wasteRelevantFor(d.label),
          x1: d.x1,
          y1: d.y1,
          x2: d.x2,
          y2: d.y2,
        ),
    ];
    // Waste evidence first, strongest first: a consumer that renders only the
    // head of the list shows the box the resident actually cares about.
    objects.sort((a, b) {
      if (a.wasteRelevant != b.wasteRelevant) return a.wasteRelevant ? -1 : 1;
      return b.confidence.compareTo(a.confidence);
    });
    return objects;
  }

  /// YOLO boxes → the normalised `Detection` boxes the stream classifier speaks.
  /// Tolerates both conventions: coordinates already within [0,1] are used
  /// as-is, pixel coordinates are divided by the analysed image size.
  static List<Detection> _toDetections(List<YoloDetection> yolo, _ScanImage scan) {
    final out = <Detection>[];
    for (final d in yolo) {
      final ax1 = _axis(d.x1, scan.width);
      final ax2 = _axis(d.x2, scan.width);
      final ay1 = _axis(d.y1, scan.height);
      final ay2 = _axis(d.y2, scan.height);
      out.add(Detection(
        d.label,
        d.confidence,
        math.min(ay1, ay2),
        math.min(ax1, ax2),
        math.max(ay1, ay2),
        math.max(ax1, ax2),
      ));
    }
    return out;
  }

  static double _axis(double v, int size) {
    if (!v.isFinite) return 0.0;
    return (v > 1.0 ? v / size : v).clamp(0.0, 1.0);
  }

  /// EfficientDet fallback input: 320×320 RGB uint8 sampled from the same
  /// downscaled copy (no second decode of the original file).
  static Uint8List _prepare320(_ScanImage scan) {
    const size = EfficientDetDetector.inputSize;
    final out = Uint8List(size * size * 3);
    final sx = scan.width / size;
    final sy = scan.height / size;
    var o = 0;
    for (var y = 0; y < size; y++) {
      final srcY = math.min(scan.height - 1, (y * sy).floor());
      for (var x = 0; x < size; x++) {
        final srcX = math.min(scan.width - 1, (x * sx).floor());
        final i = (srcY * scan.width + srcX) * 3;
        out[o++] = scan.rgb[i];
        out[o++] = scan.rgb[i + 1];
        out[o++] = scan.rgb[i + 2];
      }
    }
    return out;
  }

  /// ML Kit labelling over the downscaled copy. The bytes are spooled to a
  /// temp file because `InputImage.fromFilePath` is the supported entry point.
  Future<List<VisionLabel>> _mlkitLabels(Uint8List jpeg) async {
    _labeler ??= ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.4));
    File? tmp;
    try {
      final dir = await getTemporaryDirectory();
      tmp = File('${dir.path}/twp_scan_'
          '${DateTime.now().microsecondsSinceEpoch}.jpg');
      await tmp.writeAsBytes(jpeg, flush: true);
      final labels = await _labeler!.processImage(InputImage.fromFilePath(tmp.path));
      return [for (final l in labels) VisionLabel(l.label, l.confidence)];
    } catch (e) {
      debugPrint('TWP:ERROR mlkit: $e');
      return [];
    } finally {
      if (tmp != null) {
        try {
          await tmp.delete();
        } catch (_) {/* temp cleanup is best-effort */}
      }
    }
  }

  String _toJson(ClassificationOutcome o, List<Detection> detections,
      List<VisionLabel> mlkit, KnnResult? knn, int ms, List<DetectedObject> objects) {
    String esc(String s) => s.replaceAll('"', "'");
    final scores = o.scores.entries
        .map((e) => '"${e.key.display}":${e.value.toStringAsFixed(2)}')
        .join(',');
    var recycle = 0, reusable = 0, trash = 0;
    var relevant = 0;
    for (final obj in objects) {
      if (obj.wasteRelevant) relevant++;
      switch (obj.category) {
        case RecycleCategory.recycle:
          recycle++;
        case RecycleCategory.reusable:
          reusable++;
        case RecycleCategory.trash:
          trash++;
      }
    }
    return '{"category":${o.category == null ? "null" : '"${o.category!.display}"'},'
        '"scores":{$scores},'
        '"confidence":${o.confidence},'
        '"needsConfirmation":${o.needsConfirmation},'
        '"matchedFrom":"${esc(o.matchedFrom ?? "")}",'
        '"deviceName":"${esc(o.deviceName)}",'
        '"knnItem":"${esc(knnItemName(o, knn))}",'
        '"knnCos":${knn?.cosine.toStringAsFixed(3) ?? "null"},'
        '"boxes":${detections.length},'
        '"objects":${objects.length},'
        '"wasteRelevant":$relevant,'
        '"streams":{"recycle":$recycle,"reusable":$reusable,"trash":$trash},'
        '"detector":"$lastDetectionStage",'
        '"yoloIsolated":$lastYoloIsolated,'
        '"mlkit":${mlkit.length},'
        '"infrastructure":${o.infrastructure},'
        '"ms":$ms}';
  }

  static String knnItemName(ClassificationOutcome o, KnnResult? knn) =>
      o.knnItem.isNotEmpty ? o.knnItem : (knn?.label ?? '');

  void dispose() {
    detector.dispose();
    efficientDet.dispose();
    embedder.dispose();
    _labeler?.close();
    // The worker-isolate copy of the detector dies with its isolate.
  }
}
