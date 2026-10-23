/// Unit tests for the bundled offline guidance engine
/// (`lib/services/local_llm.dart`).
///
/// What is pinned here is the contract the scan screen relies on:
///
/// * the eight seed items get real, item-specific advice;
/// * the same query always produces the same advice (determinism — the
///   templates are seeded from `label.hashCode`, never from a clock);
/// * kNN evidence can promote an ambiguous label to a named item, and stream
///   evidence alone never claims a specific item;
/// * an unknown label still gets safe disposal guidance instead of an
///   exception;
/// * the knowledge table cannot drift away from the COCO label → stream
///   mapping in `test/recycle_classifier_test.dart`;
/// * the neural slot stays off and its stub stays unimplemented, so no scan can
///   ever depend on a network model.
///
/// Run: `flutter test test/local_llm_test.dart`
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:township_of_tomorrow/services/local_llm.dart';
import 'package:township_of_tomorrow/services/recycle_classifier.dart';
import 'package:township_of_tomorrow/types.dart';

/// The bundled kNN seed items — `assets/knn/seed/seed.json`.
const seedLabels = <String>[
  'bottle_plastic',
  'can_aluminium',
  'banana_peel',
  'cardboard_box',
  'laptop',
  'battery_aa',
  'tshirt',
  'tissue_paper',
];

