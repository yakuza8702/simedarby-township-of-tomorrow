/// Host-side tests for the YOLO26n-int8 primary asset, its registry wiring, and
/// the decode path shared by both bundled YOLO graphs
/// (`lib/services/yolo_detector.dart`).
///
/// Pure Dart on purpose: the host running `flutter test` has no
/// `libtensorflowlite_c`, so nothing here creates an `Interpreter`. Everything
/// asserted is either a file on disk, registry JSON, the pure model-selection
/// logic ([YoloDetector.candidateChain]), or the real matrix decoder
/// ([YoloDetector.decodeMatrix]) driven with synthetic prediction matrices in
/// the exact shapes the two shipped graphs declare:
///
/// * `assets/models/yolo26n_int8.tflite` (primary) — `[1,3,640,640]` in (NCHW) /
///   `[1,84,8400]` out float32, 80 COCO classes, non-end2end v8-style head;
/// * `assets/models/yolo_detect_fp16.tflite` (fallback) — `[1,640,640,3]` in
///   (NHWC) / `[1,84,8400]` out float32.
///
/// Run: `flutter test test/yolo26_decode_test.dart`
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart' show TensorType;
import 'package:township_of_tomorrow/services/yolo_detector.dart';

/// COCO-80 index used by the fixtures below (ultralytics / COCO-train order).
const int bottleIndex = 39;
const int personIndex = 0;

File assetFile(String name) => File('assets/models/$name');

String readAsset(String name) => assetFile(name).readAsStringSync();

List<String> readLabels(String name) => readAsset(name)
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .toList(growable: false);

/// One hand-written anchor of a prediction matrix, in `xywh` centre form.
class _Anchor {
  const _Anchor(
    this.row,
    this.cx,
    this.cy,
    this.width,
    this.height,
    this.classIndex,
    this.score, {
    this.objectness = 1.0,
  });

  final int row;
  final double cx;
  final double cy;
  final double width;
  final double height;
  final int classIndex;
  final double score;
  final double objectness;
}

/// Builds the raw prediction matrix a graph with [head] would emit.
Float32List _matrixFor(YoloHead head, List<_Anchor> anchors) {
  final logits = Float32List(head.rows * head.cols);
  final step = head.step;
  for (final anchor in anchors) {
    final base = head.transposed ? anchor.row : anchor.row * head.cols;
    logits[base] = anchor.cx;
    logits[base + step] = anchor.cy;
    logits[base + 2 * step] = anchor.width;
    logits[base + 3 * step] = anchor.height;
    if (head.hasObjectness) logits[base + 4 * step] = anchor.objectness;
    logits[base + (head.classBase + anchor.classIndex) * step] = anchor.score;
  }
  return logits;
}

/// Letterbox with no scaling and no padding, so decoded boxes are the raw
/// `xywh` values.
const YoloLetterbox plainLetterbox = YoloLetterbox(
  inputWidth: 640,
  inputHeight: 640,
  sourceWidth: 640,
  sourceHeight: 640,
);

/// The `[1,84,8400]` head both shipped graphs declare.
final YoloHead v8Head =
    YoloHead.resolve(first: 84, second: 8400, labelCount: 80);

