/// Cat Dex domain types: one distributed cat, plus the deterministic names the
/// Cat Distribution System hands out.
///
/// Hand-written `toJson`/`fromJson` in the `lib/types.dart` style — `fromJson`
/// tolerates missing optional keys so older files keep loading. Everything here
/// is offline data: precinct labels only, never an address.
library;

/// The name pool. Twelve is enough to make a Dex feel populated while staying
/// short enough that a human can read the whole assignment list at once.
const List<String> kCatDexNames = [
  'Chairman Meow',
  'Purrsephone',
  'Meowser',
  'Catniss',
  'Fuzz Aldrin',
  'Clawdia',
  'Purrlock Holmes',
  'Sir Pounce',
  'Whiskers McFluff',
  'Duchess Fluffington',
  'Meowcolm',
  'Catpernicus',
];

/// Stable, platform-independent 32-bit FNV-1a hash of [value].
///
/// `String.hashCode` is not guaranteed to be stable across runs, and the Dex
/// needs the same id to produce the same name and the same sticker tilt after a
/// restart — so it hashes by hand.
int catDexHash(String value) {
  var h = 0x811c9dc5;
  for (var i = 0; i < value.length; i++) {
    h = (h ^ value.codeUnitAt(i)) & 0xffffffff;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// The fun name for [id]: same id in, same name out, forever.
String catDexNameFor(String id) =>
    kCatDexNames[catDexHash(id) % kCatDexNames.length];

/// One cat the Distribution System has assigned to this device.
class CatSighting {
  final String id;

  /// The detector's own label for the catch (`cat`, `kitten`, …).
  final String label;

  /// The human-facing item label filed with the catch (`stray cat`, …); may be
  /// empty on older sightings, in which case [displayItemLabel] falls back to
  /// [label].
  final String itemLabel;

  /// What the detail sheet shows: [itemLabel] when set, else the raw [label].
  String get displayItemLabel => itemLabel.isEmpty ? label : itemLabel;

  /// Deterministic fun name — see [catDexNameFor].
  final String name;
  final DateTime capturedAt;

  /// Precinct label only — never a street address.
  final String precinct;

  /// Where the bytes came from (`camera`, `gallery`, …): provenance, not data.
  final String source;

  /// Full photo the cat was found in, copied into the app documents dir.
  final String originalPath;

  /// The cut-out, ringed, tilted PNG the Dex grid shows.
  final String stickerPath;

  CatSighting({
    required this.id,
    required this.label,
    this.itemLabel = '',
    required this.name,
    required this.capturedAt,
    required this.precinct,
    required this.source,
    required this.originalPath,
    required this.stickerPath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'itemLabel': itemLabel,
        'name': name,
        'capturedAt': capturedAt.toIso8601String(),
        'precinct': precinct,
        'source': source,
        'originalPath': originalPath,
        'stickerPath': stickerPath,
      };

  static CatSighting fromJson(Map<String, dynamic> j) => CatSighting(
        id: j['id'] as String,
        label: (j['label'] ?? 'cat') as String,
        // Older files have no `itemLabel` key — default to empty so
        // [CatSighting.displayItemLabel] falls back to [label].
        itemLabel: (j['itemLabel'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        capturedAt: DateTime.parse(j['capturedAt'] as String),
        precinct: (j['precinct'] ?? '') as String,
        source: (j['source'] ?? '') as String,
        originalPath: (j['originalPath'] ?? '') as String,
        stickerPath: (j['stickerPath'] ?? '') as String,
      );
}
