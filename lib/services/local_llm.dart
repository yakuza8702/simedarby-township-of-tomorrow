/// Tiny on-device language layer for the scanner.
///
/// The scanner has to *explain* a scan — what the item is, exactly what to do
/// with it, why it matters — in plain language, on a phone, offline. That is
/// what this file is: a bundled knowledge + retrieval engine
/// ([TinyLlmBackend]) that composes an answer out of a const item table, the
/// evidence the pipeline already produced, and deterministic templates.
///
/// Design rules, all deliberate:
///
/// * **Offline and dependency-free.** No network, no model download, no new
///   package: a const knowledge map plus string composition. There is no
///   failure mode where a resident is left without guidance because a service
///   was unreachable.
/// * **Deterministic.** The same [ScanQuery] always produces the same
///   [ScanAdvice]: template variation is seeded from `label.hashCode`, never
///   from a clock or a random source. That is what makes it testable.
/// * **The heavy/remote path is never required.** [kEnableNeuralTinyLlm] is a
///   documented slot for a future quantized on-device text model. It is
///   DEFAULT OFF and stays off: while it is off nothing here can reach the
///   network, and every scan still gets guidance from [TinyLlmBackend].
library;

import '../types.dart';
import 'recycle_classifier.dart';
import 'waste_classifier.dart';

/// Const knowledge row for one recognised item.
///
/// [key] is the bundled kNN seed name where one exists (`bottle_plastic`), so
/// the table lines up with `assets/knn/seed/seed.json`; [aliases] carry the
/// spellings the detector, ML Kit and the kNN vote actually emit.
class KnowledgeEntry {
  /// Canonical key — the snake_case seed name, e.g. `bottle_plastic`.
  final String key;

  /// Resident-facing item name, e.g. `plastic bottle`.
  final String display;

  /// Normalised spellings that also match this row (`bottle`, `water bottle`).
  final List<String> aliases;

  /// What to do with it, in order, plain language (one imperative per step).
  final List<String> disposalSteps;

  /// Short bin name used for the guidance chip, e.g. `blue recycling bin`.
  final String bin;

  /// One sentence on why this matters.
  final String impact;

  /// Safety warning for items that are dangerous to bin casually.
  final String? hazardNote;

  /// The six-stream category this row belongs to.
  final WasteCategory category;

  const KnowledgeEntry({
    required this.key,
    required this.display,
    required this.aliases,
    required this.disposalSteps,
    required this.bin,
    required this.impact,
    required this.category,
    this.hazardNote,
  });

  /// Coarse stream, kept consistent with `recycle_classifier.dart` — see
  /// [coarseStream] and the consistency test in `test/local_llm_test.dart`.
  RecycleCategory get stream => coarseStream(category);

  /// True when [normalisedLabel] names this row (`bottle_plastic`, `bottle`,
  /// `500ml water bottle` all hit the plastic-bottle row).
  bool matchesLabel(String normalisedLabel) {
    if (normalisedLabel.isEmpty) return false;
    if (normalisedLabel == normaliseCocoLabel(key)) return true;
    if (normalisedLabel == normaliseCocoLabel(display)) return true;
    if (aliases.contains(normalisedLabel)) return true;
    return aliases.any(normalisedLabel.contains);
  }
}

