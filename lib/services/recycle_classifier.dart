/// COCO label → recycle-stream mapping for the primary YOLO detection stage.
///
/// The bundled detector speaks the standard 80-class COCO vocabulary
/// (`assets/models/coco_labels.txt`). This file is the single hard-coded table
/// that turns any of those 80 names into one of the three resident-facing
/// streams, and decides whether a detected box is waste evidence the scanner
/// should surface at all ([wasteRelevantFor]).
///
/// Deliberately exhaustive: [recycleLabels] and [reusableLabels] name the
/// useful classes, [trashLabels] names the food waste, and *everything else* —
/// people, animals, vehicles, and the furniture that has no reuse route — falls
/// through to [RecycleCategory.trash], so a detection is never left unmapped.
library;

import '../types.dart';

/// Washable container and cutlery material → the recycling stream.
const recycleLabels = <String>{
  'bottle',
  'wine glass',
  'cup',
  'bowl',
  'fork',
  'knife',
  'spoon',
};

/// Objects that still have a useful life → the Circular Hub (share, don't bin).
const reusableLabels = <String>{
  'book',
  'backpack',
  'handbag',
  'umbrella',
  'suitcase',
  'chair',
  'couch',
  'bed',
  'dining table',
  'tv',
  'laptop',
  'mouse',
  'keyboard',
  'remote',
  'cell phone',
  'microwave',
  'oven',
  'toaster',
  'refrigerator',
  'clock',
  'vase',
  'scissors',
  'hair drier',
  'toothbrush',
  'teddy bear',
  'sports ball',
  'surfboard',
  'skateboard',
  'frisbee',
  'kite',
};

/// Food and garden waste → organics / general waste.
///
/// Named explicitly for readability and for tests; every *other* COCO class
/// ends up at the same destination through the [categoriseCocoLabel] fallback.
const trashLabels = <String>{
  'banana',
  'apple',
  'sandwich',
  'orange',
  'broccoli',
  'carrot',
  'hot dog',
  'pizza',
  'donut',
  'cake',
};

/// Labels worth showing the resident as waste evidence.
///
/// A "bottle" box means something to the collection log; a "car" or a "dog"
/// box does not, so the pipeline keeps the detection but does not let it drive
/// the scan headline.
const wasteRelevantLabels = <String>{
  'bottle',
  'wine glass',
  'cup',
  'bowl',
  'fork',
  'knife',
  'spoon',
  'book',
  'banana',
  'apple',
  'sandwich',
  'orange',
  'broccoli',
  'carrot',
  'hot dog',
  'pizza',
  'donut',
  'cake',
  'potted plant',
  'vase',
  'scissors',
  'toothbrush',
  'teddy bear',
};

/// The full 80-class vocabulary the YOLO stage emits, in `coco_labels.txt`
/// order. Kept here so the mapping table can be checked for complete coverage
/// without loading assets.
const cocoLabels = <String>{
  'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train',
  'truck', 'boat', 'traffic light', 'fire hydrant', 'stop sign',
  'parking meter', 'bench', 'bird', 'cat', 'dog', 'horse', 'sheep', 'cow',
  'elephant', 'bear', 'zebra', 'giraffe', 'backpack', 'umbrella', 'handbag',
  'tie', 'suitcase', 'frisbee', 'skis', 'snowboard', 'sports ball', 'kite',
  'baseball bat', 'baseball glove', 'skateboard', 'surfboard',
  'tennis racket', 'bottle', 'wine glass', 'cup', 'fork', 'knife', 'spoon',
  'bowl', 'banana', 'apple', 'sandwich', 'orange', 'broccoli', 'carrot',
  'hot dog', 'pizza', 'donut', 'cake', 'chair', 'couch', 'potted plant',
  'bed', 'dining table', 'toilet', 'tv', 'laptop', 'mouse', 'remote',
  'keyboard', 'cell phone', 'microwave', 'oven', 'toaster', 'sink',
  'refrigerator', 'book', 'clock', 'vase', 'scissors', 'teddy bear',
  'hair drier', 'toothbrush',
};

/// Canonical form of a detector label: trimmed, lower-cased, with the
/// underscore spellings some exports use (`hot_dog`) folded to the COCO name.
String normaliseCocoLabel(String label) => label
    .trim()
    .toLowerCase()
    .replaceAll('_', ' ')
    .replaceAll(RegExp(r'\s+'), ' ');

/// Which of the three streams a detected label belongs to.
///
/// Anything outside [recycleLabels] and [reusableLabels] — including every
/// remaining COCO class (people, animals, vehicles) and any label the model
/// invents — is [RecycleCategory.trash].
RecycleCategory categoriseCocoLabel(String label) {
  final l = normaliseCocoLabel(label);
  if (recycleLabels.contains(l)) return RecycleCategory.recycle;
  if (reusableLabels.contains(l)) return RecycleCategory.reusable;
  return RecycleCategory.trash;
}

/// Whether a detected label is waste evidence at all (rather than background
/// scenery the detector happened to fire on).
bool wasteRelevantFor(String label) =>
    wasteRelevantLabels.contains(normaliseCocoLabel(label));
