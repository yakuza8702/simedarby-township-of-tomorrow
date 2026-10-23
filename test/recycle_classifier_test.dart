/// Unit tests for the COCO label → recycle-stream table in
/// `lib/services/recycle_classifier.dart`.
///
/// The table is the contract three other things depend on, so it is pinned
/// here explicitly:
///
/// * `tool/fetch_test_images.sh` picks COCO val2017 images whose *dominant*
///   annotated class is a recycle / trash / reusable label, and records the
///   expectation it derived from the ground truth;
/// * `tool/detection_bench.dart` scores the on-device YOLO stage against those
///   expectations via [categoriseCocoLabel];
/// * `integration_test/on_device_detection_test.dart` runs that bench on an
///   emulator.
///
/// That is why the label sets asserted below (bottle/cup/wine glass/bowl →
/// recycle, banana/apple/pizza/cake/donut → trash, book/laptop/cell phone/
/// chair/backpack/tv → reusable) are exactly the ones the fetch script looks
/// for: if the mapping moves, the bench expectations move with it.
///
/// Run: `flutter test test/recycle_classifier_test.dart`
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:township_of_tomorrow/services/recycle_classifier.dart';
import 'package:township_of_tomorrow/types.dart';

/// Representative labels used by the bench, keyed to the stream the table must
/// return. Deliberately wider than 25 entries and covering all three streams.
const representativeLabels = <String, RecycleCategory>{
  // ── recycle: washable containers and cutlery ───────────────────────────
  'bottle': RecycleCategory.recycle,
  'wine glass': RecycleCategory.recycle,
  'cup': RecycleCategory.recycle,
  'bowl': RecycleCategory.recycle,
  'fork': RecycleCategory.recycle,
  'knife': RecycleCategory.recycle,
  'spoon': RecycleCategory.recycle,

  // ── reusable: still has a useful life, Circular Hub ────────────────────
  'book': RecycleCategory.reusable,
  'backpack': RecycleCategory.reusable,
  'handbag': RecycleCategory.reusable,
  'umbrella': RecycleCategory.reusable,
  'suitcase': RecycleCategory.reusable,
  'chair': RecycleCategory.reusable,
  'couch': RecycleCategory.reusable,
  'bed': RecycleCategory.reusable,
  'dining table': RecycleCategory.reusable,
  'tv': RecycleCategory.reusable,
  'laptop': RecycleCategory.reusable,
  'mouse': RecycleCategory.reusable,
  'keyboard': RecycleCategory.reusable,
  'remote': RecycleCategory.reusable,
  'cell phone': RecycleCategory.reusable,
  'microwave': RecycleCategory.reusable,
  'oven': RecycleCategory.reusable,
  'toaster': RecycleCategory.reusable,
  'refrigerator': RecycleCategory.reusable,
  'clock': RecycleCategory.reusable,
  'vase': RecycleCategory.reusable,
  'scissors': RecycleCategory.reusable,
  'hair drier': RecycleCategory.reusable,
  'toothbrush': RecycleCategory.reusable,
  'teddy bear': RecycleCategory.reusable,
  'sports ball': RecycleCategory.reusable,
  'surfboard': RecycleCategory.reusable,
  'skateboard': RecycleCategory.reusable,
  'frisbee': RecycleCategory.reusable,
  'kite': RecycleCategory.reusable,

  // ── trash: food and garden waste ───────────────────────────────────────
  'banana': RecycleCategory.trash,
  'apple': RecycleCategory.trash,
  'sandwich': RecycleCategory.trash,
  'orange': RecycleCategory.trash,
  'broccoli': RecycleCategory.trash,
  'carrot': RecycleCategory.trash,
  'hot dog': RecycleCategory.trash,
  'pizza': RecycleCategory.trash,
  'donut': RecycleCategory.trash,
  'cake': RecycleCategory.trash,

  // ── trash by fallback: neither useful nor washable ─────────────────────
  'person': RecycleCategory.trash,
  'car': RecycleCategory.trash,
  'dog': RecycleCategory.trash,
  'cat': RecycleCategory.trash,
  'bench': RecycleCategory.trash,
  'toilet': RecycleCategory.trash,
  'sink': RecycleCategory.trash,
  'potted plant': RecycleCategory.trash,
};

/// Labels the fetch script hunts for, per expected stream — at least five
/// images of each on disk.
const fetchScriptRecyclePicks = <String>['bottle', 'cup', 'wine glass', 'bowl'];
const fetchScriptTrashPicks = <String>['banana', 'apple', 'pizza', 'cake', 'donut'];
const fetchScriptReusablePicks = <String>[
  'book',
  'laptop',
  'cell phone',
  'chair',
  'backpack',
  'tv',
];