void main() {
  group('assets/models/registry.json', () {
    late YoloModelRegistry registry;
    late List<String> cocoLabels;

    setUpAll(() {
      expect(assetFile('registry.json').existsSync(), isTrue,
          reason: 'registry.json must be bundled');
      registry = YoloModelRegistry.parse(readAsset('registry.json'));
      cocoLabels = readLabels('coco_labels.txt');
    });

    test('parses into entries and keeps the non-YOLO engine out of the way', () {
      expect(registry.entries, isNotEmpty);
      expect(registry.yoloEntries.map((entry) => entry.id),
          containsAll(<String>['yolo26n-fp32', 'yolo26n-int8', 'yolo-detect-fp16']));
      expect(registry.yoloEntries.map((entry) => entry.id),
          isNot(contains('efficientdet-lite0-int8')));
      expect(registry.comment, isNotEmpty);
    });

    test('declares yolo_detect_fp16.tflite as the executing primary', () {
      final primary = registry.yoloPrimary;
      expect(primary, isNotNull);
      expect(primary!.id, 'yolo-detect-fp16');
      expect(primary.file, 'yolo_detect_fp16.tflite');
      expect(primary.assetPath, YoloDetector.defaultAssetPath);
      expect(primary.isPrimary, isTrue);
      expect(primary.isYolo, isTrue);
      expect(primary.inputSize, <int>[640, 640]);
      expect(primary.classes, 80);
      expect(primary.outputLayout, 'v8');
      expect(primary.labelAssetPath, 'assets/models/coco_labels.txt');
      expect(primary.note, contains('PRIMARY'));
      expect(primary.note, contains('95.2%'));
      expect(primary.note, contains('81.0%'));
    });

    test('keeps yolo26n_fp32.tflite as a measured candidate', () {
      final candidate = registry.entryForFile('assets/models/yolo26n_fp32.tflite');
      expect(candidate, isNotNull);
      expect(candidate!.id, 'yolo26n-fp32');
      expect(candidate.role, 'candidate');
      expect(candidate.isPrimary, isFalse);
      expect(candidate.isFallback, isFalse);
      expect(candidate.engine, 'YOLO26n fp32');
      expect(candidate.inputSize, <int>[640, 640]);
      expect(candidate.classes, 80);
      expect(candidate.outputLayout, 'v8');
      expect(candidate.sha256,
          '0743bca7eb3ad24d7cf7b792885ef461cf72ce39f54a9bbbd44489b9cbfece13');
      // It executes, it is fast, and it lost on accuracy — all three recorded.
      expect(candidate.note, contains('DOES execute on the bundled runtime'));
      expect(candidate.note, contains('0 tensors with a dynamic signature'));
      expect(candidate.note, contains('85.7%'));
      expect(candidate.note, contains('66.7%'));
      expect(candidate.note, contains('20x'));
      expect(candidate.note, contains('NOT kept as primary'));
      // The re-export recipe has to stay reproducible from the registry alone.
      expect(candidate.source, contains('yolo26n.pt'));
      expect(candidate.source, contains('onnx2tf'));
      expect(candidate.source, contains('TFLiteConverter'));
    });

    test('keeps yolo26n_int8.tflite registered as a candidate, not a load target',
        () {
      final candidate =
          registry.entryForFile('assets/models/yolo26n_int8.tflite');
      expect(candidate, isNotNull);
      expect(candidate!.id, 'yolo26n-int8');
      expect(candidate.role, 'candidate');
      expect(candidate.isPrimary, isFalse);
      expect(candidate.isFallback, isFalse);
      expect(candidate.isYolo, isTrue);
      expect(candidate.inputSize, <int>[640, 640]);
      expect(candidate.classes, 80);
      expect(candidate.outputLayout, 'v8');
      expect(candidate.sha256, isNotEmpty);
      expect(candidate.source, contains('yolo26n_w8a32.tflite'));
      // The steerer's wording, verbatim, so the unblock path cannot drift.
      expect(candidate.note, contains('cannot allocate int8 weight constants'));
      expect(candidate.note, contains('Input tensor 235 lacks data'));
      expect(candidate.note, contains('3 dynamic-shape tensors'));
      expect(candidate.note,
          contains('re-exporting yolo26n float32/dynamic-range without dynamic shapes'));
      expect(candidate.note,
          contains('baseline 95.2% category / 81.0% label'));
      expect(candidate.note, contains('bumping the TFLite/LiteRT runtime'));
      expect(candidate.isPrimary, isFalse,
          reason: 'a graph this runtime cannot allocate must not be auto-loaded');
    });

    test('declares no separate fallback role — the primary is the last resort',
        () {
      expect(registry.yoloFallback, isNull);
      final primary = registry.yoloPrimary!;
      expect(primary.isFallback, isFalse);
      expect(primary.note, contains('last-resort graph'));
    });

    test('the packaged primary asset is a real TFLite flatbuffer', () {
      final file = assetFile('yolo_detect_fp16.tflite');
      expect(file.existsSync(), isTrue,
          reason: 'the registry primary must be bundled');
      final length = file.lengthSync();
      expect(length, greaterThan(1 * 1024 * 1024),
          reason: 'a nano detect graph is megabytes, not a placeholder');
      expect(length, lessThan(32 * 1024 * 1024));

      final bytes = file.openSync().readSync(12);
      expect(String.fromCharCodes(bytes.sublist(0, 2)), isNot('PK'),
          reason: 'a ZIP renamed to .tflite must never be shipped');
      expect(String.fromCharCodes(bytes.sublist(4, 8)), 'TFL3',
          reason: 'TFLite flatbuffer magic lives at offset 4');
      final rootOffset = bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) |
          (bytes[3] << 24);
      expect(rootOffset, greaterThan(8));
      expect(rootOffset, lessThan(length));
    });

    test('every bundled YOLO graph is a real flatbuffer and still shaped v8', () {
      for (final name in <String>[
        'yolo_detect_fp16.tflite',
        'yolo26n_fp32.tflite',
        'yolo26n_int8.tflite',
      ]) {
        final file = assetFile(name);
        expect(file.existsSync(), isTrue, reason: '$name must stay bundled');
        final bytes = file.openSync().readSync(8);
        expect(String.fromCharCodes(bytes.sublist(4, 8)), 'TFL3',
            reason: '$name must be a TFLite flatbuffer');
      }
      final file = assetFile('yolo_detect_fp16.tflite');
      final bytes = file.openSync().readSync(8);
      expect(String.fromCharCodes(bytes.sublist(4, 8)), 'TFL3');
      expect(readLabels('coco_labels.txt').length, 80);
      expect(cocoLabels[bottleIndex], 'bottle');
      expect(cocoLabels[personIndex], 'person');
    });

    test('pubspec declares both graphs as explicit assets', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- assets/models/yolo26n_fp32.tflite'));
      expect(pubspec, contains('- assets/models/yolo26n_int8.tflite'));
      expect(pubspec, contains('- assets/models/yolo_detect_fp16.tflite'));
      expect(pubspec, contains('- assets/models/registry.json'));
    });

    test('malformed registries degrade instead of throwing in the caller', () {
      expect(() => YoloModelRegistry.parse('[]'), throwsFormatException);
      expect(() => YoloModelRegistry.parse('not json'), throwsFormatException);

      final empty = YoloModelRegistry.parse('{"models": []}');
      expect(empty.entries, isEmpty);
      expect(empty.yoloPrimary, isNull);
      expect(empty.yoloFallback, isNull);

      // Wrong-typed keys are skipped, not fatal.
      final sloppy = YoloModelRegistry.parse(jsonEncode(<String, Object>{
        'models': <Object>[
          <String, Object>{'id': 7, 'file': 'x.tflite', 'classes': 'eighty'},
        ],
      }));
      expect(sloppy.entries.single.id, '');
      expect(sloppy.entries.single.file, 'x.tflite');
      expect(sloppy.entries.single.classes, 0);
    });
  });

  group('primary vs fallback model selection', () {
    late YoloModelRegistry registry;

    setUpAll(() {
      registry = YoloModelRegistry.parse(readAsset('registry.json'));
    });

    test('the measured primary is the only graph the chain opens', () {
      final chain = YoloDetector.candidateChain(registry: registry);
      expect(chain.map((candidate) => candidate.assetPath).toList(),
          <String>[YoloDetector.defaultAssetPath]);
      expect(chain.single.entryId, 'yolo-detect-fp16');
      expect(chain.single.role, 'primary');
      expect(chain.single.isFallback, isTrue,
          reason: 'last resort of the chain, and the registry primary');
      expect(chain.single.engineName, 'YOLO detect fp16 · TFLite · on-device');
      expect(chain.single.labelAssetPaths, <String>[
        'assets/models/coco_labels.txt',
        'assets/models/coco-labels.txt',
      ]);
      // Neither candidate is tried: the int8 graph cannot be allocated here and
      // the fp32 graph measured below the shipped accuracy.
      expect(
          chain.any((candidate) => candidate.assetPath.contains('yolo26n')),
          isFalse);
    });

    test('a promoted candidate leads the chain again (the documented unblock)',
        () {
      final promoted = YoloModelRegistry.parse(jsonEncode(<String, Object>{
        'models': <Object>[
          <String, Object>{
            'id': 'yolo26n-int8',
            'file': 'yolo26n_int8.tflite',
            'labels': 'coco_labels.txt',
            'format': 'yolo',
            'role': 'primary',
            'engine': 'YOLO26n int8',
          },
        ],
      }));
      final chain = YoloDetector.candidateChain(registry: promoted);
      expect(chain, hasLength(2));
      expect(chain.first.assetPath, 'assets/models/yolo26n_int8.tflite');
      expect(chain.first.role, 'primary');
      expect(chain.first.isFallback, isFalse);
      expect(chain.last.assetPath, YoloDetector.defaultAssetPath);
      expect(chain.last.isFallback, isTrue);
    });

    test('an explicitly pinned candidate is still honoured', () {
      final chain = YoloDetector.candidateChain(
        assetPath: 'assets/models/yolo26n_int8.tflite',
        registry: registry,
      );
      expect(chain, hasLength(1));
      expect(chain.single.assetPath, 'assets/models/yolo26n_int8.tflite');
      expect(chain.single.role, 'pinned');
      expect(chain.single.isFallback, isTrue);
    });

    test('no registry at all reproduces the pre-change behaviour', () {
      final chain = YoloDetector.candidateChain();
      expect(chain, hasLength(1));
      expect(chain.single.assetPath, YoloDetector.defaultAssetPath);
      expect(chain.single.labelAssetPaths.first,
          YoloDetector.defaultLabelAssetPath);
      expect(YoloDetector.defaultAssetPath,
          'assets/models/yolo_detect_fp16.tflite');
      expect(YoloDetector.defaultConfidenceThreshold, 0.25);
    });

    test('a pinned assetPath ignores the registry primary', () {
      final chain = YoloDetector.candidateChain(
        assetPath: 'assets/models/custom_model.tflite',
        registry: registry,
      );
      expect(chain, hasLength(1));
      expect(chain.single.assetPath, 'assets/models/custom_model.tflite');
      expect(chain.single.role, 'pinned');
      expect(chain.single.entryId, '');
      expect(chain.single.engineName, YoloDetector.defaultEngineName);
    });

    test('a registry that promotes the fallback dedupes to one candidate', () {
      final promoted = YoloModelRegistry.parse(jsonEncode(<String, Object>{
        'models': <Object>[
          <String, Object>{
            'id': 'fp16-only',
            'file': 'yolo_detect_fp16.tflite',
            'labels': 'coco_labels.txt',
            'format': 'yolo',
            'role': 'primary',
          },
        ],
      }));
      final chain = YoloDetector.candidateChain(registry: promoted);
      expect(chain, hasLength(1));
      expect(chain.single.assetPath, YoloDetector.defaultAssetPath);
    });

    test('role-less registries fall back to file order', () {
      final roleless = YoloModelRegistry.parse(jsonEncode(<String, Object>{
        'models': <Object>[
          <String, Object>{
            'id': 'first',
            'file': 'a.tflite',
            'format': 'yolo',
          },
          <String, Object>{
            'id': 'second',
            'file': 'b.tflite',
            'format': 'yolo',
          },
        ],
      }));
      expect(roleless.yoloPrimary!.id, 'first');
      expect(roleless.yoloFallback, isNull);
      final chain = YoloDetector.candidateChain(registry: roleless);
      expect(chain.first.assetPath, 'assets/models/a.tflite');
      expect(chain.last.assetPath, YoloDetector.defaultAssetPath);
    });
  });

  group('head layout resolution', () {
    test('[1,84,8400] resolves to the v8/v26 transposed head', () {
      expect(v8Head.transposed, isTrue);
      expect(v8Head.rows, 8400);
      expect(v8Head.cols, 84);
      expect(v8Head.hasObjectness, isFalse);
      expect(v8Head.classCount, 80);
      expect(v8Head.classBase, 4);
      expect(v8Head.step, 8400);
      // Both shipped graphs declare exactly this tensor.
      expect(YoloHead.resolve(first: 84, second: 8400, labelCount: 80).rows,
          8400);
      // The row-major spelling of the same matrix decodes identically.
      final rowMajor = YoloHead.resolve(first: 8400, second: 84, labelCount: 80);
      expect(rowMajor.transposed, isFalse);
      expect(rowMajor.rows, 8400);
      expect(rowMajor.step, 1);
    });

    test('[1,25200,85] resolves to the v5 head with objectness', () {
      final v5 = YoloHead.resolve(first: 25200, second: 85, labelCount: 80);
      expect(v5.transposed, isFalse);
      expect(v5.rows, 25200);
      expect(v5.cols, 85);
      expect(v5.hasObjectness, isTrue);
      expect(v5.classCount, 80);
      expect(v5.classBase, 5);
    });

    test('a 5-class custom graph lands on the right stride', () {
      final custom = YoloHead.resolve(first: 9, second: 8400, labelCount: 5);
      expect(custom.hasObjectness, isFalse);
      expect(custom.classCount, 5);
      // 6 columns (4 box + 5 classes + objectness) round-trip as well.
      final customV5 = YoloHead.resolve(first: 10, second: 8400, labelCount: 5);
      expect(customV5.hasObjectness, isTrue);
      expect(customV5.classCount, 5);
    });

    test('input shapes of both graphs resolve to 640x640', () {
      final fp16 = YoloDetector.resolveInputLayout(<int>[1, 640, 640, 3]);
      expect(<int>[fp16.width, fp16.height], <int>[640, 640]);
      expect(fp16.isChw, isFalse);

      final primary = YoloDetector.resolveInputLayout(<int>[1, 3, 640, 640]);
      expect(<int>[primary.width, primary.height], <int>[640, 640]);
      expect(primary.isChw, isTrue,
          reason: 'yolo26n_int8.tflite is NCHW — the existing path handles it');

      final dynamicShape = YoloDetector.resolveInputLayout(<int>[1, -1, -1, 3]);
      expect(<int>[dynamicShape.width, dynamicShape.height], <int>[640, 640]);
    });
  });

  group('decode of a synthetic [84, 8400] matrix', () {
    late List<String> cocoLabels;

    setUpAll(() => cocoLabels = readLabels('coco_labels.txt'));

    test('boxes, class scores, labels and class-agnostic NMS', () {
      final detections = YoloDetector.decodeMatrix(
        _matrixFor(v8Head, const <_Anchor>[
          // bottle at (320,320), kept.
          _Anchor(0, 320, 320, 100, 200, bottleIndex, 0.90),
          // Same patch, lower score, same class: suppressed by NMS.
          _Anchor(1, 322, 318, 100, 200, bottleIndex, 0.80),
          // person somewhere else: also kept.
          _Anchor(2, 500, 100, 40, 60, personIndex, 0.70),
        ]),
        head: v8Head,
        letterbox: plainLetterbox,
        labels: cocoLabels,
      );

      expect(detections, hasLength(2), reason: 'NMS keeps one box per patch');
      expect(detections.first.label, 'bottle');
      expect(detections.first.confidence, closeTo(0.90, 1e-6));
      expect(detections.first.x1, closeTo(270, 1e-6));
      expect(detections.first.y1, closeTo(220, 1e-6));
      expect(detections.first.x2, closeTo(370, 1e-6));
      expect(detections.first.y2, closeTo(420, 1e-6));
      expect(detections.first.width, closeTo(100, 1e-6));
      expect(detections.first.height, closeTo(200, 1e-6));

      expect(detections.last.label, 'person');
      expect(detections.last.confidence, closeTo(0.70, 1e-6));
      expect(detections.last.x1, closeTo(480, 1e-6));
      expect(detections.last.y1, closeTo(70, 1e-6));
      expect(detections.last.x2, closeTo(520, 1e-6));
      expect(detections.last.y2, closeTo(130, 1e-6));
    });

    test('NMS is class-agnostic across overlapping classes', () {
      final detections = YoloDetector.decodeMatrix(
        _matrixFor(v8Head, const <_Anchor>[
          _Anchor(0, 300, 300, 100, 100, bottleIndex, 0.90),
          _Anchor(1, 305, 300, 100, 100, personIndex, 0.85),
        ]),
        head: v8Head,
        letterbox: plainLetterbox,
        labels: cocoLabels,
      );
      expect(detections, hasLength(1));
      expect(detections.single.label, 'bottle');
    });

    test('labels come from the index table, class #N without one', () {
      final matrix = _matrixFor(v8Head, const <_Anchor>[
        _Anchor(0, 320, 320, 100, 100, bottleIndex, 0.90),
      ]);
      expect(
          YoloDetector.decodeMatrix(matrix,
              head: v8Head, letterbox: plainLetterbox, labels: cocoLabels)
              .single
              .label,
          'bottle');
      expect(
          YoloDetector.decodeMatrix(matrix,
                  head: v8Head, letterbox: plainLetterbox)
              .single
              .label,
          'class #$bottleIndex');
    });

    test('the 0.25 floor applies, with one relaxed retry at 0.05', () {
      final weak = _matrixFor(v8Head, const <_Anchor>[
        _Anchor(0, 320, 320, 100, 100, bottleIndex, 0.20),
      ]);
      // With the retry clamped to the floor, a 0.20-only matrix stays empty…
      expect(
          YoloDetector.decodeMatrix(weak,
              head: v8Head,
              letterbox: plainLetterbox,
              labels: cocoLabels,
              confidenceThreshold: 0.25,
              retryConfidenceThreshold: 0.25),
          isEmpty);
      // …the documented 0.05 retry does pick it up…
      expect(
          YoloDetector.decodeMatrix(weak,
                  head: v8Head,
                  letterbox: plainLetterbox,
                  labels: cocoLabels,
                  confidenceThreshold: 0.25,
                  retryConfidenceThreshold: 0.05)
              .single
              .confidence,
          closeTo(0.20, 1e-6));
      // …and the retry is what [detect] runs by default.
      expect(
          YoloDetector.decodeMatrix(weak,
                  head: v8Head, letterbox: plainLetterbox, labels: cocoLabels)
              .single
              .confidence,
          closeTo(0.20, 1e-6));
      // A confident box suppresses the retry entirely.
      final detections = YoloDetector.decodeMatrix(
        _matrixFor(v8Head, const <_Anchor>[
          _Anchor(0, 320, 320, 100, 100, bottleIndex, 0.90),
          _Anchor(1, 100, 100, 50, 50, personIndex, 0.20),
        ]),
        head: v8Head,
        letterbox: plainLetterbox,
        labels: cocoLabels,
        confidenceThreshold: 0.25,
        retryConfidenceThreshold: 0.05,
      );
      expect(detections, hasLength(1));
      expect(detections.single.label, 'bottle');
    });

    test('letterbox scale and padding are inverted exactly', () {
      final detections = YoloDetector.decodeMatrix(
        _matrixFor(v8Head, const <_Anchor>[
          _Anchor(0, 340, 210, 100, 60, bottleIndex, 0.90),
        ]),
        head: v8Head,
        letterbox: const YoloLetterbox(
          inputWidth: 640,
          inputHeight: 640,
          scale: 0.5,
          padX: 20,
          padY: 10,
          sourceWidth: 1200,
          sourceHeight: 700,
        ),
        labels: cocoLabels,
      );
      expect(detections.single.x1, closeTo(540, 1e-6));
      expect(detections.single.y1, closeTo(340, 1e-6));
      expect(detections.single.x2, closeTo(740, 1e-6));
      expect(detections.single.y2, closeTo(460, 1e-6));
    });

    test('normalised (0..1) box outputs are rescaled to input pixels', () {
      final detections = YoloDetector.decodeMatrix(
        _matrixFor(v8Head, const <_Anchor>[
          _Anchor(0, 0.5, 0.5, 0.25, 0.5, bottleIndex, 0.90),
        ]),
        head: v8Head,
        letterbox: plainLetterbox,
        labels: cocoLabels,
      );
      expect(detections.single.x1, closeTo(240, 1e-6));
      expect(detections.single.y1, closeTo(160, 1e-6));
      expect(detections.single.x2, closeTo(400, 1e-6));
      expect(detections.single.y2, closeTo(480, 1e-6));
    });

    test('boxes are clamped to the source image', () {
      final detections = YoloDetector.decodeMatrix(
        _matrixFor(v8Head, const <_Anchor>[
          _Anchor(0, 195, 195, 40, 40, bottleIndex, 0.90),
        ]),
        head: v8Head,
        letterbox: const YoloLetterbox(
          inputWidth: 640,
          inputHeight: 640,
          sourceWidth: 200,
          sourceHeight: 200,
        ),
        labels: cocoLabels,
      );
      expect(detections.single.x1, 175);
      expect(detections.single.y1, 175);
      expect(detections.single.x2, 200);
      expect(detections.single.y2, 200);
    });

    test('maxDetections caps the returned boxes', () {
      final detections = YoloDetector.decodeMatrix(
        _matrixFor(v8Head, const <_Anchor>[
          _Anchor(0, 100, 100, 20, 20, bottleIndex, 0.90),
          _Anchor(1, 300, 100, 20, 20, personIndex, 0.80),
          _Anchor(2, 500, 100, 20, 20, bottleIndex, 0.70),
        ]),
        head: v8Head,
        letterbox: plainLetterbox,
        labels: cocoLabels,
        maxDetections: 2,
      );
      expect(detections, hasLength(2));
      expect(detections.map((d) => d.confidence).toList(),
          <dynamic>[closeTo(0.90, 1e-6), closeTo(0.80, 1e-6)]);
    });

    test('degenerate matrices decode to nothing instead of throwing', () {
      expect(
          YoloDetector.decodeMatrix(Float32List(v8Head.rows * v8Head.cols),
              head: v8Head, letterbox: plainLetterbox, labels: cocoLabels),
          isEmpty);
    });
  });

  group('decode of a v5-style [25200, 85] matrix', () {
    final v5Head =
        YoloHead.resolve(first: 25200, second: 85, labelCount: 80);

    test('score is objectness x class probability', () {
      final detections = YoloDetector.decodeMatrix(
        _matrixFor(v5Head, const <_Anchor>[
          _Anchor(0, 320, 320, 100, 100, bottleIndex, 0.50, objectness: 0.80),
        ]),
        head: v5Head,
        letterbox: plainLetterbox,
        labels: readLabels('coco_labels.txt'),
      );
      expect(detections, hasLength(1));
      expect(detections.single.confidence, closeTo(0.40, 1e-6));
      expect(detections.single.label, 'bottle');
    });

    test('the objectness gate drops rows before the class scan', () {
      final detections = YoloDetector.decodeMatrix(
        _matrixFor(v5Head, const <_Anchor>[
          _Anchor(0, 320, 320, 100, 100, bottleIndex, 0.90, objectness: 0.10),
        ]),
        head: v5Head,
        letterbox: plainLetterbox,
        labels: readLabels('coco_labels.txt'),
        confidenceThreshold: 0.25,
        retryConfidenceThreshold: 0.25,
      );
      expect(detections, isEmpty,
          reason: 'objectness 0.10 < 0.25 must never reach the class scan');
    });
  });

  group('generalized decoder vs the pre-change decoder', () {
    late List<String> cocoLabels;

    setUpAll(() => cocoLabels = readLabels('coco_labels.txt'));

    test('200 random matrices decode identically in all three spellings', () {
      final random = math.Random(20261015);
      final heads = <YoloHead>[
        v8Head, // [1,84,8400] — what both shipped graphs declare
        YoloHead.resolve(first: 8400, second: 84, labelCount: 80),
        YoloHead.resolve(first: 25200, second: 85, labelCount: 80),
      ];
      var withDetections = 0;

      for (var iteration = 0; iteration < 200; iteration++) {
        final head = heads[iteration % heads.length];
        // Half the sweeps use normalised (0..1) boxes, half pixel-space ones.
        final normalised = random.nextBool();
        final anchors = <_Anchor>[
          for (var i = 0; i < 1 + random.nextInt(6); i++)
            _Anchor(
              random.nextInt(12),
              normalised ? random.nextDouble() : random.nextDouble() * 640,
              normalised ? random.nextDouble() : random.nextDouble() * 640,
              normalised ? random.nextDouble() * 0.5 : random.nextDouble() * 300,
              normalised ? random.nextDouble() * 0.5 : random.nextDouble() * 300,
              random.nextInt(head.classCount),
              random.nextDouble(),
              objectness: random.nextDouble(),
            ),
        ];
        final logits = _matrixFor(head, anchors);
        final letterbox = YoloLetterbox(
          inputWidth: 640,
          inputHeight: 640,
          scale: 0.3 + random.nextDouble() * 1.2,
          padX: random.nextInt(60),
          padY: random.nextInt(60),
          sourceWidth: 200 + random.nextInt(1080),
          sourceHeight: 200 + random.nextInt(880),
        );
        final confidenceThreshold = <double>[0.1, 0.25, 0.5][random.nextInt(3)];
        final iouThreshold = 0.3 + random.nextDouble() * 0.4;
        final maxDetections = 1 + random.nextInt(8);
        final reason = 'iteration $iteration head=${head.rows}x${head.cols}';

        final expected = _legacyDecode(
          logits,
          head: head,
          labels: cocoLabels,
          confidenceThreshold: confidenceThreshold,
          iouThreshold: iouThreshold,
          maxDetections: maxDetections,
          letterbox: letterbox,
        );
        final actual = YoloDetector.decodeMatrix(
          logits,
          head: head,
          letterbox: letterbox,
          labels: cocoLabels,
          confidenceThreshold: confidenceThreshold,
          iouThreshold: iouThreshold,
          maxDetections: maxDetections,
        );

        expect(actual.length, expected.length, reason: reason);
        for (var i = 0; i < actual.length; i++) {
          expect(actual[i].label, expected[i].label, reason: '$reason #$i');
          expect(actual[i].confidence, closeTo(expected[i].confidence, 1e-9),
              reason: '$reason #$i');
          expect(actual[i].x1, closeTo(expected[i].x1, 1e-9), reason: '$reason #$i');
          expect(actual[i].y1, closeTo(expected[i].y1, 1e-9), reason: '$reason #$i');
          expect(actual[i].x2, closeTo(expected[i].x2, 1e-9), reason: '$reason #$i');
          expect(actual[i].y2, closeTo(expected[i].y2, 1e-9), reason: '$reason #$i');
        }
        if (actual.isNotEmpty) withDetections++;
      }

      expect(withDetections, greaterThan(20),
          reason: 'the sweep must actually exercise NMS + label mapping');
    });
  });

  group('isolate-safe loading contract', () {
    // A stub bundle backed by the real files on disk, so resolveChain() runs its
    // production code path without ServicesBinding — which a worker isolate
    // spawned by Isolate.run has none of. That is exactly the bug this contract
    // exists to fix.
    Future<ByteData> diskBytes(String asset) async {
      final file = File(asset);
      if (!file.existsSync()) {
        throw FileSystemException('not bundled', asset);
      }
      final bytes = await file.readAsBytes();
      return ByteData.view(
          bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
    }

    Future<String> diskString(String asset) async {
      final file = File(asset);
      if (!file.existsSync()) {
        throw FileSystemException('not bundled', asset);
      }
      return file.readAsStringSync();
    }

    late Directory cacheDir;

    setUp(() {
      cacheDir = Directory.systemTemp.createTempSync('township_yolo_test_');
    });

    tearDown(() {
      if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
    });

    test('resolves the primary and never asks for either candidate',
        () async {
      final requested = <String>[];
      final chain = await YoloModelAssets.resolveChain(
        loadBytes: (asset) async {
          requested.add(asset);
          return diskBytes(asset);
        },
        loadString: (asset) async {
          requested.add(asset);
          return diskString(asset);
        },
        materialise: false,
      );

      expect(chain, hasLength(1));
      expect(chain.single.assetPath, YoloDetector.defaultAssetPath);
      expect(chain.single.role, 'primary');
      expect(chain.single.isFallback, isTrue);
      expect(chain.single.entryId, 'yolo-detect-fp16');
      expect(chain.single.isFlatbuffer, isTrue);
      expect(chain.single.engineName, 'YOLO detect fp16 · TFLite · on-device');
      expect(chain.single.modelBytes.length,
          assetFile('yolo_detect_fp16.tflite').lengthSync());
      expect(String.fromCharCodes(chain.single.modelBytes.sublist(4, 8)), 'TFL3');
      expect(chain.single.labels, hasLength(80));
      expect(chain.single.labels[bottleIndex], 'bottle');
      expect(chain.single.labelAssetPath, 'assets/models/coco_labels.txt');
      expect(chain.single.cacheFileName, YoloDetector.tempModelFileName);

      // Neither candidate is even read: no wasted cold-start work at all.
      expect(requested.where((asset) => asset.contains('yolo26n')), isEmpty);
      expect(requested, contains('assets/models/registry.json'));
      expect(requested, contains(YoloDetector.defaultAssetPath));
    });

    test('a primary that is a renamed archive leaves nothing to load',
        () async {
      final zip = Uint8List.fromList(
          <int>[0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0, 1, 2, 3]);
      expect(
          () => YoloModelAssets.resolveChain(
                loadBytes: (asset) async => asset.endsWith('.tflite')
                    ? ByteData.view(zip.buffer)
                    : diskBytes(asset),
                loadString: diskString,
                materialise: false,
              ),
          throwsA(isA<StateError>()));

      expect(
          YoloModelAssets(
            assetPath: 'assets/models/evil.tflite',
            modelBytes: zip,
            labels: const <String>[],
          ).isFlatbuffer,
          isFalse);
      expect(
          YoloModelAssets(
            assetPath: 'assets/models/short.tflite',
            modelBytes: Uint8List.fromList(<int>[0, 0, 0, 0]),
            labels: const <String>[],
          ).isFlatbuffer,
          isFalse);
    });

    test('the main isolate materialises a chain any isolate can reload',
        () async {
      final resolved = await YoloModelAssets.resolveChain(
        loadBytes: diskBytes,
        loadString: diskString,
        cacheDirectory: cacheDir,
      );
      expect(resolved, hasLength(1));

      // No bundle, no bindings: this is what a worker isolate calls.
      final cached = await YoloModelAssets.loadCached(directory: cacheDir);
      expect(cached.map((assets) => assets.assetPath).toList(),
          resolved.map((assets) => assets.assetPath).toList());
      expect(cached.single.role, 'primary');
      expect(cached.single.engine, 'YOLO detect fp16');
      expect(cached.single.labels, resolved.single.labels);
      expect(cached.single.modelBytes.length, resolved.single.modelBytes.length);
      expect(cached.single.modelBytes.sublist(4, 8),
          resolved.single.modelBytes.sublist(4, 8));
      expect(cached.single.isFlatbuffer, isTrue);
      expect(cached.single.isFallback, isTrue);
      expect(
          File('${cacheDir.path}/${YoloModelAssets.manifestFileName}')
              .existsSync(),
          isTrue);

      final emptyDir = Directory.systemTemp.createTempSync('township_empty_');
      expect(await YoloModelAssets.loadCached(directory: emptyDir), isEmpty);
      emptyDir.deleteSync(recursive: true);
    });

    test('runtime verdicts stick to the content that failed', () async {
      final assets = YoloModelAssets(
        assetPath: 'assets/models/yolo26n_int8.tflite',
        modelBytes: await assetFile('yolo26n_int8.tflite').readAsBytes(),
        labels: const <String>[],
      );
      final replaced = YoloModelAssets(
        assetPath: assets.assetPath,
        modelBytes: Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
        labels: const <String>[],
      );
      final relocated = YoloModelAssets(
        assetPath: 'assets/models/other.tflite',
        modelBytes: assets.modelBytes,
        labels: const <String>[],
      );

      expect(YoloRuntimeVerdict.fingerprintOf(assets),
          YoloRuntimeVerdict.fingerprintOf(assets));
      expect(YoloRuntimeVerdict.fingerprintOf(assets),
          isNot(YoloRuntimeVerdict.fingerprintOf(replaced)));
      expect(YoloRuntimeVerdict.fingerprintOf(assets),
          isNot(YoloRuntimeVerdict.fingerprintOf(relocated)));

      expect(await YoloRuntimeVerdict.isBlocked(assets, directory: cacheDir),
          isFalse);
      await YoloRuntimeVerdict.record(
          YoloRuntimeVerdict.fingerprintOf(assets),
          'Bad state: failed precondition',
          directory: cacheDir);
      expect(await YoloRuntimeVerdict.isBlocked(assets, directory: cacheDir),
          isTrue);
      // A replaced model, another path, and another cache dir are all unaffected.
      expect(
          await YoloRuntimeVerdict.isBlocked(replaced, directory: cacheDir),
          isFalse);
      expect(
          await YoloRuntimeVerdict.isBlocked(relocated, directory: cacheDir),
          isFalse);
      final fresh = Directory.systemTemp.createTempSync('township_verdict_');
      expect(await YoloRuntimeVerdict.isBlocked(assets, directory: fresh),
          isFalse);
      fresh.deleteSync(recursive: true);

      final stored = await YoloRuntimeVerdict.load(directory: cacheDir);
      expect(stored, hasLength(1));
      expect(stored.values.single, contains('failed precondition'));
    });

    test('label tables are parsed the same way everywhere', () {
      expect(
          YoloModelAssets.parseLabels(
              'person\n\n  bottle  \n???\ntoothbrush\n'),
          <String>['person', 'bottle', 'toothbrush']);
      expect(YoloModelAssets.parseLabels(''), isEmpty);
    });

    test('dtype byte sizes cover the readable tensor types', () {
      expect(YoloDetector.bytesPerElement(TensorType.float32), 4);
      expect(YoloDetector.bytesPerElement(TensorType.float16), 2);
      expect(YoloDetector.bytesPerElement(TensorType.int8), 1);
      expect(YoloDetector.bytesPerElement(TensorType.uint8), 1);
      expect(YoloDetector.bytesPerElement(TensorType.int32), 0);
    });

    test('float16 conversion round-trips', () {
      expect(YoloDetector.toHalfBits(0.0), 0x0000);
      expect(YoloDetector.toHalfBits(1.0), 0x3C00);
      expect(YoloDetector.toHalfBits(0.5), 0x3800);
      expect(YoloDetector.toHalfBits(-1.0), 0xBC00);
      expect(YoloDetector.halfToDouble(0x3C00), 1.0);
      expect(YoloDetector.halfToDouble(0x3800), 0.5);
      for (final value in <double>[0.0, 0.25, 0.5, 0.75, 1.0, -0.5, 0.333333]) {
        expect(YoloDetector.halfToDouble(YoloDetector.toHalfBits(value)),
            closeTo(value, 0.001),
            reason: 'round-trip of $value');
      }
      expect(YoloDetector.halfToDouble(YoloDetector.toHalfBits(70000.0)),
          double.infinity);
    });
  });
}