/// The bundled item table. Eight seed items (the kNN seed set) plus the
/// household items the detector names most often.
const tinyLlmKnowledge = <String, KnowledgeEntry>{
  'bottle_plastic': KnowledgeEntry(
    key: 'bottle_plastic',
    display: 'Plastic bottle',
    aliases: ['plastic bottle', 'bottle', 'water bottle', 'drink bottle',
      'pet bottle', 'soft drink bottle', 'juice bottle'],
    disposalSteps: [
      'Empty it and give it a quick rinse',
      'Keep the cap screwed on so it stays with the bottle',
      'Drop it loose in the blue recycling bin — never bagged',
    ],
    bin: 'blue recycling bin',
    impact: 'One clean, loose bottle gets recovered; a dirty or bagged one is '
        'often rejected at the sorting line instead.',
    category: WasteCategory.Recyclable,
  ),
  'can_aluminium': KnowledgeEntry(
    key: 'can_aluminium',
    display: 'Aluminium can',
    aliases: ['aluminium can', 'aluminum can', 'can', 'tin can', 'soda can',
      'drink can', 'beverage can', 'soft drink can'],
    disposalSteps: [
      'Pour out anything left inside',
      'Push the tab in so no sharp edge is exposed',
      'Drop it loose in the blue recycling bin',
    ],
    bin: 'blue recycling bin',
    impact: 'Aluminium recycles endlessly, and a can collected today is usually '
        'back on a shelf within a couple of months.',
    category: WasteCategory.Recyclable,
  ),
  'banana_peel': KnowledgeEntry(
    key: 'banana_peel',
    display: 'Banana peel',
    aliases: ['banana peel', 'banana skin', 'banana', 'fruit peel', 'fruit skin'],
    disposalSteps: [
      'Pull off any plastic sticker or tape',
      'Add it to the organics bin or the precinct compost bay',
      'Wrap it in newspaper only if the collection asks you to',
    ],
    bin: 'green organics bin or compost bay',
    impact: 'Food scraps are the heaviest part of household waste; composting '
        'them cuts landfill methane and returns nutrients to township soil.',
    category: WasteCategory.Organic,
  ),
  'cardboard_box': KnowledgeEntry(
    key: 'cardboard_box',
    display: 'Cardboard box',
    aliases: ['cardboard box', 'cardboard', 'carton', 'shipping box', 'box',
      'packaging box'],
    disposalSteps: [
      'Flatten it so it takes no room',
      'Remove tape, staples and any polystyrene packing',
      'Keep it dry and put it loose in the blue recycling bin',
    ],
    bin: 'blue recycling bin',
    impact: 'Flattened cardboard is high-value fibre; wet or taped boxes are '
        'usually sent to landfill instead of being recovered.',
    category: WasteCategory.Recyclable,
  ),
  'laptop': KnowledgeEntry(
    key: 'laptop',
    display: 'Laptop',
    aliases: ['laptop', 'notebook computer', 'portable computer', 'computer'],
    disposalSteps: [
      'Back up anything you still need',
      'Wipe the drive so no data leaves with it',
      'Take it to the township e-waste drop-off, or list it working on the '
          'Circular Hub',
    ],
    bin: 'E-waste drop-off',
    impact: 'A laptop holds recoverable metals and a battery that can ignite in '
        'a collection truck, so it never belongs in a kerbside bin.',
    hazardNote: 'Never put a laptop in the general bin — the battery is the risk.',
    category: WasteCategory.Ewaste,
  ),
  'battery_aa': KnowledgeEntry(
    key: 'battery_aa',
    display: 'AA battery',
    aliases: ['aa battery', 'aaa battery', 'battery', 'batteries',
      'alkaline battery', 'dry cell', 'household battery'],
    disposalSteps: [
      'Tape the terminals so it cannot short against another cell',
      'Keep it in a dry container, never loose in a bag',
      'Drop it at the household hazardous waste collection point',
    ],
    bin: 'household hazardous waste drop-off',
    impact: 'Batteries leak and can catch fire in collection trucks, and one '
        'cell can contaminate a whole load of recyclables.',
    hazardNote: 'Never bin a loose battery, and never mix it with other waste.',
    category: WasteCategory.Hazardous,
  ),
  'tshirt': KnowledgeEntry(
    key: 'tshirt',
    display: 'T-shirt',
    aliases: ['t-shirt', 'tshirt', 'shirt', 'tee', 'clothing', 'clothes',
      'garment', 'textile'],
    disposalSteps: [
      'Check it is clean and dry',
      'List it on the Circular Hub or take it to a textile donation point',
      'If it is worn out, use it as a cleaning rag before discarding it',
    ],
    bin: 'Circular Hub',
    impact: 'Textiles take decades to break down in landfill, and a wearable '
        'shirt displaces a new purchase entirely.',
    category: WasteCategory.Reusable,
  ),
  'tissue_paper': KnowledgeEntry(
    key: 'tissue_paper',
    display: 'Tissue paper',
    aliases: ['tissue paper', 'tissue', 'used tissue', 'napkin', 'paper towel',
      'wet wipe', 'tissue box'],
    disposalSteps: [
      'Do not put it in the recycling bin — used tissue is not recoverable fibre',
      'Bag it with the general waste',
      'Choose a reusable cloth where you can next time',
    ],
    bin: 'grey general-waste bin',
    impact: 'Tissues are short-fibred and usually soiled, so they contaminate a '
        'recycling load rather than adding to it.',
    category: WasteCategory.Landfill,
  ),
};

