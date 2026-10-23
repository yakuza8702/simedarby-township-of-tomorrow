/// Waste-stream decision layer — faithful Dart port of the legacy
/// `src/services/wasteClassifier.ts`, extended with the kNN evidence path.
///
/// Detection gives boxes and object names ("bottle", "cell phone", "banana");
/// this module turns them into one of the township's six streams plus the
/// guidance a resident needs. It stays a transparent keyword model on purpose:
/// every decision can be traced back to the label that produced it, and
/// anything below the confidence gate is handed back to the resident instead
/// of being asserted.
library;
import '../types.dart';

const GUIDANCE = <WasteCategory, StreamGuidance>{
  WasteCategory.Recyclable: StreamGuidance(
    WasteCategory.Recyclable,
    'Blue recycling bin (kitar semula)',
    'Empty and rinse the item, keep lids and caps with it, and place it loose — never bagged — in the blue bin.',
    'Clean, loose recyclables are the single biggest factor in whether a township\'s material is actually recovered rather than rejected at the sorting facility.',
  ),
  WasteCategory.Organic: StreamGuidance(
    WasteCategory.Organic,
    'Green organics bin or compost bay',
    'Drain liquids, remove any plastic wrapping, and add it to the organics bin or your precinct compost bay.',
    'Food and garden waste is the heaviest fraction of household waste; composting it cuts landfill methane and returns nutrients to township soil.',
  ),
  WasteCategory.Landfill: StreamGuidance(
    WasteCategory.Landfill,
    'Grey general-waste bin',
    'This item has no recovery route today — place it in the grey bin and try to choose a reusable alternative next time.',
    'Every avoided landfill item delays the need for new disposal capacity and reduces collection weight across the precinct.',
  ),
  WasteCategory.Ewaste: StreamGuidance(
    WasteCategory.Ewaste,
    'E-waste drop-off point (do not bin)',
    'Wipe your data if it stores any, then take it to the township e-waste drop-off point — never the general bin.',
    'E-waste carries recoverable metals and hazardous elements; drop-off keeps both the value and the toxins out of landfill.',
  ),
  WasteCategory.Hazardous: StreamGuidance(
    WasteCategory.Hazardous,
    'Household hazardous waste drop-off',
    'Keep it in its original container, do not mix it with other waste, and take it to the household hazardous waste collection point.',
    'Batteries, bulbs, paints and chemicals contaminate an entire collection load when they leak — separating them protects everything else you recycle.',
  ),
  WasteCategory.Reusable: StreamGuidance(
    WasteCategory.Reusable,
    'Circular Hub — pass it on instead',
    'This item still has a useful life. List it on the Circular Hub rather than discarding it.',
    'Reuse displaces a new purchase and keeps the item out of the waste stream entirely — the highest-value outcome in the township loop.',
  ),
};

const MANUAL_CATEGORIES = WasteCategory.values;

class StreamRule {
  final WasteCategory category;
  final double weight;
  final List<String> keywords;
  const StreamRule(this.category, this.weight, this.keywords);
}

