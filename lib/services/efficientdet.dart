/// EfficientDet-Lite0 (int8, 320×320) raw-head detector for Flutter.
///
/// The model emits raw SSD heads — a [1,19206,90] class-score tensor and a
/// [1,19206,4] anchor-relative box tensor — with NO NMS and NO anchor
/// decoding. Both halves below are ported from
/// google/automl efficientdet/tf2/anchors.py and from the legacy
/// TfliteDetector.java (validated: 19206 anchors exactly, emulator-proven).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../types.dart';

class EfficientDetDetector {
  static const inputSize = 320;
  /// Below this the candidate is not worth the NMS pass; the caller filters harder anyway.
  static const efficientdetFloor = 0.25;

  static const anchorMinLevel = 3;
  static const anchorMaxLevel = 7;
  static const anchorScalesPerOctave = 3;
  static const anchorAspectRatios = [1.0, 2.0, 0.5];

  Interpreter? _interpreter;
  List<String> _labels = [];
  double _anchorScale = 3.0;
  Float32List? _anchors; // packed: n*4 as y0,x0,y1,x1
  int _numAnchors = 0;

  // Reusable IO buffers (the scores tensor alone is ~7 MB).
  Uint8List _input = Uint8List(inputSize * inputSize * 3);
  Uint8List? _outBoxesBytes;
  Uint8List? _outScoresBytes;

  bool get ready => _interpreter != null && _labels.isNotEmpty;

  String get engineName => 'EfficientDet-Lite0 · TFLite · on-device';