// ───────────────────────── differential oracle ─────────────────────────────
// The decoder as it existed BEFORE the registry/primary change, transcribed
// from the previous revision of `lib/services/yolo_detector.dart` (the `collect`
// closure inside `detect`, `_boxesLookNormalized`, `_nonMaxSuppression`,
// `_intersectionOverUnion`, `_labelFor`). It exists only to prove the
// generalized decoder is numerically identical, and is not shipped code.

class _LegacyCandidate {
  const _LegacyCandidate(
      this.labelIndex, this.score, this.x1, this.y1, this.x2, this.y2);

  final int labelIndex;
  final double score;
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  double get area => math.max(0.0, x2 - x1) * math.max(0.0, y2 - y1);
}

double _legacyIou(_LegacyCandidate a, _LegacyCandidate b) {
  final x1 = math.max(a.x1, b.x1);
  final y1 = math.max(a.y1, b.y1);
  final x2 = math.min(a.x2, b.x2);
  final y2 = math.min(a.y2, b.y2);
  final intersection = math.max(0.0, x2 - x1) * math.max(0.0, y2 - y1);
  if (intersection <= 0) return 0.0;
  final union = a.area + b.area - intersection;
  return union <= 0 ? 0.0 : intersection / union;
}

List<_LegacyCandidate> _legacyNms(
  List<_LegacyCandidate> candidates,
  double iouThreshold,
  int maxDetections,
) {
  if (candidates.isEmpty) return candidates;
  final sorted = List<_LegacyCandidate>.of(candidates)
    ..sort((a, b) => b.score.compareTo(a.score));
  final pool = sorted.length > 3000 ? sorted.sublist(0, 3000) : sorted;
  final kept = <_LegacyCandidate>[];
  for (final candidate in pool) {
    var suppressed = false;
    for (final chosen in kept) {
      if (_legacyIou(chosen, candidate) > iouThreshold) {
        suppressed = true;
        break;
      }
    }
    if (suppressed) continue;
    kept.add(candidate);
    if (kept.length >= maxDetections) break;
  }
  return kept;
}