/// The COCO class each bundled key usually arrives as, for the keys that have a
/// plausible detector name. Used to pin the table to the same coarse streams as
/// `recycle_classifier.dart` (see `test/recycle_classifier_test.dart`): keys
/// whose COCO name is a real class must agree with [categoriseCocoLabel].
const cocoClassOfKnowledgeKey = <String, String>{
  'bottle_plastic': 'bottle',
  'can_aluminium': 'can',
  'banana_peel': 'banana',
  'cardboard_box': 'cardboard box',
  'laptop': 'laptop',
  'battery_aa': 'battery',
  'tshirt': 't-shirt',
  'tissue_paper': 'tissue paper',
};

/// Six-stream category → the coarse stream the detector stage speaks.
///
/// This is the bridge that keeps the guidance consistent with the label →
/// stream table: Recyclable recycles, Reusable *and* E-waste are the reuse
/// stream (the bench sorts a laptop to `reusable`), and food/hazardous/general
/// waste all land on trash.
RecycleCategory coarseStream(WasteCategory category) => switch (category) {
      WasteCategory.Recyclable => RecycleCategory.recycle,
      WasteCategory.Reusable || WasteCategory.Ewaste => RecycleCategory.reusable,
      WasteCategory.Organic ||
      WasteCategory.Landfill ||
      WasteCategory.Hazardous =>
        RecycleCategory.trash,
    };

/// Short resident-facing bin names, one per stream, matching the wording of
/// `GUIDANCE` in `waste_classifier.dart`.
const shortBinNames = <WasteCategory, String>{
  WasteCategory.Recyclable: 'blue recycling bin',
  WasteCategory.Organic: 'green organics bin or compost bay',
  WasteCategory.Reusable: 'Circular Hub',
  WasteCategory.Ewaste: 'E-waste drop-off',
  WasteCategory.Hazardous: 'household hazardous waste drop-off',
  WasteCategory.Landfill: 'grey general-waste bin',
};

/// Verb that opens the bin chip, one per stream.
const binVerbs = <WasteCategory, String>{
  WasteCategory.Recyclable: 'Recycle',
  WasteCategory.Organic: 'Compost',
  WasteCategory.Reusable: 'Reuse',
  WasteCategory.Ewaste: 'E-waste drop-off',
  WasteCategory.Hazardous: 'Hazardous drop-off',
  WasteCategory.Landfill: 'General waste',
};

/// Short verb phrase used in headlines, one per stream.
const headlineVerbs = <WasteCategory, String>{
  WasteCategory.Recyclable: 'recycle it',
  WasteCategory.Organic: 'compost it',
  WasteCategory.Reusable: 'reuse it',
  WasteCategory.Ewaste: 'keep it out of the bin',
  WasteCategory.Hazardous: 'do not bin it',
  WasteCategory.Landfill: 'general waste only',
};

/// Generic item name used when the scanner can place the stream but not name
/// the item. Kept short: these names appear inside headline templates that must
/// stay under eight words.
const genericItemNames = <WasteCategory, String>{
  WasteCategory.Recyclable: 'recyclable item',
  WasteCategory.Organic: 'food or garden waste',
  WasteCategory.Reusable: 'reusable item',
  WasteCategory.Ewaste: 'electronic item',
  WasteCategory.Hazardous: 'hazardous item',
  WasteCategory.Landfill: 'non-recyclable item',
};

/// One scan, as the language layer sees it: what the pipeline found, and what
/// the resident asked afterwards ('' for the first pass).
class ScanQuery {
  /// Detector / classifier label for the item, e.g. `bottle_plastic` or
  /// `bottle`. May be empty when nothing was detected.
  final String label;

  /// Confidence in [0,1] for [label].
  final double confidence;