/// Keyword → stream table. Covers the COCO classes the detector can return plus
/// common items the ML Kit labeller and the kNN embedder name.
const RULES = <StreamRule>[
  StreamRule(WasteCategory.Recyclable, 1.0, [
    'bottle', 'water bottle', 'plastic bottle', 'glass bottle', 'wine glass',
    'cup', 'mug', 'glass', 'jar', 'tin', 'can', 'aluminium', 'aluminum',
    'metal', 'steel', 'iron', 'copper', 'carton', 'cardboard', 'paper',
    'newspaper', 'magazine', 'envelope', 'box', 'packaging', 'wrapper',
    'packet', 'plastic', 'pet', 'bowl', 'plate', 'tray', 'container',
    'lid', 'cap', 'fork', 'knife', 'spoon', 'cutlery', 'utensil',
    'canister', 'drum', 'sheet', 'tube', 'pipe', 'crate', 'basket',
    'pallet', 'jug', 'flask', 'thermos',
    'beverage', 'soda', 'soft drink', 'drink can', 'recyclable', 'recycling',
    'paper bag', 'cardboard box', 'packaging material', 'drinkware',
  ]),
  StreamRule(WasteCategory.Organic, 1.0, [
    'banana', 'apple', 'sandwich', 'orange', 'broccoli', 'carrot',
    'hot dog', 'pizza', 'donut', 'cake', 'potted plant', 'potted',
    'food', 'fruit', 'vegetable', 'vegetation', 'plant', 'leaf', 'leaves',
    'flower', 'grass', 'garden', 'compost', 'soil', 'peel', 'bread',
    'rice', 'noodle', 'coffee', 'tea', 'egg', 'meat', 'fish', 'bone',
    'shell', 'branch', 'wood', 'log', 'seed', 'corn', 'coconut',
    'leftover', 'meal', 'produce', 'herb',
    'flesh', 'rind', 'core', 'cooked', 'raw food', 'greens',
  ]),
  StreamRule(WasteCategory.Ewaste, 1.15, [
    'laptop', 'mouse', 'remote', 'keyboard', 'cell phone', 'tv',
    'microwave', 'oven', 'toaster', 'refrigerator', 'hair drier', 'clock',
    // NOTE: loose household batteries moved to Hazardous (leak risk) — see rule below.
    'charger', 'adapter', 'cable', 'cord', 'wire',
    'electronics', 'electronic', 'device', 'phone', 'mobile phone',
    'smartphone', 'computer', 'desktop', 'monitor', 'screen', 'television',
    'printer', 'scanner', 'router', 'modem', 'speaker', 'headphone',
    'earphone', 'earbud', 'camera', 'circuit', 'motherboard', 'chip',
    'hard drive', 'usb', 'power bank', 'console', 'tablet', 'radio',
    'appliance', 'kettle', 'blender', 'fan', 'vacuum', 'freezer',
    'washing machine', 'air conditioner', 'heater', 'drone',
    'gadget', 'powerbank', 'e-waste', 'ewaste', 'electronic waste',
    'hard disk', 'loudspeaker', 'home appliance', 'vacuum cleaner',
  ]),
  StreamRule(WasteCategory.Hazardous, 1.3, [
    'light bulb', 'bulb', 'lamp', 'fluorescent', 'paint', 'solvent',
    'thinner', 'pesticide', 'insecticide', 'herbicide', 'chemical', 'acid',
    'bleach', 'detergent', 'medicine', 'medication', 'pill', 'syringe',
    'needle', 'thermometer', 'aerosol', 'spray can', 'gas', 'cylinder',
    'oil', 'lubricant', 'antifreeze', 'asbestos', 'fire extinguisher',
    'nail polish', 'cosmetic',
    'hazardous', 'toxic', 'corrosive', 'flammable', 'mercury', 'lead-acid',
    'car battery', 'lithium', 'vape', 'e-cigarette', 'smoke detector',
    // loose household batteries: the cells leak and contaminate collection
    'battery', 'batteries', 'alkaline', 'zinc', 'button cell',
  ]),
  StreamRule(WasteCategory.Reusable, 0.95, [
    'book', 'chair', 'couch', 'bed', 'dining table', 'backpack', 'handbag',
    'suitcase', 'tie', 'umbrella', 'teddy bear', 'scissors', 'sports ball',
    'skateboard', 'surfboard', 'tennis racket', 'skis', 'snowboard',
    'frisbee', 'kite', 'baseball bat', 'baseball glove',
    'clothing', 'clothes', 'shirt', 'dress', 'trouser', 'jeans', 'jacket',
    'shoe', 'sneaker', 'boot', 'sandal', 'slipper', 'hat', 'cap', 'bag',
    'towel', 'blanket', 'curtain', 'fabric', 'textile', 'leather',
    'furniture', 'table', 'desk', 'shelf', 'cabinet', 'sofa', 'mattress',
    'notebook', 'toy', 'puzzle', 'game', 'sport', 'bicycle', 'bike',
    'ball', 'racket', 'tool', 'hammer', 'screwdriver', 'wrench', 'drill',
    'pot', 'pan', 'picture frame', 'vase', 'decoration', 'instrument',
    'guitar', 'piano', 'mirror', 'rug', 'carpet',
    'outerwear', 'coat', 'sweater', 'hoodie', 'jumper', 'skirt', 'sock',
    'scarf', 'pyjama', 'garment', 'wardrobe', 'donation', 'second-hand',
    'jewellery', 'watch', 'armchair', 'stool', 'bookcase', 'toy block',
  ]),
  StreamRule(WasteCategory.Landfill, 0.9, [
    'toothbrush', 'toilet', 'sink', 'tissue', 'tissue paper', 'tissue box',
    'napkin', 'paper towel',
    'toilet paper', 'straw', 'styrofoam', 'polystyrene', 'diaper', 'nappy',
    'sanitary', 'cigarette', 'mask', 'face mask', 'glove', 'bandage',
    'plaster', 'cotton', 'swab', 'toothpaste', 'razor', 'pen', 'marker',
    'crayon', 'rubber', 'sponge', 'ceramic', 'porcelain', 'pottery',
    'broken glass', 'dust', 'debris', 'rubble', 'concrete', 'brick',
    'tile', 'stone', 'sand', 'ash', 'cling film',
    'wet wipe', 'wipe', 'litter', 'disposable', 'non-recyclable', 'receipt',
    'sticker', 'wrapping paper', 'coffee cup', 'foam cup', 'broken',
  ]),
];

