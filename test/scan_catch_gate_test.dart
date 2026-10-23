/// Gate tests for the Cat Distribution card: what the scan screen's mount site
/// asks before it offers a Cat Dex catch.
///
/// Pinned here (`CatDistributionCard.catchableCatBox`):
/// * a cat box below the detector's own 0.25 floor opens nothing — the relaxed
///   0.05 retry pass must not be able to conjure a catch out of noise;
/// * a competing COCO animal scoring *higher* than the best cat box suppresses
///   the card (dog 0.95 + cat 0.26 is a dog photo), a tie keeps it;
/// * a non-COCO label (`squirrel`, `kitten`) is never a cat and never a
///   competitor — the label filter, not the score, decides;
/// * the copy the card-level scan result renders carries no Cat-Distribution
///   line for a non-cat animal.
///
/// `test/scan_catch_test.dart` pins the card's own widget/handler contract and
/// `catBox`; this file pins the gate layered on top of it and is deliberately
/// separate so neither file's contract can drift unnoticed.
///
/// Run: `flutter test test/scan_catch_gate_test.dart`
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:township_of_tomorrow/screens/scan_screen.dart';
import 'package:township_of_tomorrow/services/scan_quips.dart';
import 'package:township_of_tomorrow/types.dart';

/// Detector box, in the pipeline's working-copy pixel space.
DetectedObject _box(String label, double confidence) => DetectedObject.at(
    label, confidence, RecycleCategory.trash, false, 8, 6, 34, 30);

/// Every animal label that competes with the cat for a sighting.
final _competitors = [
  for (final label in ScanQuips.animalLabels)
    if (label != CatDistributionCard.catLabel) label,
];