  /// Text read off the item (brand, material line, expiry). Null when the scan
  /// did not run OCR — `ScanResult` carries no OCR field today, so callers that
  /// have text pass it explicitly.
  final String? ocrText;

  /// Local kNN item identity, when the embedder adopted one.
  final String? knnLabel;

  /// Cosine of that kNN match, in [0,1].
  final double? knnScore;

  /// The six-stream guidance the pipeline already decided on, when it decided.
  final StreamGuidance? guidance;

  /// The resident's follow-up question; '' for the first pass.
  final String userQuestion;

  const ScanQuery({
    required this.label,
    this.confidence = 0.0,
    this.ocrText,
    this.knnLabel,
    this.knnScore,
    this.guidance,
    this.userQuestion = '',
  });
}

/// What the resident sees: a headline, plain-language guidance, the bin chip,
/// why it matters, and 2–3 tappable follow-up questions.
class ScanAdvice {
  final String headline;
  final String guidance;
  final String binAction;
  final String impactNote;
  final List<String> followUps;
  final String modelInfo;

  const ScanAdvice({
    required this.headline,
    required this.guidance,
    required this.binAction,
    required this.impactNote,
    required this.followUps,
    this.modelInfo = TinyLlmBackend.modelInfo,
  });

  Map<String, dynamic> toJson() => {
        'headline': headline,
        'guidance': guidance,
        'binAction': binAction,
        'impactNote': impactNote,
        'followUps': followUps,
        'modelInfo': modelInfo,
      };

  /// Round-trip counterpart of [toJson] — the scan log writes advice with it and
  /// reads it back unchanged.
  static ScanAdvice fromJson(Map<String, dynamic> json) => ScanAdvice(
        headline: json['headline'] as String,
        guidance: json['guidance'] as String,
        binAction: json['binAction'] as String,
        impactNote: json['impactNote'] as String,
        followUps: [
          for (final f in (json['followUps'] as List)) f as String,
        ],
        modelInfo: json['modelInfo'] as String,
      );
}

/// A source of scan guidance. One method, so a future backend can be swapped in
/// behind [LocalLlmService] without the screens noticing.
abstract class LlmBackend {
  Future<ScanAdvice> advise(ScanQuery q);
}

/// The bundled offline engine: const knowledge + evidence scoring + templates.
///
/// Fully synchronous string work behind an async signature (the interface is
/// async so a future on-device model can be awaited without changing callers).
/// It never throws: anything unexpected falls back to safe disposal guidance.
class TinyLlmBackend implements LlmBackend {
  const TinyLlmBackend();

  /// Reported with every answer so the UI can state where guidance came from.
  static const modelInfo =
      'TinyLlm v1 (on-device knowledge+retrieval, offline, no network)';

  /// Evidence floor for asserting a *specific* item. Label evidence clears it
  /// on its own; a kNN identity clears it when the cosine is meaningful; stream
  /// evidence alone deliberately does not (that answer stays generic).
  static const specificityFloor = 50.0;

  @override
  Future<ScanAdvice> advise(ScanQuery q) async {
    try {
      return _compose(_bestEntry(q), q, unidentified: !_hasEvidence(q));
    } catch (e, st) {
      // Guidance must survive a bug in the ranking: the resident still gets a
      // safe, correct-if-boring instruction rather than an exception.
      assert(() {
        // ignore: avoid_print
        print('TWP:ERROR tiny llm: $e\n$st');
        return true;
      }());
      return _safeAdvice(q);
    }
  }

  /// Best knowledge row for the evidence in [q], or a generic row built from the
  /// stream when nothing specific clears [specificityFloor].
  KnowledgeEntry _bestEntry(ScanQuery q) {
    final label = normaliseCocoLabel(q.label);
    KnowledgeEntry? best;
    var bestScore = 0.0;

    for (final entry in tinyLlmKnowledge.values) {
      final score = _labelScore(entry, label) +
          _knnScore(entry, q) +
          _ocrScore(entry, q.ocrText) +
          _guidanceScore(entry, q.guidance);
      // Ties break on the key so the choice never depends on map order.
      if (best == null ||
          score > bestScore ||
          (score == bestScore && entry.key.compareTo(best.key) < 0)) {
        best = entry;
        bestScore = score;
      }
    }
    if (best != null && bestScore >= specificityFloor) return best;
    return _genericEntry(q);
  }