/// Exact-phrase stream overrides. A whole-image/kNN label that names the item
/// verbatim decides the stream for that label and suppresses the ambiguous
/// shorter tokens inside it ("tissue paper" contains "paper", but tissues are
/// never clean enough for the blue bin under most municipal rules).
const PHRASE_STREAMS = <String, WasteCategory>{
  'tissue paper': WasteCategory.Landfill,
  'tissue box': WasteCategory.Landfill,
  'kitchen towel': WasteCategory.Landfill,
  'paper towel': WasteCategory.Landfill,
  'loose battery': WasteCategory.Hazardous,
  'AA battery': WasteCategory.Hazardous,
  'AAA battery': WasteCategory.Hazardous,
  'button cell': WasteCategory.Hazardous,
  'car battery': WasteCategory.Hazardous,
  'banana peel': WasteCategory.Organic,
  'plastic bottle': WasteCategory.Recyclable,
  'aluminium can': WasteCategory.Recyclable,
  'cardboard box': WasteCategory.Recyclable,
  't-shirt': WasteCategory.Reusable,
};

/// Fallback headline when no label resolves to a general device name.
const unknownDevice = 'Unknown device';

/// General-device aliases: raw detector / ML Kit / kNN label text → the
/// canonical general name shown as the scan headline ("laptop", "notebook"
/// and "macbook" collapse to one headline each). Labels outside this table
/// are not device names.
const deviceNameAliases = <String, String>{
  'laptop': 'Laptop',
  'notebook': 'Laptop',
  'macbook': 'Laptop',
  'phone': 'Smartphone',
  'cell phone': 'Smartphone',
  'mobile': 'Smartphone',
  'smartphone': 'Smartphone',
  'battery': 'Battery',
  'batteries': 'Battery',
  'powerbank': 'Power bank',
  'power bank': 'Power bank',
  'charger': 'Charger',
  'adapter': 'Charger',
  'cable': 'Cable',
  'keyboard': 'Keyboard',
  'mouse': 'Mouse',
  'monitor': 'Monitor',
  'screen': 'Monitor',
  'tv': 'TV',
  'television': 'TV',
  'remote': 'Remote',
  'speaker': 'Speaker',
  'printer': 'Printer',
  'fridge': 'Fridge',
  'refrigerator': 'Fridge',
  'microwave': 'Microwave',
  'fan': 'Fan',
  'kettle': 'Kettle',
  'washing machine': 'Washing machine',
  'bulb': 'Bulb',
  'lamp': 'Bulb',
  'gadget': 'Gadget',
};

/// Normalise one raw label to its canonical general device name ('' when
/// the label is not an aliased device).
String normalizeDeviceName(String raw) {
  final key = raw.trim().toLowerCase();
  if (key.isEmpty) return '';
  return deviceNameAliases[key] ?? '';
}

/// Street furniture the detector can see — hazard-report subjects, not waste.
const INFRASTRUCTURE_LABELS = [
  'fire hydrant', 'traffic light', 'stop sign', 'parking meter', 'bench',
  'toilet', 'sink', 'potted plant', 'street sign', 'manhole',
];

class Evidence {
  final int count;
  final double best;
  const Evidence(this.count, this.best);
}

class ClassificationOutcome {
  final WasteCategory? category;
  final int confidence; // 0..100
  final bool needsConfirmation;
  final List<WasteCategory> candidates;
  final String? matchedFrom;
  final bool infrastructure;
  final Map<WasteCategory, double> scores;
  final Evidence? evidence;
  final String knnItem; // kNN item identity, if any
  final String deviceName; // general device name for the scan headline

  const ClassificationOutcome({
    required this.category,
    required this.confidence,
    required this.needsConfirmation,
    required this.candidates,
    required this.infrastructure,
    required this.scores,
    required this.knnItem,
    required this.deviceName,
    this.matchedFrom,
    this.evidence,
  });
}

const CONFIDENCE_GATE = 55;
const MARGIN_GATE = 12;
const SINGLE_LABEL_GATE = 0.7;

