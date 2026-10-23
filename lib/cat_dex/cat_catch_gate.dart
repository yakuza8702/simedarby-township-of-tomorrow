/// The one cat-catch gate, shared by the scan card and the log-a-sighting flow.
///
/// Copied out of `lib/screens/scan_screen.dart` (which keeps its public static
/// methods as thin delegates so its call sites and tests stay valid) so there
/// is exactly one definition of "this photo may offer a cat catch":
///
/// * the strongest box labelled [catLabel] is [catBox];
/// * [catchableCatBox] additionally requires detector-level confidence and no
///   competing animal scoring higher (a dog photo is not a cat photo);
/// * [scaleToOriginal] maps the pipeline's 640-px working-copy boxes back to
///   full-resolution capture pixels.
///
/// Offline, pure, no plugins — both flows call it on-device.
library;

import '../services/scan_quips.dart';
import '../types.dart';

/// Detector-box arithmetic for the Cat Distribution System catch.
class CatCatchGate {
  CatCatchGate._();

  /// The detector label that makes a box a cat (COCO-80 `cat`).
  static const String catLabel = 'cat';

  /// The animals that compete with a cat for the sighting — the COCO-80 animal
  /// set the scan result copy already names (`ScanQuips.animalLabels`).
  static const Set<String> competingAnimalLabels = ScanQuips.animalLabels;

  /// Score floor a cat box must clear to offer the catch: the detector's own
  /// default floor (`YoloDetector.defaultConfidenceThreshold` = 0.25), *not*
  /// the 0.05 relaxed-retry floor, which is what lets a spurious 0.08 `cat` box
  /// survive into `ScanResult.objects` at all.
  static const double minCatConfidence = 0.25;

  /// The highest-confidence box labelled [catLabel], or null when the scan
  /// found no cat.
  ///
  /// Confidence, not list order: `ScanResult.objects` is sorted waste-evidence
  /// first, so a cat can sit anywhere in the list.
  static DetectedObject? catBox(List<DetectedObject> objects) {
    DetectedObject? best;
    for (final o in objects) {
      if (o.label.trim().toLowerCase() != catLabel) continue;
      if (best == null || o.confidence > best.confidence) best = o;
    }
    return best;
  }

  /// The cat box that may offer the dex catch — [catBox] restricted to a
  /// *confident* cat that no other animal outranks.
  ///
  /// * below [minCatConfidence] → null (nothing confident enough was seen);
  /// * another animal scoring *higher* than the best cat → null (dog 0.95 vs
  ///   cat 0.26 is a dog photo). A tie keeps the cat: equal confidence is not
  ///   evidence against the cat.
  ///
  /// Only detector boxes reach this list — `ScanResult.objects` is built from
  /// YOLO alone (`VisionPipeline._toObjects`), so an ML Kit image label can
  /// never open the card.
  static DetectedObject? catchableCatBox(List<DetectedObject> objects) {
    final best = catBox(objects);
    if (best == null || best.confidence < minCatConfidence) return null;
    for (final o in objects) {
      final label = o.label.trim().toLowerCase();
      if (label == catLabel || !competingAnimalLabels.contains(label)) {
        continue;
      }
      if (o.confidence > best.confidence) return null;
    }
    return best;
  }

  /// Detector boxes are pixels in the pipeline's 640-px working copy, while the
  /// photo the catch re-reads is the full-resolution capture — so the box is
  /// scaled back up whenever the capture is the longer of the two. Captures at
  /// or below 640 px are never resized by the pipeline, so their boxes pass
  /// through unchanged.
  static double scaleToOriginal(int imageWidth, int imageHeight) {
    const scanSide = 640;
    final longest = imageWidth > imageHeight ? imageWidth : imageHeight;
    return longest <= scanSide ? 1.0 : longest / scanSide;
  }
}