  /// Label evidence, strongest first: exact key, exact display, exact alias,
  /// then a phrase contained in the label.
  double _labelScore(KnowledgeEntry e, String normalisedLabel) {
    if (normalisedLabel.isEmpty) return 0;
    if (normalisedLabel == normaliseCocoLabel(e.key)) return 120;
    if (normalisedLabel == normaliseCocoLabel(e.display)) return 110;
    if (e.aliases.contains(normalisedLabel)) return 100;
    for (final alias in e.aliases) {
      if (normalisedLabel.contains(alias)) return 70;
    }
    if (normalisedLabel.contains(normaliseCocoLabel(e.display))) return 60;
    return 0;
  }

  /// kNN identity evidence, scaled by the cosine: an adopted identity at a high
  /// cosine is enough to assert the item on its own, a weak one is not.
  double _knnScore(KnowledgeEntry e, ScanQuery q) {
    final knn = q.knnLabel;
    if (knn == null) return 0;
    final weight = (q.knnScore ?? 0.5).clamp(0.35, 1.0);
    final strength = _labelScore(e, normaliseCocoLabel(knn));
    if (strength == 0) return 0;
    return (strength >= 70 ? 80 : 40) * weight;
  }

  /// OCR text evidence: a phrase read off the item counts nearly as much as the
  /// detector naming it, loose token hits count for less.
  double _ocrScore(KnowledgeEntry e, String? ocrText) {
    if (ocrText == null) return 0;
    final text = normaliseCocoLabel(ocrText);
    if (text.isEmpty) return 0;
    final phrase = _labelScore(e, text) * 0.8;
    final tokens = text.split(' ').where((t) => t.length >= 3).toSet();
    final words = <String>{
      ...normaliseCocoLabel(e.display).split(' '),
      for (final alias in e.aliases) ...alias.split(' '),
    };
    final hits = tokens.where(words.contains).length;
    final loose = (hits * 20).clamp(0, 60).toDouble();
    return phrase > loose ? phrase : loose;
  }

  /// Stream evidence from the pipeline's own decision: same six-stream category
  /// is a strong hint, the same coarse stream a weak one.
  double _guidanceScore(KnowledgeEntry e, StreamGuidance? guidance) {
    if (guidance == null) return 0;
    if (e.category == guidance.category) return 30;
    return e.stream == coarseStream(guidance.category) ? 12 : 0;
  }

  /// Generic row for the stream the evidence points at: the resident still gets
  /// the right bin, just without an item claim.
  KnowledgeEntry _genericEntry(ScanQuery q) {
    final category = q.guidance?.category ?? _classify(q.label).$1;
    final guidance = GUIDANCE[category] ?? GUIDANCE[WasteCategory.Landfill]!;
    final bin = shortBinNames[category] ?? shortBinNames[WasteCategory.Landfill]!;
    return KnowledgeEntry(
      key: 'generic_${category.name}',
      display: genericItemNames[category] ?? 'item',
      aliases: const [],
      disposalSteps: [guidance.action],
      bin: bin,
      impact: guidance.impact,
      hazardNote: category == WasteCategory.Hazardous
          ? 'Keep it in its original container and never mix it with other waste.'
          : null,
      category: category,
    );
  }

  /// Six-stream category for a label the knowledge table does not know: the
  /// keyword table first, then the coarse COCO table both the bench and the
  /// fetch script already agree on, then the safe default (general waste).
  ///
  /// The second half of the record says whether any table actually recognised
  /// the material — an unrecognised *and* unclassifiable label is what makes the
  /// answer lead with the safety caveat.
  (WasteCategory, bool) _classify(String label) {
    final normalised = normaliseCocoLabel(label);
    if (normalised.isEmpty) return (WasteCategory.Landfill, false);
    final phrase = PHRASE_STREAMS[normalised];
    if (phrase != null) return (phrase, true);

    var best = WasteCategory.Landfill;
    var bestWeight = 0.0;
    for (final rule in RULES) {
      for (final keyword in rule.keywords) {
        if (keyword.length < 3) continue;
        if (normalised.contains(keyword) && rule.weight > bestWeight) {
          best = rule.category;
          bestWeight = rule.weight;
        }
      }
    }
    if (bestWeight > 0) return (best, true);

    return (
      switch (categoriseCocoLabel(label)) {
        RecycleCategory.recycle => WasteCategory.Recyclable,
        RecycleCategory.reusable => WasteCategory.Reusable,
        RecycleCategory.trash => WasteCategory.Landfill,
      },
      false,
    );
  }