const GARMENT_KEYWORDS = [
  'outerwear', 'jacket', 'coat', 'sweater', 'hoodie', 'jumper', 'shirt',
  't-shirt', 'dress', 'jeans', 'trouser', 'pant', 'skirt', 'sock', 'scarf',
  'pyjama', 'garment', 'clothing', 'clothes', 'outfit', 'wardrobe', 'sleeve',
  'collar', 'denim',
];

double strongestLabel(List<VisionLabel> labels) {
  var best = 0.0;
  for (final l in labels) {
    if (l.text == '???' || l.text.startsWith('object #')) continue;
    if (l.confidence > best) best = l.confidence;
  }
  return best;
}

/// Raw text of the strongest real label — skips placeholders ('???',
/// 'object #…') and the kNN identity, which the headline derives from
/// first. Feeds device-name derivation step two.
String strongestLabelText(List<VisionLabel> labels, {String exclude = ''}) {
  var best = '';
  var bestStrength = 0.0;
  for (final l in labels) {
    final text = l.text.toLowerCase();
    if (text == '???' || text.startsWith('object #')) continue;
    if (l.text == exclude) continue;
    if (l.confidence > bestStrength) {
      bestStrength = l.confidence;
      best = l.text;
    }
  }
  return best;
}

/// Headline device-name derivation: kNN item identity first, then the
/// strongest detector / ML Kit label, then keyword evidence, else
/// 'Unknown device'. Each raw label is normalised through
/// [deviceNameAliases]; the first source that resolves to a canonical
/// general name wins.
String deriveDeviceName({
  required String knnItem,
  required String strongestLabel,
  required String? matchedFrom,
}) {
  for (final raw in [knnItem, strongestLabel, matchedFrom]) {
    if (raw == null || raw.isEmpty) continue;
    final name = normalizeDeviceName(raw);
    if (name.isNotEmpty) return name;
  }
  return unknownDevice;
}

class _Scored {
  final Map<WasteCategory, double> scores;
  final String? matchedFrom;
  final Map<WasteCategory, Evidence> support;
  _Scored(this.scores, this.matchedFrom, this.support);
}

_Scored _scoreLabels(List<VisionLabel> labels, {bool suppressGarments = false}) {
  final scores = <WasteCategory, double>{};
  final support = <WasteCategory, Evidence>{};
  String? matchedFrom;
  var matchedStrength = 0.0;

  for (final label in labels) {
    final text = label.text.toLowerCase();
    if (text == '???' || text.startsWith('object #')) continue;
    final strength = label.confidence.clamp(0.0, 1.0);
    // Exact-phrase override: verbatim item names outrank their substrings.
    final phraseCategory = PHRASE_STREAMS[text];
    if (phraseCategory != null) {
      scores[phraseCategory] =
          (scores[phraseCategory] ?? 0) + strength * 2.0;
      final seen = support[phraseCategory];
      support[phraseCategory] = Evidence(
        (seen?.count ?? 0) + 2,
        (seen == null || seen.best < strength) ? strength : seen.best,
      );
      if (strength > matchedStrength) {
        matchedStrength = strength;
        matchedFrom = label.text;
      }
      continue;
    }
    final garmentOnly = suppressGarments &&
        GARMENT_KEYWORDS.any(text.contains) &&
        !RULES.any((rule) => rule.keywords
            .any((k) => !GARMENT_KEYWORDS.contains(k) && text.contains(k)));
    if (garmentOnly) continue;
    for (final rule in RULES) {
      if (!rule.keywords.any(text.contains)) continue;
      scores[rule.category] = (scores[rule.category] ?? 0) + strength * rule.weight;
      final seen = support[rule.category];
      support[rule.category] = Evidence(
        (seen?.count ?? 0) + 1,
        (seen == null || seen.best < strength) ? strength : seen.best,
      );
      if (strength > matchedStrength) {
        matchedStrength = strength;
        matchedFrom = label.text;
      }
    }
  }
  return _Scored(scores, matchedFrom, support);
}

