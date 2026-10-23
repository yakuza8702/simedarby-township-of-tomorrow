/// Bridge between the vision pipeline's real result type and the language
/// layer's query type.
///
/// `ScanResult` knows what was detected; `ScanQuery` knows what the guidance
/// engine needs. This file is the only place that maps one onto the other, so
/// the field names live in exactly one spot and a pipeline change breaks here
/// (loudly, at compile time) instead of silently degrading the guidance.
///
/// Every field below is read from the real types in `lib/types.dart` and
/// `lib/services/vision_pipeline.dart` — nothing is invented:
///
/// * `ScanResult.objects` → `DetectedObject.label` / `.confidence` (YOLO boxes,
///   already ordered waste-evidence-first then by confidence);
/// * `ScanResult.outcome` → `ClassificationOutcome.confidence` (0..100),
///   `.knnItem`, `.matchedFrom`, `.category`;
/// * `ScanResult.knn` → `KnnResult.label` / `.cosine`;
/// * `ScanResult.mlkitLabels` → `VisionLabel.text` / `.confidence`;
/// * `outcome.category` → `GUIDANCE[...]` → `StreamGuidance`.
///
/// One field has no source: **OCR text**. `ScanResult` carries no OCR field —
/// text recognition is a separate service (`lib/services/text_recognition.dart`)
/// that the pipeline does not thread into the result — so `ocrText` is an
/// explicit optional input ([fromScanResult]'s `ocrText`) and is null when the
/// caller has none.
library;

import '../types.dart';
import 'local_llm.dart';
import 'vision_pipeline.dart';
import 'waste_classifier.dart';

class ScanAdvisor {
  ScanAdvisor._();

  /// Map a finished scan into the query the guidance engine consumes.
  ///
  /// [userQuestion] is '' for the first pass and the tapped follow-up question
  /// afterwards; [ocrText] is only non-null when the caller has OCR output,
  /// because the pipeline's result does not carry it.
  static ScanQuery fromScanResult(
    ScanResult result, {
    String userQuestion = '',
    String? ocrText,
  }) {
    final (label, confidence) = _evidence(result);
    final category = result.outcome.category;
    return ScanQuery(
      label: label,
      confidence: confidence.clamp(0.0, 1.0),
      ocrText: ocrText,
      knnLabel: result.knn?.label,
      knnScore: result.knn?.cosine,
      guidance: category == null ? null : GUIDANCE[category],
      userQuestion: userQuestion,
    );
  }

  /// The same scan, asked a follow-up question — what a suggestion chip
  /// re-queries with, so the evidence is not re-derived.
  static ScanQuery withQuestion(ScanQuery base, String question) => ScanQuery(
        label: base.label,
        confidence: base.confidence,
        ocrText: base.ocrText,
        knnLabel: base.knnLabel,
        knnScore: base.knnScore,
        guidance: base.guidance,
        userQuestion: question,
      );

  /// Best available (label, confidence) pair, in evidence order: a waste-relevant
  /// box first, then the kNN identity with its cosine, then the strongest ML Kit
  /// label, and finally whatever the stream decision matched on.
  static (String, double) _evidence(ScanResult result) {
    final object = _primaryObject(result.objects);
    if (object != null) {
      return (object.label, object.confidence);
    }
    final knn = result.knn;
    if (knn != null && knn.label.isNotEmpty) {
      return (knn.label, knn.cosine);
    }
    final vision = _strongest(result.mlkitLabels);
    if (vision != null) {
      return (vision.text, vision.confidence);
    }
    return (result.outcome.matchedFrom ?? '', result.outcome.confidence / 100);
  }

  /// The box the resident actually cares about: the pipeline sorts waste
  /// evidence first and strongest first, so this is the head of the list.
  static DetectedObject? _primaryObject(List<DetectedObject> objects) {
    for (final object in objects) {
      if (object.wasteRelevant && object.label.isNotEmpty) return object;
    }
    for (final object in objects) {
      if (object.label.isNotEmpty) return object;
    }
    return null;
  }

  static VisionLabel? _strongest(List<VisionLabel> labels) {
    VisionLabel? best;
    for (final label in labels) {
      if (label.text.isEmpty) continue;
      if (best == null || label.confidence > best.confidence) best = label;
    }
    return best;
  }
}