  /// Whether anything in the query names or classifies the item at all. False
  /// means the answer must be the safe default, and say so.
  bool _hasEvidence(ScanQuery q) {
    if (q.guidance != null) return true;
    if (q.knnLabel != null && q.knnLabel!.trim().isNotEmpty) return true;
    if (q.ocrText != null && q.ocrText!.trim().isNotEmpty) return true;
    final label = normaliseCocoLabel(q.label);
    if (label.isEmpty) return false;
    if (tinyLlmKnowledge.values.any((e) => _labelScore(e, label) > 0)) {
      return true;
    }
    return _classify(q.label).$2;
  }

  // ── composition ───────────────────────────────────────────────────────────

  ScanAdvice _compose(KnowledgeEntry e, ScanQuery q,
      {required bool unidentified}) {
    // Deterministic variation: the same label always picks the same template.
    final variant = q.label.hashCode % 3;
    final asked = q.userQuestion.trim();
    final named = e.key.startsWith('generic_') == false;
    final sentences = <String>[
      if (asked.isNotEmpty) _answerFor(asked, e),
      if (named)
        'This looks like ${_article(e.display)} ${e.display.toLowerCase()}'
            '${_confidenceNote(q.confidence)}.'
      else
        _genericIdentity(e),
      _stepsSentence(e.disposalSteps),
      if (e.hazardNote != null) e.hazardNote!,
    ].whereType<String>().where((s) => s.isNotEmpty).toList();
    // The identity line and the stream guidance overlap by design ("This item
    // still has a useful life." is both the reuse stream's opening line and the
    // unnamed-item identity line), so the paragraph is deduplicated before it is
    // handed to the card.
    final guidance = _dedupeSentences(sentences);

    return ScanAdvice(
      headline: _headline(e, variant),
      // An item nothing could place still leads with the safety caveat: the
      // resident must know this is a default, not an identification.
      guidance: unidentified && asked.isEmpty
          ? 'The scanner could not name this item, so this is the safe default: '
              '$guidance'
          : guidance,
      binAction: _binAction(e),
      impactNote: e.impact,
      followUps: _followUps(e, asked, variant),
    );
  }

  /// Compose the guidance paragraph without repeating itself.
  ///
  /// The pieces this engine joins are independently authored: the stream
  /// guidance in `waste_classifier.dart` already opens the reuse action with
  /// "This item still has a useful life." while the unnamed-item identity line
  /// says the same thing, so the two used to be printed back to back (seen in
  /// visual QA of the live app). Sentences are compared whitespace-normalised
  /// and case-insensitively, and a sentence that is a strict prefix of a later
  /// one is dropped as well — the later sentence says everything it said and
  /// carries the instruction that actually matters.
  ///
  /// The paragraph is capped at three sentences, and if deduplication were ever
  /// to remove everything the original composition is used instead, so guidance
  /// can never come back empty.
  String _dedupeSentences(List<String> parts) {
    final sentences = [
      for (final part in parts) ..._splitSentences(part),
    ];
    final keys = [for (final s in sentences) _sentenceKey(s)];
    final kept = <String>[];
    final keptKeys = <String>[];
    for (var i = 0; i < sentences.length; i++) {
      final key = keys[i];
      if (key.isEmpty || keptKeys.contains(key)) continue;
      final repeatedByLater = keys.skip(i + 1).any((k) => k.startsWith('$key '));
      if (repeatedByLater) continue;
      keptKeys.add(key);
      kept.add(sentences[i]);
    }
    final joined = kept.take(3).join(' ');
    return joined.isEmpty ? parts.take(3).join(' ') : joined;
  }

