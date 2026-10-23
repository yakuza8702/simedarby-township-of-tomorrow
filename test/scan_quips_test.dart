/// Unit tests for [ScanQuips] — the result card's title + quip copy.
///
/// Pinned here: all five rule branches (recyclable / trash / reusable / animal /
/// not-waste), the cat special case, the precedence between the branches, title
/// humanization (`cell phone` → `Cell phone`) and the empty-label fallback. The
/// card is the first thing a resident reads after a scan, so a label table
/// change must break this file loudly rather than quietly mis-instruct someone.
///
/// Run: `flutter test test/scan_quips_test.dart`
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:township_of_tomorrow/services/scan_quips.dart';

/// Short call form for the record the result card renders.
({String title, String quip}) _quips(
  String label,
  String category,
  bool wasteRelevant,
) =>
    ScanQuips.forResult(
      topLabel: label,
      category: category,
      isWasteRelevant: wasteRelevant,
    );

void main() {
  group('title humanization', () {
    test('spaces and underscores both fold to a sentence-cased title', () {
      expect(_quips('cell phone', 'recycle', true).title, 'Cell phone');
      expect(_quips('cell_phone', 'recycle', true).title, 'Cell phone');
      expect(_quips('  CELL   PHONE ', 'recycle', true).title, 'Cell phone');
      expect(_quips('hot_dog', 'trash', true).title, 'Hot dog');
      expect(_quips('cat', 'trash', false).title, 'Cat');
    });

    test('a label with no name falls back to the nothing-detected title', () {
      expect(_quips('', '', false).title, ScanQuips.nothingDetected);
      expect(_quips('   ', '', false).title, ScanQuips.nothingDetected);
      expect(_quips('___', '', false).title, ScanQuips.nothingDetected);
      expect(ScanQuips.nothingDetected, 'Nothing detected');
    });
  });

  group('stream rules (waste evidence)', () {
    test('recyclable', () {
      final r = _quips('bottle', 'recycle', true);
      expect(r.title, 'Bottle');
      expect(r.quip, 'Bottle — recyclable! Blue bin awaits.');
    });

    test('trash', () {
      final r = _quips('plastic bag', 'trash', true);
      expect(r.title, 'Plastic bag');
      expect(r.quip, 'Plastic bag — not recyclable. Bin it.');
    });

    test('reusable', () {
      final r = _quips('teddy bear', 'reusable', true);
      expect(r.title, 'Teddy bear');
      expect(
        r.quip,
        'Teddy bear — not trash, still useful! '
        'Share it on the Circular Hub.',
      );
    });

    test('both enums\' spellings reach the same rule', () {
      expect(_quips('bottle', 'recyclable', true).quip,
          'Bottle — recyclable! Blue bin awaits.');
      expect(_quips('bottle', 'Recyclable', true).quip,
          'Bottle — recyclable! Blue bin awaits.');
      expect(_quips('bottle', 'REUSABLE', true).quip,
          'Bottle — not trash, still useful! Share it on the Circular Hub.');
      expect(_quips('bottle', 'landfill', true).quip,
          'Bottle — not recyclable. Bin it.');
    });

    test('a stream outside the three rules defaults to the bin line', () {
      // Reachable only from a six-stream verdict (no detector box): the item is
      // still waste, so it must not borrow the "not waste" line.
      expect(_quips('battery', 'hazardous', true).quip,
          'Battery — not recyclable. Bin it.');
      expect(_quips('banana', '', true).quip, 'Banana — not recyclable. Bin it.');
    });
  });

  group('non-waste labels', () {
    test('an animal is pettable', () {
      final r = _quips('dog', 'trash', false);
      expect(r.title, 'Dog');
      expect(
        r.quip,
        'Dog — not recyclable, but pettable! '
        'The Cat Distribution System has noted this sighting.',
      );
    });

    test('every named animal takes the animal branch', () {
      for (final animal in ScanQuips.animalLabels) {
        if (animal == 'cat') continue;
        expect(_quips(animal, 'trash', false).quip,
            contains('not recyclable, but pettable!'),
            reason: '$animal should be pettable');
      }
      expect(ScanQuips.animalLabels.length, 10);
    });

    test('the cat special case overrides everything else', () {
      final r = _quips('cat', 'trash', false);
      expect(r.title, 'Cat');
      expect(r.quip,
          'A cat has appeared! The Cat Distribution System has assigned you a cat.');
      // Precedence: the non-waste branch answers first, so even a stream-mapped
      // cat is not told to bin itself.
      expect(_quips('cat', 'recycle', false).quip,
          'A cat has appeared! The Cat Distribution System has assigned you a cat.');
      // ...and an animal is never given the generic leave-it-be line.
      expect(_quips('dog', 'trash', false).quip, isNot(contains('Leave it be')));
    });

    test('any other non-waste label is left alone', () {
      final r = _quips('chair', 'trash', false);
      expect(r.title, 'Chair');
      expect(r.quip, 'Chair — not waste. Leave it be.');
    });

    test('empty label still produces a complete pair of lines', () {
      final r = _quips('', '', false);
      expect(r.title, 'Nothing detected');
      expect(r.quip, 'Nothing detected — not waste. Leave it be.');
    });
  });
}