void main() {
  group('cat confidence floor', () {
    test('a confident cat box offers the catch', () {
      for (final confidence in [0.95, 0.66, 0.5, 0.25]) {
        final cat = _box('cat', confidence);
        expect(CatDistributionCard.catchableCatBox([cat]), same(cat),
            reason: 'cat at $confidence must open the card');
      }
    });

    test('a cat box under the detector floor offers nothing', () {
      // 0.08 is exactly what the relaxed 0.05 retry pass lets through.
      for (final confidence in [0.24, 0.08, 0.05, 0.0]) {
        expect(CatDistributionCard.catchableCatBox([_box('cat', confidence)]),
            isNull,
            reason: 'cat at $confidence must not open the card');
      }
    });

    test('the floor is the YOLO default, not the relaxed retry floor', () {
      expect(CatDistributionCard.minCatConfidence, 0.25);
    });
  });

  group('competing animals', () {
    test('a stronger dog suppresses the cat', () {
      expect(
          CatDistributionCard.catchableCatBox(
              [_box('dog', 0.95), _box('cat', 0.26)]),
          isNull);
    });

    test('a stronger bird suppresses the cat', () {
      expect(
          CatDistributionCard.catchableCatBox(
              [_box('bird', 0.4), _box('cat', 0.26)]),
          isNull);
    });

    test('every animal competitor outranking the cat suppresses it', () {
      for (final animal in _competitors) {
        expect(
            CatDistributionCard.catchableCatBox(
                [_box('cat', 0.26), _box(animal, 0.30)]),
            isNull,
            reason: '$animal 0.30 must beat cat 0.26');
      }
    });

    test('a weaker animal does not suppress the cat', () {
      expect(
          CatDistributionCard.catchableCatBox(
              [_box('cat', 0.9), _box('dog', 0.2)]),
          isNotNull);
    });

    test('an equal-confidence animal keeps the card', () {
      expect(
          CatDistributionCard.catchableCatBox(
              [_box('cat', 0.5), _box('dog', 0.5)]),
          isNotNull);
      expect(
          CatDistributionCard.catchableCatBox(
              [_box('cat', 0.25), _box('bird', 0.25)]),
          isNotNull);
    });

    test('the strongest cat is the one compared', () {
      // The 0.12 box must not drag the comparison down below the dog.
      final boxes = [_box('cat', 0.12), _box('cat', 0.80), _box('dog', 0.75)];
      final gate = CatDistributionCard.catchableCatBox(boxes);
      expect(gate, isNotNull);
      expect(gate!.confidence, 0.80);

      // …and the same dog beats a cat whose *best* box is weaker.
      expect(CatDistributionCard.catchableCatBox([_box('cat', 0.74), _box('dog', 0.75)]),
          isNull);
    });

    test('case and padding do not hide a competitor', () {
      expect(
          CatDistributionCard.catchableCatBox(
              [_box('Dog', 0.95), _box(' CAT ', 0.26)]),
          isNull);
      expect(CatDistributionCard.catchableCatBox([_box(' CAT ', 0.9)]),
          isNotNull);
    });

    test('non-animal boxes never suppress the cat', () {
      expect(
          CatDistributionCard.catchableCatBox(
              [_box('bottle', 0.99), _box('chair', 0.9), _box('cat', 0.9)]),
          isNotNull);
    });
  });

  group('label filter', () {
    test('squirrel is not a COCO label and never opens the card', () {
      expect(ScanQuips.animalLabels.contains('squirrel'), isFalse);
      expect(CatDistributionCard.catchableCatBox([_box('squirrel', 0.99)]),
          isNull);
      // It is not a cat *and* not a competitor, so it cannot outrank one either.
      expect(
          CatDistributionCard.catchableCatBox(
              [_box('squirrel', 0.99), _box('cat', 0.9)]),
          isNotNull);
    });

    test('a near-miss name is still not a cat', () {
      for (final label in ['kitten', 'cats', 'cat_', 'wildcat']) {
        expect(CatDistributionCard.catchableCatBox([_box(label, 0.99)]), isNull,
            reason: '$label is not the detector label');
      }
    });

    test('the competitor set is the shared COCO animal set', () {
      expect(CatDistributionCard.animalLabels, ScanQuips.animalLabels);
      expect(
          CatDistributionCard.animalLabels,
          containsAll([
            'cat', 'dog', 'bird', 'horse', 'sheep', //
            'cow', 'elephant', 'bear', 'zebra', 'giraffe',
          ]));
      expect(CatDistributionCard.catLabel, 'cat');
    });
  });

  group('gate vs catBox', () {
    test('catBox still reports boxes the gate rejects', () {
      // The pinned `catBox` stays a pure label lookup…
      expect(CatDistributionCard.catBox([_box('cat', 0.08)]), isNotNull);
      expect(
          CatDistributionCard.catBox([_box('dog', 0.95), _box('cat', 0.26)]),
          isNotNull);
      // …and the mount-site gate is what refuses them.
      expect(CatDistributionCard.catchableCatBox([_box('cat', 0.08)]), isNull);
      expect(
          CatDistributionCard.catchableCatBox(
              [_box('dog', 0.95), _box('cat', 0.26)]),
          isNull);
    });

    test('no boxes at all means no catch', () {
      expect(CatDistributionCard.catchableCatBox(const []), isNull);
    });
  });

  group('result copy', () {
    test('a non-cat animal carries no Cat-Distribution line', () {
      for (final animal in _competitors) {
        final quip = ScanQuips.forResult(
          topLabel: animal,
          category: 'trash',
          isWasteRelevant: false,
          catDistributionCopy: false,
        );
        expect(quip.quip, isNot(contains('Cat Distribution System')),
            reason: '$animal must not borrow the cat copy');
        expect(quip.quip, contains('not recyclable, but pettable!'));
      }
    });

    test('the cat keeps its copy either way', () {
      const expected =
          'A cat has appeared! The Cat Distribution System has assigned you a cat.';
      expect(
          ScanQuips.forResult(
            topLabel: 'cat',
            category: 'trash',
            isWasteRelevant: false,
            catDistributionCopy: false,
          ).quip,
          expected);
    });
  });
}
