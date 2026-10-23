/// Cat Dex state: the cats this device has caught, and the level that comes
/// with them.
///
/// Follows the hand-rolled persistence pattern of `lib/store/collection_store.dart`
/// and the community board store: a single JSON file in the app documents dir,
/// written whole on every change. The directory is injectable so unit tests can
/// point at a temp dir instead of the `path_provider` plugin (which is
/// unavailable in a plain VM test).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'cat_dex_models.dart';

class CatDexStore extends ChangeNotifier {
  /// [storageDir] `null` (the app default) → `getApplicationDocumentsDirectory()`.
  CatDexStore({this._storageDir});

  static const fileName = 'cat_dex.json';

  /// Ascending count cut-offs, one per tier; index 0 is the empty-Dex tier.
  /// 3 cats is already Level 2 — the tiers are meant to arrive early.
  static const List<int> levelThresholds = [0, 1, 3, 4, 10];

  /// Tier titles by count, parallel to [levelThresholds]:
  /// 0 → Awaiting assignment · 1 → Assigned · 3 → Certified Cat Person ·
  /// 4 → Cat Distribution Hub · 10 → Final Boss of Cats.
  ///
  /// The banner itself leads with the numeric label (`Cat Level <index>`,
  /// see [CatDexScreen]); these titles remain the store-level tier names.
  static const List<String> levelTitles = [
    'Awaiting assignment',
    'Assigned',
    'Certified Cat Person',
    'Cat Distribution Hub',
    'Final Boss of Cats',
  ];

  /// The tier a Dex holding [count] cats has reached.
  static int levelIndexFor(int count) {
    var idx = 0;
    for (var i = 0; i < levelThresholds.length; i++) {
      if (count >= levelThresholds[i]) idx = i;
    }
    return idx;
  }

  /// The tier title for [count] — the string the level banner shows.
  static String levelTitleFor(int count) => levelTitles[levelIndexFor(count)];

  /// Deterministic name for [id]; exposed here so callers need one import.
  static String nameFor(String id) => catDexNameFor(id);

  final Directory? _storageDir;
  final List<CatSighting> _sightings = [];
  File? _file;
  bool _loaded = false;

  List<CatSighting> get sightings => List.unmodifiable(_sightings);
  int get count => _sightings.length;

  /// The current tier title (see [levelTitles]).
  String get level => levelTitleFor(count);

  /// The current tier number, `0..levelTitles.length - 1`.
  int get levelIndex => levelIndexFor(count);

  /// Count at which the next tier unlocks, or `null` at the top tier.
  int? get nextLevelCount =>
      levelIndex + 1 < levelThresholds.length ? levelThresholds[levelIndex + 1] : null;

  /// Cats still needed for the next tier (`1..`), or `null` at the top tier.
  ///
  /// By construction [nextLevelCount] is strictly above [count] whenever it is
  /// non-null (the level index is the maximal threshold already reached).
  int? get catsToNextLevel {
    final next = nextLevelCount;
    return next == null ? null : next - count;
  }

  /// `0..1` progress towards [nextLevelCount]; `1` once maxed out.
  double get levelProgress {
    final next = nextLevelCount;
    if (next == null) return 1;
    final base = levelThresholds[levelIndex];
    if (next <= base) return 1;
    return ((count - base) / (next - base)).clamp(0.0, 1.0);
  }

  bool get loaded => _loaded;

  CatSighting? byId(String id) {
    for (final s in _sightings) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Read `cat_dex.json`; with no file yet the Dex simply starts empty.
  Future<void> load() async {
    final dir = _storageDir ?? await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/$fileName');
    if (await _file!.exists()) {
      try {
        final list = (jsonDecode(await _file!.readAsString()) as List)
            .cast<Map<String, dynamic>>();
        _sightings
          ..clear()
          ..addAll([for (final j in list) CatSighting.fromJson(j)]);
      } catch (e) {
        debugPrint('TWP:ERROR cat dex load: $e');
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> save() async {
    if (_file == null) return;
    await _file!.writeAsString(jsonEncode([for (final s in _sightings) s.toJson()]));
  }

  /// Remove every sighting, leaving the Dex empty — the demo-data reset path,
  /// mirroring `CollectionStore.clearAll` / `CommunityBoardStore.clearAll`.
  Future<void> clearAll() async {
    _sightings.clear();
    await save();
    notifyListeners();
  }

  /// Newest catch first, matching the collection log's insertion order.
  ///
  /// [id] and [name] are only passed by callers that already have them (the
  /// sticker cutter does); the name always comes from [catDexNameFor] unless
  /// given. Re-adding a known [id] returns the stored sighting untouched.
  Future<CatSighting> addSighting({
    required String label,
    required String precinct,
    required String source,
    required String originalPath,
    required String stickerPath,
    String? itemLabel,
    DateTime? capturedAt,
    String? id,
    String? name,
  }) async {
    final sightingId = id ?? 'cat-${DateTime.now().microsecondsSinceEpoch}';
    final existing = byId(sightingId);
    if (existing != null) return existing;
    final sighting = CatSighting(
      id: sightingId,
      label: label,
      itemLabel: itemLabel ?? '',
      name: name ?? catDexNameFor(sightingId),
      capturedAt: capturedAt ?? DateTime.now(),
      precinct: precinct,
      source: source,
      originalPath: originalPath,
      stickerPath: stickerPath,
    );
    _sightings.insert(0, sighting);
    await save();
    notifyListeners();
    return sighting;
  }
}