bool _legacyBoxesLookNormalized(
  Float32List logits, {
  required YoloHead head,
  required double confidenceThreshold,
}) {
  final step = head.step;
  final classBase = head.classBase;
  var sampled = 0;
  var maxAbs = 0.0;
  for (var row = 0; row < head.rows && sampled < 256; row++) {
    final base = head.transposed ? row : row * head.cols;
    var gate = head.hasObjectness ? logits[base + 4 * step] : 0.0;
    if (!head.hasObjectness) {
      for (var c = 0; c < head.classCount; c++) {
        final score = logits[base + (classBase + c) * step];
        if (score > gate) gate = score;
      }
    }
    if (gate < confidenceThreshold) continue;
    sampled++;
    for (var c = 0; c < 4; c++) {
      final value = logits[base + c * step].abs();
      if (value > maxAbs) maxAbs = value;
    }
  }
  if (sampled == 0) return false;
  return maxAbs <= 2.0;
}

List<YoloDetection> _legacyDecode(
  Float32List logits, {
  required YoloHead head,
  required List<String> labels,
  required double confidenceThreshold,
  required double iouThreshold,
  required int maxDetections,
  required YoloLetterbox letterbox,
}) {
  final boxesNormalized = _legacyBoxesLookNormalized(logits,
      head: head, confidenceThreshold: confidenceThreshold);
  final boxScaleX = boxesNormalized ? letterbox.inputWidth.toDouble() : 1.0;
  final boxScaleY = boxesNormalized ? letterbox.inputHeight.toDouble() : 1.0;
  final classBase = head.classBase;
  final step = head.step;

  List<_LegacyCandidate> collect(double threshold) {
    final candidates = <_LegacyCandidate>[];
    for (var row = 0; row < head.rows; row++) {
      final base = head.transposed ? row : row * head.cols;
      final double cx = logits[base] * boxScaleX;
      final double cy = logits[base + step] * boxScaleY;
      final double bw = logits[base + 2 * step] * boxScaleX;
      final double bh = logits[base + 3 * step] * boxScaleY;
      final double objectness = head.hasObjectness ? logits[base + 4 * step] : 1.0;
      if (objectness < threshold) continue;

      var bestClass = -1;
      var bestScore = 0.0;
      for (var c = 0; c < head.classCount; c++) {
        final score = logits[base + (classBase + c) * step];
        if (score > bestScore) {
          bestScore = score;
          bestClass = c;
        }
      }
      if (bestClass < 0) continue;

      final confidence = head.hasObjectness ? objectness * bestScore : bestScore;
      if (confidence < threshold) continue;

      final double left = ((cx - bw / 2) - letterbox.padX) / letterbox.scale;
      final double top = ((cy - bh / 2) - letterbox.padY) / letterbox.scale;
      final double right = ((cx + bw / 2) - letterbox.padX) / letterbox.scale;
      final double bottom = ((cy + bh / 2) - letterbox.padY) / letterbox.scale;
      if (right <= left || bottom <= top) continue;

      candidates.add(_LegacyCandidate(
        bestClass,
        confidence,
        left.clamp(0.0, letterbox.sourceWidth.toDouble()),
        top.clamp(0.0, letterbox.sourceHeight.toDouble()),
        right.clamp(0.0, letterbox.sourceWidth.toDouble()),
        bottom.clamp(0.0, letterbox.sourceHeight.toDouble()),
      ));
    }
    return candidates;
  }

  var usedThreshold = confidenceThreshold;
  var candidates = collect(usedThreshold);
  var kept = _legacyNms(candidates, iouThreshold, maxDetections);
  if (kept.isEmpty && usedThreshold > 0.05) {
    usedThreshold = 0.05;
    candidates = collect(usedThreshold);
    kept = _legacyNms(candidates, iouThreshold, maxDetections);
  }

  return <YoloDetection>[
    for (final candidate in kept)
      YoloDetection(
        candidate.labelIndex >= 0 && candidate.labelIndex < labels.length
            ? labels[candidate.labelIndex]
            : 'class #${candidate.labelIndex}',
        candidate.score,
        candidate.x1,
        candidate.y1,
        candidate.x2,
        candidate.y2,
      ),
  ];
}
