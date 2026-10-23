/// Shared types for the Township of Tomorrow scanner.
library;

enum WasteCategory { Recyclable, Organic, Reusable, Ewaste, Hazardous, Landfill }

/// `E-waste`/`Ewaste` naming helper — keep the historical display string.
extension WasteCategoryX on WasteCategory {
  String get display => switch (this) {
        WasteCategory.Ewaste => 'E-waste',
        _ => name,
      };
}

/// The three resident-facing streams the detection stage sorts items into.
///
/// Distinct from [WasteCategory] on purpose: the six-stream decision is the
/// scanner's final verdict, while this is the coarse destination a detected
/// object gets from the label table before ML Kit and the kNN vote.
enum RecycleCategory { recycle, reusable, trash }

/// One detector box after it has been mapped to a [RecycleCategory].
///
/// `x1, y1, x2, y2` are the detector's own box coordinates, copied through
/// unchanged (top-left → bottom-right): pixels in the image the detector was
/// handed — for this pipeline the 640-px longest-side working copy, not the
/// full-resolution capture. Normalised `0..1` boxes for the stream classifier
/// are derived separately, in `ScanResult.detections`.
class DetectedObject {
  final String label;
  final double confidence;
  final RecycleCategory category;
  final bool wasteRelevant;
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  const DetectedObject({
    required this.label,
    required this.confidence,
    required this.category,
    required this.wasteRelevant,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  /// Positional counterpart of the named constructor, in detector field order:
  /// `(label, confidence, category, wasteRelevant, x1, y1, x2, y2)`.
  const DetectedObject.at(
    this.label,
    this.confidence,
    this.category,
    this.wasteRelevant,
    this.x1,
    this.y1,
    this.x2,
    this.y2,
  );

  double get width => (x2 - x1).abs();
  double get height => (y2 - y1).abs();
  double get area => width * height;

  Map<String, dynamic> toJson() => {
        'label': label,
        'confidence': confidence,
        'category': category.name,
        'wasteRelevant': wasteRelevant,
        'x1': x1,
        'y1': y1,
        'x2': x2,
        'y2': y2,
      };
}

class Detection {
  final String label;
  final double score;
  /// Normalised box: y0, x0, y1, x1 in [0,1] of the source image.
  final double ymin, xmin, ymax, xmax;
  const Detection(this.label, this.score, this.ymin, this.xmin, this.ymax, this.xmax);
}

class VisionLabel {
  final String text;
  final double confidence; // 0..1
  const VisionLabel(this.text, this.confidence);
}

class StreamGuidance {
  final WasteCategory category;
  final String bin;
  final String action;
  final String impact;
  const StreamGuidance(this.category, this.bin, this.action, this.impact);
}

/// One item the resident has committed to handle (the Collection tab).
class CollectionEntry {
  final String id;
  final String itemLabel; // what the scanner called it
  final WasteCategory category;
  final int confidence; // 0..100
  final String photoPath;
  final String photoHash; // pHash hex — anchor for the anti-exploit proof
  final String status; // 'collected' | 'done'
  final String action; // '' | recycle | remove | dispose
  final int pointsAwarded;
  final DateTime addedAt;
  final DateTime? doneAt;
  final String verifyReason;

  CollectionEntry({
    required this.id,
    required this.itemLabel,
    required this.category,
    required this.confidence,
    required this.photoPath,
    required this.photoHash,
    required this.status,
    this.action = '',
    this.pointsAwarded = 0,
    required this.addedAt,
    this.doneAt,
    this.verifyReason = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'itemLabel': itemLabel,
        'category': category.name,
        'confidence': confidence,
        'photoPath': photoPath,
        'photoHash': photoHash,
        'status': status,
        'action': action,
        'pointsAwarded': pointsAwarded,
        'addedAt': addedAt.toIso8601String(),
        'doneAt': doneAt?.toIso8601String(),
        'verifyReason': verifyReason,
      };

  static CollectionEntry fromJson(Map<String, dynamic> j) => CollectionEntry(
        id: j['id'] as String,
        itemLabel: j['itemLabel'] as String,
        category: WasteCategory.values.byName(j['category'] as String),
        confidence: (j['confidence'] as num).toInt(),
        photoPath: j['photoPath'] as String,
        photoHash: (j['photoHash'] ?? '') as String,
        status: (j['status'] ?? 'collected') as String,
        action: (j['action'] ?? '') as String,
        pointsAwarded: (j['pointsAwarded'] ?? 0) as int,
        addedAt: DateTime.parse(j['addedAt'] as String),
        doneAt: j['doneAt'] == null ? null : DateTime.parse(j['doneAt'] as String),
        verifyReason: (j['verifyReason'] ?? '') as String,
      );
}