  /// Split one composed piece into grammatical sentences, terminators kept.
  static List<String> _splitSentences(String text) {
    final matches = RegExp(r'[^.!?]+(?:[.!?]+|$)').allMatches(text);
    return [
      for (final match in matches) match.group(0)!.trim(),
    ].where((s) => s.isNotEmpty).toList();
  }

  /// Sentence fingerprint for the duplicate check: lowercase, punctuation
  /// flattened to single spaces, so "This item still has a useful life." and
  /// "this item still has a useful life" compare equal.
  static String _sentenceKey(String sentence) => sentence
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  String _headline(KnowledgeEntry e, int variant) {
    final display =
        e.key.startsWith('generic_') ? e.display : e.display.toLowerCase();
    return switch (variant) {
      0 => '${_capitalise(display)} — '
          '${headlineVerbs[e.category] ?? 'check the stream'}',
      1 => 'Where does this go: $display',
      _ => 'How to handle: $display',
    };
  }

  String _genericIdentity(KnowledgeEntry e) => switch (e.category) {
        WasteCategory.Recyclable =>
          'This is recyclable material whose exact type the scanner could not pin down.',
        WasteCategory.Organic => 'This is food or garden waste.',
        WasteCategory.Reusable => 'This item still has a useful life.',
        WasteCategory.Ewaste => 'This is an electronic item.',
        WasteCategory.Hazardous => 'This is household hazardous waste.',
        WasteCategory.Landfill => 'This item has no recovery route today.',
      };

  String _confidenceNote(double confidence) {
    final percent = (confidence * 100).round().clamp(0, 100);
    return percent >= 40 ? ' (about $percent% confident)' : '';
  }

  /// Steps as one plain sentence: `Rinse it out, keep the cap on and drop it
  /// loose in the blue bin.`
  String _stepsSentence(List<String> steps) {
    if (steps.isEmpty) return '';
    final parts = [
      for (final step in steps) _lowerFirst(step.replaceAll(RegExp(r'\.$'), '')),
    ];
    if (parts.length == 1) return '${_capitalise(parts.first)}.';
    final head = parts.sublist(0, parts.length - 1).join(', ');
    return '${_capitalise(head)} and ${parts.last}.';
  }

  String _binAction(KnowledgeEntry e) =>
      '${binVerbs[e.category] ?? 'Check'} — ${e.bin}';

  /// 2–3 tappable questions, rotated deterministically and never repeating the
  /// question the resident just asked.
  List<String> _followUps(KnowledgeEntry e, String asked, int variant) {
    final item = e.display.toLowerCase();
    final pool = <String>[
      'Does it need rinsing first?',
      'Can the lid or cap go in too?',
      'What if it is dirty or wet?',
      'Is it fine to flatten it?',
      'Where is the nearest drop-off point?',
      'Does ${_article(item)} $item still need sorting?',
      'What should I avoid putting in with it?',
    ];
    final out = <String>[];
    for (var i = 0; i < pool.length && out.length < 3; i++) {
      final candidate = pool[(variant + i) % pool.length];
      if (candidate.toLowerCase() == asked.toLowerCase()) continue;
      if (out.contains(candidate)) continue;
      out.add(candidate);
    }
    return out;
  }

  /// Deterministic keyword routing for a follow-up question. Unknown questions
  /// get a neutral lead-in rather than an invented answer.
  String _answerFor(String question, KnowledgeEntry e) {
    final q = normaliseCocoLabel(question);
    if (q.contains('rins') || q.contains('wash') || q.contains('clean')) {
      return 'Yes — a quick rinse and shake dry is worth it, because clean '
          'material is what actually gets recovered.';
    }
    if (q.contains('dirty') || q.contains('wet') || q.contains('stain') ||
        q.contains('food') || q.contains('smell')) {
      return 'Scrape it out and rinse it if you can; if it stays soiled, the '
          'grey general-waste bin is the safer stream.';
    }
    if (q.contains('where') || q.contains('bin') || q.contains('which')) {
      return 'It goes to the ${e.bin}.';
    }
    if (q.contains('cap') || q.contains('lid') || q.contains('cover') ||
        q.contains('screw')) {
      return 'Keep the cap or lid with the item — loose small pieces fall '
          'through the sorting line.';
    }
    if (q.contains('flatten') || q.contains('crush') || q.contains('space')) {
      return 'Flattening is fine and saves collection space, as long as the '
          'item stays clean.';
    }
    if (q.contains('hazard') || q.contains('safe') || q.contains('danger') ||
        q.contains('fire')) {
      return e.hazardNote ??
          'Handle it exactly as this stream says and never mix it into another bin.';
    }
    if (q.contains('avoid') || q.contains('reuse') || q.contains('buy')) {
      return 'The step above that is avoiding it next time — reuse, refill or '
          'buy it loose where you can.';
    }
    return 'Here is what matters for this item:';
  }