ClassificationOutcome _decide(
  _Scored scored, {
  required bool infrastructure,
  double boost = 0,
  required double topLabelStrength,
  required String knnItem,
  required String deviceName,
  bool knnTrust = false,
}) {
  final ranked = scored.scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  if (ranked.isEmpty) {
    return ClassificationOutcome(
      category: null,
      confidence: 0,
      needsConfirmation: true,
      candidates: MANUAL_CATEGORIES,
      infrastructure: infrastructure,
      scores: scored.scores,
      knnItem: knnItem,
      deviceName: deviceName,
    );
  }

  final best = ranked[0];
  final second = ranked.length > 1 ? ranked[1].value : 0.0;
  final total = ranked.fold(0.0, (s, e) => s + e.value);
  final margin = total > 0 ? (best.value - second) / total : 0.0;

  final strongest = topLabelStrength.clamp(0.0, 1.0) * 100;
  final mass = (best.value > 1.25 ? 1.25 : best.value) * 100;
  final competition = ranked.length > 1 ? 0.6 + 0.4 * margin : 1.0;
  final score = (strongest < mass + 10 ? strongest : mass + 10) * competition;
  var confidence = (score * (1 - boost * 0.35) + boost * 100 * 0.35).round();
  if (confidence > 100) confidence = 100;

  final winning = scored.support[best.key];
  final enoughEvidence = (winning?.count ?? 0) >= 2 || (winning?.best ?? 0) >= SINGLE_LABEL_GATE;
  final confident = knnTrust
      // The kNN item identity is an independent on-device signal; the margin
      // gate exists for keyword-only scans where weak labels gang up.
      ? (confidence >= 50 && (winning?.best ?? 0) >= SINGLE_LABEL_GATE)
      : (confidence >= CONFIDENCE_GATE &&
          (ranked.length == 1 || margin * 100 >= MARGIN_GATE) &&
          enoughEvidence);

  return ClassificationOutcome(
    category: confident ? best.key : null,
    confidence: confidence,
    needsConfirmation: !confident,
    candidates: ranked.take(3).map((e) => e.key).toList(),
    matchedFrom: scored.matchedFrom,
    infrastructure: infrastructure,
    scores: scored.scores,
    evidence: winning,
    knnItem: knnItem,
    deviceName: deviceName,
  );
}

/// Classify ML Kit labels (whole-image fallback path).
ClassificationOutcome classifyLabels(List<VisionLabel> labels,
    {String knnItem = '', bool knnTrust = false}) {
  final s = _scoreLabels(labels);
  return _decide(s,
      infrastructure: false,
      topLabelStrength: strongestLabel(labels),
      knnItem: knnItem,
      deviceName: deriveDeviceName(
        knnItem: knnItem,
        strongestLabel: strongestLabelText(labels, exclude: knnItem),
        matchedFrom: s.matchedFrom),
      knnTrust: knnTrust);
}

/// Classify detector boxes, optionally fused with whole-image extra labels
/// (ML Kit when boxes were not decisive, and the kNN item identity).
ClassificationOutcome classifyDetections(
  List<Detection> detections,
  List<VisionLabel> extraLabels, {
  String knnItem = '',
  bool knnTrust = false,
}) {
  final confident = detections.where((d) => d.score >= 0.3).toList();
  final primary = confident.isEmpty ? null : confident.first;

  // With a trusted kNN item identity, the whole-image labels describe the
  // SCENE around the item (the table under a laptop) — they are context,
  // not the subject. Halve them; keep detector boxes at full weight.
  final contextScale = knnTrust ? 0.5 : 1.0;
  final labels = <VisionLabel>[
    for (var i = 0; i < confident.length; i++)
      VisionLabel(confident[i].label, i == 0 ? confident[i].score : confident[i].score * 0.6),
    for (final l in extraLabels)
      // the trusted kNN item label itself keeps its cited strength
      (l.text == knnItem) ? l : VisionLabel(l.text, l.confidence * contextScale),
  ];

  final personSubject = confident.any((d) => d.label.toLowerCase().contains('person')) ||
      extraLabels.any((l) => l.text.toLowerCase().contains('person')) ||
      // A trusted kNN item identity beats whole-image garment chatter: the
      // labeller names the clothing of whoever holds the item (the banana
      // peel photo scored "Outerwear 84%").
      knnTrust;
  final s = _scoreLabels(labels, suppressGarments: personSubject);
  final infrastructure = primary != null &&
      INFRASTRUCTURE_LABELS.any(primary.label.toLowerCase().contains);

  return _decide(
    s,
    infrastructure: infrastructure,
    boost: primary?.score ?? 0,
    topLabelStrength: strongestLabel(labels),
    knnItem: knnItem,
    deviceName: deriveDeviceName(
      knnItem: knnItem,
      strongestLabel: strongestLabelText(labels, exclude: knnItem),
      matchedFrom: s.matchedFrom),
    knnTrust: knnTrust,
  );
}

/// Turn detector boxes into the label shape the classifier understands.
List<VisionLabel> detectionsToLabels(List<Detection> detections) =>
    [for (final d in detections) VisionLabel(d.label, d.score)];
