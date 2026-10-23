/// Headline + quip copy for a finished scan's result card.
///
/// The card used to open with the classifier's fixed headline
/// (`ClassificationOutcome.deviceName`); this service turns the primary
/// detection into two lines of plain-language copy instead — a title (the
/// humanized label) and one quip that says what the stream means for the
/// resident.
///
/// Pure string work: no I/O, no model, no state. Every string below is fixed by
/// the copy spec with `<label>` standing for the humanized label, so the caller
/// only passes the three facts the scan result already carries per box —
/// `DetectedObject.label` / `.category` / `.wasteRelevant`.
library;

import 'recycle_classifier.dart';

/// The two lines the result card shows for one scan.
class ScanQuips {
  ScanQuips._();

  /// Detector labels that are not waste but still deserve a quip: the township
  /// camera fires on its animals often enough that the copy names the case.
  static const animalLabels = <String>{
    'cat',
    'dog',
    'bird',
    'horse',
    'sheep',
    'cow',
    'elephant',
    'bear',
    'zebra',
    'giraffe',
  };

  /// Title shown when the scan has no label to name at all.
  static const nothingDetected = 'Nothing detected';

  /// Internal stream buckets the copy rules are written against.
  static const _recyclable = 'recyclable';
  static const _reusable = 'reusable';
  static const _animalLabel = 'cat';

  /// Title + quip for this scan.
  ///
  /// [topLabel] is the detector's label for the primary box ('' when nothing
  /// fired), [category] is the stream it was mapped to — either enum's spelling
  /// is accepted (`RecycleCategory.recycle` / `.reusable` / `.trash` and
  /// `WasteCategory.Recyclable` / `.Reusable` / `.Landfill`) — and
  /// [isWasteRelevant] says whether the box is waste evidence rather than
  /// background scenery.
  ///
  /// [catDistributionCopy] picks the wording for a **non-cat animal** box: the
  /// live scan card passes `false`, so a bird/dog/horse sighting gets no
  /// Cat-Distribution line and — matching the scan's cat-dex gate — no hint that
  /// a catch is on offer. The default stays `true` for the legacy wording
  /// pinned verbatim by `test/scan_quips_test.dart`.
  static ({String title, String quip}) forResult({
    required String topLabel,
    required String category,
    required bool isWasteRelevant,
    bool catDistributionCopy = true,
  }) {
    final title = humanizeLabel(topLabel);
    return (
      title: title,
      quip: _quipFor(title, topLabel, category, isWasteRelevant,
          catDistributionCopy),
    );
  }

  /// Humanized label: trimmed, underscore spellings folded to spaces, runs of
  /// whitespace collapsed, lower-cased then sentence-cased — so `cell_phone`,
  /// `  CELL   PHONE ` and `cell phone` all render as `Cell phone`. A label with
  /// no name in it at all becomes [nothingDetected].
  static String humanizeLabel(String label) {
    final normalised = normaliseCocoLabel(label).trim();
    if (normalised.isEmpty) return nothingDetected;
    return normalised[0].toUpperCase() + normalised.substring(1);
  }

  /// The quip for one rule branch.
  ///
  /// Order matters: a box that is *not* waste evidence is answered by the
  /// animal / leave-it-be rules before its stream is consulted, because the
  /// label table falls every non-waste class through to `trash` — a cat that
  /// reached the trash rule would be told to bin itself.
  static String _quipFor(
    String title,
    String rawLabel,
    String category,
    bool isWasteRelevant,
    bool catDistributionCopy,
  ) {
    if (!isWasteRelevant) {
      final label = normaliseCocoLabel(rawLabel);
      if (label == _animalLabel) {
        return 'A cat has appeared! '
            'The Cat Distribution System has assigned you a cat.';
      }
      if (animalLabels.contains(label)) {
        // Non-cat animal. It is pettable but it is not a cat, so it must not
        // borrow the Cat Distribution copy: the card it would promise (the Dex
        // catch) is suppressed for every animal the cat gate does not clear.
        if (!catDistributionCopy) {
          return '$title — not recyclable, but pettable! '
              'No Cat Dex entry for this one.';
        }
        return '$title — not recyclable, but pettable! '
            'The Cat Distribution System has noted this sighting.';
      }
      return '$title — not waste. Leave it be.';
    }
    return switch (_stream(category)) {
      _recyclable => '$title — recyclable! Blue bin awaits.',
      _reusable =>
        '$title — not trash, still useful! Share it on the Circular Hub.',
      // `trash` and `landfill`, plus any stream outside the three copy rules
      // (organic / e-waste / hazardous): the item is waste the resident has to
      // put somewhere, and the guidance card below carries the exact bin.
      _ => '$title — not recyclable. Bin it.',
    };
  }

  /// Fold a caller's stream name onto the copy rules.
  static String _stream(String category) {
    final name = category.trim().toLowerCase().replaceAll('_', ' ');
    return switch (name) {
      'recyclable' || 'recycle' || 'recycling' => _recyclable,
      'reusable' || 'reuse' => _reusable,
      'trash' || 'landfill' => 'trash',
      _ => '',
    };
  }
}