void main() {
  const backend = TinyLlmBackend();

  group('TinyLlmBackend — bundled knowledge', () {
    test('every seed label gets item-specific advice', () async {
      for (final seed in seedLabels) {
        final entry = tinyLlmKnowledge[seed];
        expect(entry, isNotNull, reason: '$seed needs a knowledge row');
        final advice = await backend.advise(
            ScanQuery(label: seed, confidence: 0.86));

        expect(advice.headline, isNotEmpty, reason: seed);
        expect(advice.headline.split(' ').length, lessThanOrEqualTo(8),
            reason: '$seed headline must stay short: "${advice.headline}"');
        expect(advice.guidance.toLowerCase(),
            contains(entry!.display.toLowerCase()),
            reason: '$seed guidance must name the item');
        expect(advice.binAction, startsWith(binVerbs[entry.category]!),
            reason: '$seed chip must open with the stream verb');
        expect(advice.binAction, contains(entry.bin), reason: seed);
        expect(advice.impactNote, isNotEmpty, reason: seed);
        expect(advice.followUps.length, inInclusiveRange(2, 3), reason: seed);
        expect(advice.modelInfo, TinyLlmBackend.modelInfo);
      }
    });

    test('hazardous items carry the warning through to the answer', () async {
      final advice = await backend.advise(
          const ScanQuery(label: 'battery_aa', confidence: 0.9));
      expect(advice.guidance.toLowerCase(), contains('bin a loose battery'));
      expect(advice.guidance.toLowerCase(), contains('hazardous waste'));
    });

    test('advice is deterministic for repeated identical input', () async {
      const query = ScanQuery(
        label: 'bottle_plastic',
        confidence: 0.82,
        ocrText: 'PET 500ml',
        knnLabel: 'plastic bottle',
        knnScore: 0.71,
        userQuestion: 'Does it need rinsing first?',
      );

      final first = await backend.advise(query);
      final second = await backend.advise(query);
      final third = await const TinyLlmBackend().advise(query);

      expect(second.toJson(), equals(first.toJson()));
      expect(third.toJson(), equals(first.toJson()));
      expect(jsonEncode(second.toJson()), jsonEncode(first.toJson()));
    });

    test('the same label always picks the same template variant', () async {
      final a = await backend.advise(const ScanQuery(label: 'laptop'));
      final b = await backend.advise(const ScanQuery(label: 'laptop'));
      expect(b.headline, a.headline);
      expect(b.followUps, equals(a.followUps));
    });
  });

  group('TinyLlmBackend — evidence ranking', () {
    test('a kNN identity beats no identity for an ambiguous label', () async {
      const vague = ScanQuery(label: 'waste', confidence: 0.3);
      const boosted = ScanQuery(
          label: 'waste',
          confidence: 0.3,
          knnLabel: 'plastic bottle',
          knnScore: 0.88);

      final withoutKnn = await backend.advise(vague);
      final withKnn = await backend.advise(boosted);

      expect(withoutKnn.guidance.toLowerCase(),
          isNot(contains('plastic bottle')),
          reason: 'stream-level evidence must not claim a specific item');
      expect(withKnn.guidance.toLowerCase(), contains('plastic bottle'),
          reason: 'an adopted kNN identity should name the item');
      expect(withKnn.binAction, isNot(withoutKnn.binAction));
    });

    test('a weak kNN cosine does not promote the item', () async {
      const weak = ScanQuery(label: 'waste', knnLabel: 'plastic bottle', knnScore: 0.2);
      final advice = await backend.advise(weak);
      expect(advice.guidance.toLowerCase(), isNot(contains('plastic bottle')));
    });

    test('OCR text on the item counts as evidence', () async {
      const query = ScanQuery(
          label: 'unreadable item',
          confidence: 0.4,
          ocrText: 'plastic bottle 500ml');
      final advice = await backend.advise(query);
      expect(advice.guidance.toLowerCase(), contains('plastic bottle'));
    });

    test('stream evidence alone gives a generic item in the right stream',
        () async {
      const guidance = StreamGuidance(
          WasteCategory.Organic, 'Green organics bin', 'Compost it', 'Cuts methane');
      const query = ScanQuery(
          label: 'unidentified object #3', confidence: 0.5, guidance: guidance);
      final advice = await backend.advise(query);
      expect(advice.binAction, startsWith('Compost'));
      expect(advice.guidance, isNot(contains('could not name this item')),
          reason: 'the stream is known, only the item name is not');
    });

    test('guidance never repeats a sentence (ambiguous reusable item)',
        () async {
      // Regression: the stream guidance for reuse already opens with
      // "This item still has a useful life." while the unnamed-item identity
      // line says the same thing, so the composed paragraph used to print that
      // sentence twice (seen in visual QA of the live app).
      const guidance = StreamGuidance(
        WasteCategory.Reusable,
        'Circular Hub — share it instead',
        'This item still has a useful life. List it on the Circular Hub rather '
            'than discarding it.',
        'Reuse displaces a new purchase.',
      );
      const query = ScanQuery(
          label: 'unidentified object #7', confidence: 0.42, guidance: guidance);
      final advice = await backend.advise(query);

      String normalise(String s) => s
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'[.!?,;:]+$'), '');
      final sentences = advice.guidance
          .split(RegExp(r'[.!?]+\s*'))
          .map(normalise)
          .where((s) => s.isNotEmpty)
          .toList();

      expect(sentences.toSet().length, sentences.length,
          reason: 'guidance repeated a sentence: "${advice.guidance}"');
      expect(advice.guidance.toLowerCase(),
          isNot(contains('useful life. this item still has a useful life')));
      expect(advice.guidance.toLowerCase(), contains('circular hub'),
          reason: 'the actual instruction must survive the dedup');
    });

    test('unlisted COCO labels fall back to the COCO stream mapping', () async {
      const cases = <String, WasteCategory>{
        'wine glass': WasteCategory.Recyclable,
        'chair': WasteCategory.Reusable,
        'pizza': WasteCategory.Organic,
      };
      for (final entry in cases.entries) {
        final advice =
            await backend.advise(ScanQuery(label: entry.key, confidence: 0.6));
        expect(coarseStream(entry.value), categoriseCocoLabel(entry.key),
            reason: '${entry.key}: the expectation itself must match the table');
        expect(advice.binAction, startsWith(binVerbs[entry.value]!),
            reason: '${entry.key} should reach the '
                '${binVerbs[entry.value]} chip');
      }
    });
  });

  group('TinyLlmBackend — unknown input', () {
    test('an unknown label falls back to safe disposal, never throws',
        () async {
      final advice = await backend.advise(
          const ScanQuery(label: 'zzyzx_unknown_widget', confidence: 0.11));
      expect(advice.guidance, contains('could not name this item'));
      expect(advice.guidance, isNotEmpty);
      expect(advice.binAction, isNotEmpty);
      expect(advice.impactNote, isNotEmpty);
      expect(advice.followUps.length, inInclusiveRange(2, 3));
      expect(advice.headline.split(' ').length, lessThanOrEqualTo(8));
    });

    test('empty evidence still produces advice', () async {
      final advice = await backend.advise(const ScanQuery(label: ''));
      expect(advice.headline, isNotEmpty);
      expect(advice.guidance, isNotEmpty);
      expect(advice.binAction, contains('—'));
    });
  });

  group('TinyLlmBackend — follow-up questions', () {
    test('a question is answered and never suggested back', () async {
      const asked = 'Does it need rinsing first?';
      const base = ScanQuery(label: 'can_aluminium', confidence: 0.8);
      final plain = await backend.advise(base);
      final answered =
          await backend.advise(const ScanQuery(
              label: 'can_aluminium', confidence: 0.8, userQuestion: asked));

      expect(answered.guidance, isNot(plain.guidance));
      expect(answered.guidance.toLowerCase(), contains('rinse'));
      expect(answered.guidance.toLowerCase(), contains('aluminium can'));
      expect(
          answered.followUps.map((f) => f.toLowerCase()),
          isNot(contains(asked.toLowerCase())));
      expect(answered.followUps.length, inInclusiveRange(2, 3));
    });

    test('an unrecognised question gets a neutral lead-in', () async {
      final advice = await backend.advise(const ScanQuery(
          label: 'tshirt',
          confidence: 0.7,
          userQuestion: 'Is there a collection on Sunday?'));
      expect(advice.guidance, contains('Here is what matters for this item'));
    });
  });

  group('ScanAdvice serialisation', () {
    test('toJson / fromJson round-trip is lossless', () async {
      final advice = await backend.advise(
          const ScanQuery(label: 'banana_peel', confidence: 0.77));
      final restored = ScanAdvice.fromJson(advice.toJson());

      expect(restored.toJson(), equals(advice.toJson()));
      expect(restored.headline, advice.headline);
      expect(restored.binAction, advice.binAction);
      expect(restored.followUps, equals(advice.followUps));
      expect(restored.modelInfo, TinyLlmBackend.modelInfo);
    });

    test('toJson carries every field the card renders', () async {
      final advice = await backend.advise(
          const ScanQuery(label: 'cardboard_box', confidence: 0.9));
      expect(
          advice.toJson().keys.toSet(),
          equals({
            'headline',
            'guidance',
            'binAction',
            'impactNote',
            'followUps',
            'modelInfo',
          }));
    });
  });

  group('knowledge table hygiene', () {
    test('the seed set is fully covered', () {
      for (final seed in seedLabels) {
        expect(tinyLlmKnowledge.containsKey(seed), isTrue, reason: seed);
      }
      expect(tinyLlmKnowledge.length, greaterThanOrEqualTo(seedLabels.length));
    });

    test('COCO aliases agree with the label → stream table', () {
      var checked = 0;
      for (final entry in tinyLlmKnowledge.values) {
        final coco = cocoClassOfKnowledgeKey[entry.key];
        expect(coco, isNotNull, reason: '${entry.key} needs a COCO alias pin');
        if (coco == null) continue;
        if (!cocoLabels.contains(coco)) continue;
        checked++;
        expect(entry.stream, categoriseCocoLabel(coco),
            reason: '${entry.key} (as "$coco") disagrees with the COCO table');
      }
      expect(checked, greaterThanOrEqualTo(3),
          reason: 'at least three rows must be pinned to a real COCO class');
    });

    test('entries match the spellings the detectors actually emit', () {
      final bottle = tinyLlmKnowledge['bottle_plastic']!;
      expect(bottle.matchesLabel(normaliseCocoLabel('plastic bottle')), isTrue);
      expect(bottle.matchesLabel(normaliseCocoLabel('BOTTLE')), isTrue);
      expect(bottle.matchesLabel(normaliseCocoLabel('  Water_Bottle ')), isTrue);
      expect(bottle.matchesLabel(normaliseCocoLabel('cardboard box')), isFalse);
    });

    test('every entry has steps, a bin and an impact', () {
      for (final entry in tinyLlmKnowledge.values) {
        expect(entry.disposalSteps, isNotEmpty, reason: entry.key);
        expect(entry.bin, isNotEmpty, reason: entry.key);
        expect(entry.impact, isNotEmpty, reason: entry.key);
        expect(entry.key, entry.key.toLowerCase(), reason: entry.key);
      }
    });
  });

  group('LocalLlmService — the offline guarantee', () {
    test('the neural slot is off and its stub is unimplemented', () async {
      expect(kEnableNeuralTinyLlm, isFalse);
      expect(LocalLlmService.neuralTinyLlmEnabled, isFalse);
      expect(LocalLlmService.backend(), isA<TinyLlmBackend>());

      await expectLater(
        const NeuralTinyLlmBackend().advise(const ScanQuery(label: 'bottle')),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('advise() answers offline for a scan-shaped query', () async {
      final advice = await LocalLlmService.advise(const ScanQuery(
          label: 'tissue_paper',
          confidence: 0.64,
          guidance: StreamGuidance(WasteCategory.Landfill, 'Grey bin',
              'Place it in the grey bin.', 'Avoids contamination.')));
      expect(advice.modelInfo, TinyLlmBackend.modelInfo);
      expect(advice.binAction, contains('grey general-waste bin'));
    });
  });
}