/// COCO classes with no entry in the table at all — people, animals, vehicles,
/// street furniture, plumbing — plus the potted plant, which is trash by
/// fallback while still being genuine garden waste. All of them must land on
/// the trash stream via [categoriseCocoLabel]'s fallback.
const fallbackTrashLabels = <String>[
  'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train',
  'truck', 'boat', 'traffic light', 'fire hydrant', 'stop sign',
  'parking meter', 'bench', 'bird', 'cat', 'dog', 'horse', 'sheep', 'cow',
  'elephant', 'bear', 'zebra', 'giraffe', 'tie', 'skis', 'snowboard',
  'baseball bat', 'baseball glove', 'tennis racket', 'toilet', 'sink',
  'potted plant',
];

/// Classes that must never drive the scan headline: everything in
/// [fallbackTrashLabels] except the potted plant, plus the furniture and
/// electronics that sort to the Circular Hub instead of to trash.
const sceneryLabels = <String>[
  'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train',
  'truck', 'boat', 'traffic light', 'fire hydrant', 'stop sign',
  'parking meter', 'bench', 'bird', 'cat', 'dog', 'horse', 'sheep', 'cow',
  'elephant', 'bear', 'zebra', 'giraffe', 'tie', 'skis', 'snowboard',
  'baseball bat', 'baseball glove', 'tennis racket', 'toilet', 'sink',
  'chair', 'couch', 'bed', 'dining table', 'tv', 'laptop', 'mouse',
  'keyboard', 'cell phone', 'microwave', 'oven', 'toaster', 'refrigerator',
  'clock', 'backpack', 'umbrella', 'handbag', 'suitcase',
];