  /// Last-resort answer: general waste, no item claim, no exception.
  ScanAdvice _safeAdvice(ScanQuery q) {
    final guidance = GUIDANCE[WasteCategory.Landfill]!;
    return ScanAdvice(
      headline: 'Check before you bin it',
      guidance: '${guidance.action} If you are unsure, hold the item back and '
          'confirm the stream with the collection team.',
      binAction: 'General waste — ${shortBinNames[WasteCategory.Landfill]}',
      impactNote: guidance.impact,
      followUps: const [
        'Which bin does this go in?',
        'Where is the nearest drop-off point?',
      ],
    );
  }
}

/// Whether the neural text backend may be selected.
///
/// **DEFAULT OFF — keep it off.** No quantized on-device text model is bundled
/// yet, so selecting the neural slot would only make the scanner worse:
/// [NeuralTinyLlmBackend] throws [UnimplementedError] by design. When such a
/// model is added it must ship *inside* the app and run fully offline; the heavy
/// or remote LLM path must never be required for a scan to produce guidance —
/// [TinyLlmBackend] is the contract every scan falls back to.
const bool kEnableNeuralTinyLlm = false;

/// Documented stub for the future on-device text model.
///
/// This slot is for a quantized text model shipped in `assets/` and run through
/// the same TFLite runtime the detectors use. It is intentionally empty: there
/// is no network fallback here and there never should be — a scan must keep
/// working with the radio off.
class NeuralTinyLlmBackend implements LlmBackend {
  const NeuralTinyLlmBackend();

  @override
  Future<ScanAdvice> advise(ScanQuery q) async {
    throw UnimplementedError(
        'NeuralTinyLlmBackend is a documented stub: no on-device text model is '
        'bundled yet. Keep kEnableNeuralTinyLlm false — TinyLlmBackend is the '
        'offline default and needs no network.');
  }
}

/// The one entry point the UI uses. Picks the backend and adapts the result; the
/// bundled offline engine answers unless the neural slot is switched on.
class LocalLlmService {
  LocalLlmService._();

  /// The bundled offline engine — the one that actually answers today.
  static const LlmBackend offlineBackend = TinyLlmBackend();

  /// Read through a getter so the const flag stays the single switch a future
  /// change has to flip, and so the picker cannot be folded away by the
  /// analyzer while the neural build does not exist.
  static bool get neuralTinyLlmEnabled => kEnableNeuralTinyLlm;

  /// Backend picker: [TinyLlmBackend] unless [kEnableNeuralTinyLlm] is on.
  static LlmBackend backend() =>
      neuralTinyLlmEnabled ? const NeuralTinyLlmBackend() : offlineBackend;

  /// Guidance for one scan (or one follow-up question). Never throws.
  static Future<ScanAdvice> advise(ScanQuery q) => backend().advise(q);
}

/// `plastic bottle` → `Plastic bottle`.
String _capitalise(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Indefinite article for a display name: `AA battery` → `an`, which keeps the
/// composed sentences readable without an English grammar engine.
String _article(String display) {
  if (display.isEmpty) return 'a';
  return 'aeiou'.contains(display[0].toLowerCase()) ? 'an' : 'a';
}

/// `Rinse it out` → `rinse it out` (so steps read as one sentence).
String _lowerFirst(String s) =>
    s.isEmpty ? s : '${s[0].toLowerCase()}${s.substring(1)}';