  Future<void> load() async {
    if (ready) return;
    final t = Stopwatch()..start();
    _interpreter = await Interpreter.fromAsset(
      'assets/models/efficientdet-lite0-int8.tflite',
      options: InterpreterOptions()..threads = 4,
    );
    final labelsRaw = await rootBundle.loadString('assets/models/coco-labels.txt');
    _labels = labelsRaw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && l != '???')
        .toList();
    final inputT = _interpreter!.getInputTensor(0);
    debugPrint('TWP:model input ${inputT.shape} ${inputT.type} '
        '${_interpreter!.getOutputTensor(0).shape} '
        '${_interpreter!.getOutputTensor(1).shape} loaded=${t.elapsedMilliseconds}ms');
  }

  void setAnchorScale(double scale) => _anchorScale = scale;

  /// Anchors as packed y0,x0,y1,x1 float32s — same construction as
  /// anchors() in TfliteDetector.java: levels 3–7, 3 octaves × 3 aspects.
  Float32List anchors() {
    if (_anchors != null) return _anchors!;
    final boxes = <double>[];
    for (var level = anchorMinLevel; level <= anchorMaxLevel; level++) {
      final feature = (inputSize / math.pow(2, level)).ceil();
      if (feature <= 0) continue;
      final stride = inputSize / feature;
      for (var row = 0; row < feature; row++) {
        final centreY = (row + 0.5) * stride;
        for (var column = 0; column < feature; column++) {
          final centreX = (column + 0.5) * stride;
          for (var octave = 0; octave < anchorScalesPerOctave; octave++) {
            final base =
                _anchorScale * stride * math.pow(2, octave / anchorScalesPerOctave).toDouble();
            for (final aspect in anchorAspectRatios) {
              final aspectX = math.sqrt(aspect);
              final aspectY = 1.0 / aspectX;
              final halfW = base * aspectX / 2.0;
              final halfH = base * aspectY / 2.0;
              boxes.addAll([
                centreY - halfH, centreX - halfW, centreY + halfH, centreX + halfW
              ]);
            }
          }
        }
      }
    }
    _anchors = Float32List.fromList(boxes);
    _numAnchors = boxes.length ~/ 4;
    return _anchors!;
  }

  /// Decode one anchor-relative prediction into an absolute y0,x0,y1,x1 box
  /// (input-tensor pixel space).
  static List<double> decodeAnchorBox(Float32List boxes, int o, Float32List anchors, int a) {
    final ay0 = anchors[a * 4], ax0 = anchors[a * 4 + 1];
    final ay1 = anchors[a * 4 + 2], ax1 = anchors[a * 4 + 3];
    final centreYa = (ay0 + ay1) / 2.0;
    final centreXa = (ax0 + ax1) / 2.0;
    final anchorH = ay1 - ay0;
    final anchorW = ax1 - ax0;

    final ty = boxes[o], tx = boxes[o + 1], th = boxes[o + 2], tw = boxes[o + 3];
    final height = math.exp(th) * anchorH;
    final width = math.exp(tw) * anchorW;
    final centreY = ty * anchorH + centreYa;
    final centreX = tx * anchorW + centreXa;
    return [centreY - height / 2, centreX - width / 2, centreY + height / 2, centreX + width / 2];
  }

  /// Raw-head run: input RGB uint8 [320,320,3] packed row-major.
  /// Returns detections with normalised [0,1] boxes.
  List<Detection> detect(Uint8List rgb320, {double iouThreshold = 0.45, int maxDetections = 20}) {
    final interp = _interpreter;
    if (interp == null) return [];
    final anchors = this.anchors();

    final outTensors = interp.getOutputTensors();
    late int boxesIdx, scoresIdx;
    var foundBoxes = false, foundScores = false;
    for (var i = 0; i < outTensors.length; i++) {
      final shape = outTensors[i].shape;
      if (shape.length != 3) continue;
      final last = shape[shape.length - 1];
      if (last == 4) { boxesIdx = i; foundBoxes = true; }
      else if (last > 4) { scoresIdx = i; foundScores = true; }
    }
    if (!foundBoxes || !foundScores) {
      debugPrint('TWP:model EfficientDet layout needs a [1,N,4] boxes tensor and a [1,N,C] scores tensor');
      return [];
    }

    final nRows = outTensors[boxesIdx].shape[1];
    final nClasses = outTensors[scoresIdx].shape[2];

    _outBoxesBytes ??= Uint8List(nRows * 4 * 4);
    _outScoresBytes ??= Uint8List(nRows * nClasses * 4);

    if (_input.length != rgb320.length) _input = Uint8List(rgb320.length);
    _input.setAll(0, rgb320);

    final sw = Stopwatch()..start();
    interp.runForMultipleInputs([_input], {
      boxesIdx: _outBoxesBytes!.buffer,
      scoresIdx: _outScoresBytes!.buffer,
    });
    final inferMs = sw.elapsedMilliseconds;

    final boxesF = Float32List.view(_outBoxesBytes!.buffer);
    final scoresF = Float32List.view(_outScoresBytes!.buffer);

    final rows = math.min(nRows, _numAnchors);
    final raw = <Detection>[];
    for (var i = 0; i < rows; i++) {
      var best = 0.0;
      var bestClass = -1;
      final base = i * nClasses;
      for (var c = 0; c < nClasses; c++) {
        if (scoresF[base + c] > best) { best = scoresF[base + c]; bestClass = c; }
      }
      if (bestClass < 0 || best < efficientdetFloor) continue;
      final box = decodeAnchorBox(boxesF, i * 4, anchors, i);
      if (box[2] <= box[0] || box[3] <= box[1]) continue;
      raw.add(Detection(labelFor(bestClass), best,
          (box[0] / inputSize).clamp(0.0, 1.0),
          (box[1] / inputSize).clamp(0.0, 1.0),
          (box[2] / inputSize).clamp(0.0, 1.0),
          (box[3] / inputSize).clamp(0.0, 1.0)));
    }
    final kept = nonMaxSuppression(raw, iouThreshold, maxDetections);
    debugPrint('TWP:infer ms=$inferMs anchors=$rows raw=${raw.length} kept=${kept.length} engine=efficientdet');
    return kept;
  }

  String labelFor(int index) {
    if (index >= 0 && index < _labels.length) return _labels[index];
    return 'object #$index';
  }

  static List<Detection> nonMaxSuppression(List<Detection> detections,
      double iouThreshold, int maxDetections) {
    final sorted = [...detections]..sort((a, b) => b.score.compareTo(a.score));
    final kept = <Detection>[];
    for (final candidate in sorted) {
      var overlaps = false;
      for (final chosen in kept) {
        if (chosen.label != candidate.label) continue;
        if (intersectionOverUnion(chosen, candidate) > iouThreshold) {
          overlaps = true;
          break;
        }
      }
      if (!overlaps) kept.add(candidate);
      if (kept.length >= maxDetections) break;
    }
    return kept;
  }

  static double intersectionOverUnion(Detection a, Detection b) {
    final x1 = math.max(a.xmin, b.xmin);
    final y1 = math.max(a.ymin, b.ymin);
    final x2 = math.min(a.xmax, b.xmax);
    final y2 = math.min(a.ymax, b.ymax);
    final intersection = math.max(0.0, x2 - x1) * math.max(0.0, y2 - y1);
    final areaA = math.max(0.0, a.xmax - a.xmin) * math.max(0.0, a.ymax - a.ymin);
    final areaB = math.max(0.0, b.xmax - b.xmin) * math.max(0.0, b.ymax - b.ymin);
    final union = areaA + areaB - intersection;
    return union <= 0 ? 0.0 : intersection / union;
  }

  void dispose() => _interpreter?.close();
}