void main() {
  group('categoriseCocoLabel — the three streams', () {
    test('recycle: containers and cutlery', () {
      for (final label in const [
        'bottle',
        'wine glass',
        'cup',
        'bowl',
        'fork',
        'knife',
        'spoon',
      ]) {
        expect(categoriseCocoLabel(label), RecycleCategory.recycle,
            reason: '$label should sort to the recycling stream');
      }
    });

    test('reusable: things with a useful life left', () {
      for (final label in const [
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
      ]) {
        expect(categoriseCocoLabel(label), RecycleCategory.reusable,
            reason: '$label should sort to the Circular Hub stream');
      }
    });

    test('trash: food and garden waste', () {
      for (final label in const [
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
      ]) {
        expect(categoriseCocoLabel(label), RecycleCategory.trash,
            reason: '$label should sort to the trash stream');
      }
    });

    test('the bench picks map exactly as the fetch script assumes', () {
      for (final label in fetchScriptRecyclePicks) {
        expect(categoriseCocoLabel(label), RecycleCategory.recycle,
            reason: '$label is a fetch-script recycle pick');
      }
      for (final label in fetchScriptTrashPicks) {
        expect(categoriseCocoLabel(label), RecycleCategory.trash,
            reason: '$label is a fetch-script trash pick');
      }
      for (final label in fetchScriptReusablePicks) {
        expect(categoriseCocoLabel(label), RecycleCategory.reusable,
            reason: '$label is a fetch-script reusable pick');
      }
    });
  });

  group('categoriseCocoLabel — fallback', () {
    test('every other COCO class (people, animals, vehicles) falls to trash',
        () {
      for (final label in fallbackTrashLabels) {
        expect(categoriseCocoLabel(label), RecycleCategory.trash,
            reason: '$label is not waste material — expected the trash fallback');
      }
    });

    test('invented / out-of-vocabulary labels fall to trash, never to recycle',
        () {
      for (final label in const [
        'waste',
        'recyclable',
        'plastic',
        'unidentified widget',
        'bottle cap',
        'soda can',
        'Waste_Bin',
        '0',
        '???',
        '',
        '   ',
        '\t\n',
        '🚮',
      ]) {
        final actual = categoriseCocoLabel(label);
        expect(actual, RecycleCategory.trash,
            reason: 'unknown label "$label" must fall back to trash');
        expect(actual, isNot(RecycleCategory.recycle));
        expect(actual, isNot(RecycleCategory.reusable));
      }
    });

    test('spellings must match the COCO vocabulary (no fuzzy matching)', () {
      // The contract is exact after normalisation; near-misses are trash, and
      // that is worth pinning so a "helpful" substring match is never added by
      // accident — a false recycle is a wrong bin for the resident.
      expect(categoriseCocoLabel('wine glass'), RecycleCategory.recycle);
      expect(categoriseCocoLabel('wineglass'), RecycleCategory.trash);
      expect(categoriseCocoLabel('cell phone'), RecycleCategory.reusable);
      expect(categoriseCocoLabel('cellphone'), RecycleCategory.trash);
      expect(categoriseCocoLabel('soft drink bottle'), RecycleCategory.trash);
    });

    test('normalisation: case, padding and underscore spellings', () {
      expect(categoriseCocoLabel('BOTTLE'), RecycleCategory.recycle);
      expect(categoriseCocoLabel('  Bottle  '), RecycleCategory.recycle);
      expect(categoriseCocoLabel('wine_glass'), RecycleCategory.recycle);
      expect(categoriseCocoLabel('WINE_GLASS'), RecycleCategory.recycle);
      expect(categoriseCocoLabel('hot_dog'), RecycleCategory.trash);
      expect(categoriseCocoLabel('Hot Dog'), RecycleCategory.trash);
      expect(categoriseCocoLabel('Cell  Phone'), RecycleCategory.reusable);
      expect(categoriseCocoLabel('\tcell_phone\n'), RecycleCategory.reusable);
      expect(normaliseCocoLabel('  Hot_Dog  '), 'hot dog');
    });
  });

  group('wasteRelevantFor', () {
    test('true for material worth showing the resident', () {
      for (final label in const [
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
      ]) {
        expect(wasteRelevantFor(label), isTrue, reason: '$label is waste evidence');
      }
    });

    test('false for background scenery the detector happened to fire on', () {
      for (final label in sceneryLabels) {
        expect(wasteRelevantFor(label), isFalse,
            reason: '$label must not drive the scan headline');
      }
      for (final label in const ['', '   ', 'unidentified widget', 'bottle cap']) {
        expect(wasteRelevantFor(label), isFalse,
            reason: 'unknown label "$label" is not waste evidence');
      }
    });

    test('normalisation applies to the flag too', () {
      expect(wasteRelevantFor('  BOTTLE '), isTrue);
      expect(wasteRelevantFor('TEDDY_BEAR'), isTrue);
      expect(wasteRelevantFor('PIZZA'), isTrue);
      expect(wasteRelevantFor(' Chair '), isFalse);
    });

    test('category and relevance are independent axes', () {
      // Reusable but not waste evidence: a laptop is scenery to the scanner.
      expect(categoriseCocoLabel('laptop'), RecycleCategory.reusable);
      expect(wasteRelevantFor('laptop'), isFalse);

      // Trash by fallback but still waste evidence: a leftover house plant.
      expect(categoriseCocoLabel('potted plant'), RecycleCategory.trash);
      expect(wasteRelevantFor('potted plant'), isTrue);

      // Trash and not waste evidence: the neighbour's cat.
      expect(categoriseCocoLabel('cat'), RecycleCategory.trash);
      expect(wasteRelevantFor('cat'), isFalse);
    });
  });

  group('table hygiene', () {
    test('every waste-relevant label is a known COCO class', () {
      for (final label in wasteRelevantLabels) {
        expect(cocoLabels, contains(label),
            reason: '"$label" is flagged waste-relevant but is not a COCO class');
      }
    });

    test('every explicitly mapped label is a known COCO class', () {
      for (final label in <String>[
        ...recycleLabels,
        ...reusableLabels,
        ...trashLabels,
        ...wasteRelevantLabels,
      ]) {
        expect(cocoLabels, contains(label),
            reason: '"$label" is mapped but never emitted by the detector');
      }
      expect(cocoLabels.length, 80);
    });

    test('the streams are disjoint', () {
      expect(recycleLabels.intersection(reusableLabels), isEmpty);
      expect(recycleLabels.intersection(trashLabels), isEmpty);
      expect(reusableLabels.intersection(trashLabels), isEmpty);
    });

    test('all 80 COCO classes categorise, and the counts add up', () {
      final counts = <RecycleCategory, int>{
        for (final category in RecycleCategory.values) category: 0,
      };
      for (final label in cocoLabels) {
        counts[categoriseCocoLabel(label)] =
            counts[categoriseCocoLabel(label)]! + 1;
      }
      expect(counts[RecycleCategory.recycle], recycleLabels.length);
      expect(counts[RecycleCategory.reusable], reusableLabels.length);
      expect(
        counts[RecycleCategory.trash],
        cocoLabels.length - recycleLabels.length - reusableLabels.length,
      );
      expect(
        counts.values.reduce((a, b) => a + b),
        cocoLabels.length,
        reason: 'no COCO class may be left unmapped',
      );
    });
  });

  group('representative coverage (the bench table)', () {
    test('at least 25 labels, with at least 5 in each stream', () {
      expect(representativeLabels.length, greaterThanOrEqualTo(25));
      for (final category in RecycleCategory.values) {
        final inCategory =
            representativeLabels.values.where((value) => value == category);
        expect(inCategory.length, greaterThanOrEqualTo(5),
            reason: 'the $category stream needs representative labels');
      }
    });

    test('every representative label maps to its expected stream', () {
      representativeLabels.forEach((label, expected) {
        expect(categoriseCocoLabel(label), expected,
            reason: 'representative label "$label"');
      });
    });

    test('fallback-trash representatives are not waste evidence', () {
      for (final label in representativeLabels.keys) {
        if (!sceneryLabels.contains(label)) continue;
        expect(wasteRelevantFor(label), isFalse,
            reason: '"$label" is scenery, not waste evidence');
      }
    });
  });
}
