/// Demo dataset: a deterministic seed and a one-click reset.
///
/// SYNTHETIC DATA generated for this prototype — not real resident data. The
/// seed writes the four scenarios from the demo script (dumped furniture,
/// broken lamp post, bin overflow, water pooling) as hazard reports across
/// three precincts, plus hub listings, collection entries, Cat Dex sightings
/// and one demo community-board post with a fixed id.
///
/// Two safety properties:
///  * **Idempotent per store** — a store is only filled while its demo
///    collection is empty, and the board post is added through the board's
///    id-idempotent `addPost`, so pressing "Load demo data" twice never
///    doubles anything.
///  * **`includeMedia: false`** (the test configuration) skips every
///    file-backed item — hub listings, collection entries and Cat Dex
///    sightings all reference generated photos/stickers under
///    `<docs>/demo` — so a plain VM test writes no media and calls no
///    plugins. Demo collection entries additionally stay off the Go core's
///    pHash channel entirely (see [demoPhotoHash]).
///
/// Stores are injectable for tests; the defaults resolve through
/// `App.instance` (main.dart), the established optional-injection pattern.
library;

import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../cat_dex/cat_dex_store.dart';
import '../cat_dex/sticker_cutter.dart';
import '../community_board/board_models.dart';
import '../community_board/board_store.dart';
import '../main.dart' show App;
import '../store/collection_store.dart';
import '../store/township_store.dart';
import '../types.dart';

/// Totals observed after a [DemoData.seed] or [DemoData.reset], ready for the
/// screen's summary SnackBar and counts card.
class DemoCounts {
  final int reports;
  final int hubListings;
  final int collection;
  final int cats;
  final int boardPosts;

  const DemoCounts({
    required this.reports,
    required this.hubListings,
    required this.collection,
    required this.cats,
    required this.boardPosts,
  });

  @override
  String toString() =>
      'DemoCounts(reports: $reports, hubListings: $hubListings, '
      'collection: $collection, cats: $cats, boardPosts: $boardPosts)';
}

class DemoData {
  /// [includeMedia] `false` → seed only the media-free items (reports and the
  /// board post); `true` (the app default) also generates the hub photos,
  /// collection photos and Cat Dex stickers under `<docs>/demo`.
  DemoData({
    TownshipStore? township,
    CollectionStore? collection,
    CatDexStore? catDex,
    CommunityBoardStore? board,
    this.includeMedia = true,
  })  : township = township ?? App.instance.township,
        collection = collection ?? App.instance.collection,
        catDex = catDex ?? App.instance.catDex,
        board = board ?? App.instance.board;

  final TownshipStore township;
  final CollectionStore collection;
  final CatDexStore catDex;
  final CommunityBoardStore board;
  final bool includeMedia;

  /// Sub-directory under the app documents dir that holds every generated
  /// demo photo and sticker — demo media never leaves the documents dir.
  static const String demoDirName = 'docs/demo';

  /// Fixed id of the demo board post: `addPost` is idempotent by id, so the
  /// post lands exactly once no matter how often the seed runs.
  static const String demoBoardPostId = 'demo-post-01';

  /// Fill every empty demo collection; returns the totals afterwards.
  ///
  /// Safe to call repeatedly: each store is skipped when non-empty and the
  /// board post deduplicates by id.
  Future<DemoCounts> seed() async {
    if (!board.loaded) await board.load();
    if (!catDex.loaded) await catDex.load();

    if (township.reports.isEmpty) await _seedReports();

    if (includeMedia) {
      final demoDir = await _ensureDemoDir();
      if (township.hubListings.isEmpty) await _seedHubListings(demoDir);
      if (collection.entries.isEmpty) await _seedCollection(demoDir);
      if (catDex.sightings.isEmpty) await _seedCats(demoDir);
    }

    await board.addPost(_demoBoardPost());
    return _counts();
  }

  /// Clear every demo collection, restore the board's synthetic seed, then
  /// seed again; returns the totals afterwards.
  Future<DemoCounts> reset() async {
    await township.clearDemoContent();
    await collection.clearAll();
    if (!catDex.loaded) await catDex.load();
    await catDex.clearAll();
    if (!board.loaded) await board.load();
    await board.resetToSeed();
    return seed();
  }

  DemoCounts _counts() => DemoCounts(
        reports: township.reports.length,
        hubListings: township.hubListings.length,
        collection: collection.entries.length,
        cats: catDex.count,
        boardPosts: board.postCount,
      );

  /// The four demo-script scenarios: 2 submitted, 1 in review, 1 resolved,
  /// spread across three precincts. `addReport` stamps the report with the
  /// resident's own precinct unless one is passed — the demo pins each one
  /// so the operator views have cross-precinct content to show.
  Future<void> _seedReports() async {
    township.addReport(
      category: 'Illegal dumping',
      description: 'Dumped furniture on the nature strip — a two-seat couch '
          'and a bedside table left outside the community hall.',
      severity: 'medium',
      precinct: 'Precinct 1',
    );
    township.addReport(
      category: 'Street light out',
      description: 'Broken lamp post on the shared walkway — the third pole '
          'has been dark since Monday and the path is unlit after the last bus.',
      severity: 'high',
      precinct: 'Precinct 2',
    );
    final overflow = township.addReport(
      category: 'Bin overflowing',
      description: 'Bin overflow at the playground gate — the public bin is '
          'full and bags are stacked beside it.',
      severity: 'medium',
      precinct: 'Precinct 2',
    );
    final pooling = township.addReport(
      category: 'Water pooling',
      description: 'Water pooling across the path corner after rain — it '
          'drains slowly and blocks the accessible line past the drain.',
      severity: 'low',
      precinct: 'Precinct 3',
    );
    // 2 submitted (dumping, lamp post) → 1 in review → 1 resolved.
    township.triageReport(overflow.id);
    township.resolveReport(pooling.id);
  }

  Future<void> _seedHubListings(Directory demoDir) async {
    township.addHubListing(
      title: 'Sturdy bookshelf, free to a good home',
      description: 'Two-shelf timber bookshelf with a small scuff on top. '
          'Collect from the porch any time; first to reserve takes it.',
      photoPath: (await _writeDemoPhoto(demoDir, 'hub-bookshelf',
              const ColorTriple(0x4E, 0x34, 0x2E), const ColorTriple(0x8D, 0x6E, 0x63)))
          .path,
    );
    township.addHubListing(
      title: 'Box of plant pots and seed trays',
      description: 'A moving-box of clean plastic pots, seed trays and a '
          'bag of saucers. Great for the community garden or a balcony.',
      photoPath: (await _writeDemoPhoto(demoDir, 'hub-pots',
              const ColorTriple(0x1B, 0x5E, 0x20), const ColorTriple(0x66, 0xBB, 0x6A)))
          .path,
    );
  }

  Future<void> _seedCollection(Directory demoDir) async {
    final box = await _writeDemoPhoto(demoDir, 'collection-box',
        const ColorTriple(0xBF, 0x36, 0x0C), const ColorTriple(0xFF, 0x8A, 0x65));
    await collection.add(
      itemLabel: 'cardboard box',
      category: WasteCategory.Reusable,
      confidence: 92,
      photoPath: box.path,
      // Local hash instead of TownshipCore.pHashFile — see [demoPhotoHash]:
      // demo seeding stays off the MethodChannel (intentional seam; the Go
      // PHash panic that used to abort the app was fixed in core 0.2.1).
      photoHash: demoPhotoHash(box.bytes),
    );
    final bottle = await _writeDemoPhoto(demoDir, 'collection-bottle',
        const ColorTriple(0x0D, 0x47, 0xA1), const ColorTriple(0x64, 0xB5, 0xF6));
    await collection.add(
      itemLabel: 'plastic bottle',
      category: WasteCategory.Recyclable,
      confidence: 88,
      photoPath: bottle.path,
      photoHash: demoPhotoHash(bottle.bytes),
    );
  }

  /// Three demo sightings with fixed ids (so names and sticker tilts stay
  /// stable across resets); the sticker is cut from a locally generated
  /// source photo through the same pure cutter the camera flow uses.
  Future<void> _seedCats(Directory demoDir) async {
    const demos = [
      ('demo-cat-01', 'Precinct 1', ColorTriple(0x4A, 0x14, 0x8C), ColorTriple(0xCE, 0x93, 0xD8)),
      ('demo-cat-02', 'Precinct 2', ColorTriple(0x00, 0x60, 0x64), ColorTriple(0x4D, 0xD0, 0xE1)),
      ('demo-cat-03', 'Precinct 3', ColorTriple(0xE6, 0x51, 0x00), ColorTriple(0xFF, 0xB7, 0x4D)),
    ];
    final capturedAt = DateTime.utc(2026, 10, 10, 9);
    for (var i = 0; i < demos.length; i++) {
      final (id, precinct, base, accent) = demos[i];
      final source = _demoImage(base, accent);
      final srcBytes = img.encodePng(source);
      final stickerBytes = StickerCutter.cutStickerBytes(
        imageBytes: srcBytes,
        boxX: 0,
        boxY: 0,
        boxW: source.width.toDouble(),
        boxH: source.height.toDouble(),
        id: id,
      );
      final originalFile = File('${demoDir.path}/${id}_src.png');
      await originalFile.writeAsBytes(srcBytes, flush: true);
      final stickerFile = File('${demoDir.path}/$id.png');
      await stickerFile.writeAsBytes(stickerBytes, flush: true);
      await catDex.addSighting(
        id: id,
        label: 'cat',
        itemLabel: 'stray cat',
        precinct: precinct,
        source: 'demo',
        originalPath: originalFile.path,
        stickerPath: stickerFile.path,
        capturedAt: capturedAt.add(Duration(hours: i)),
      );
    }
  }

  /// The fixed-id demo board post — no media, so it seeds in every mode.
  BoardPost _demoBoardPost() => BoardPost(
        id: demoBoardPostId,
        title: 'Demo dataset loaded — synthetic content only',
        body: 'This post is part of the demo dataset generated for the '
            'prototype. Use Home → Demo data to reload the sample reports, '
            'listings and cats, or reset everything back to the synthetic '
            'board seed.',
        category: 'Events',
        precinct: 'Precinct A',
        authorLabel: 'Resident A-42',
        createdAt: DateTime.utc(2026, 10, 10, 9),
        isSynthetic: true,
      );

  Future<Directory> _ensureDemoDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/$demoDirName')
      ..createSync(recursive: true);
  }

  /// Write a deterministic two-tone demo PNG under `<docs>/demo` and return
  /// its full path plus the exact bytes written (so callers can derive a
  /// content hash without re-reading the file).
  Future<({String path, List<int> bytes})> _writeDemoPhoto(
      Directory demoDir, String name, ColorTriple base, ColorTriple accent) async {
    final file = File('${demoDir.path}/$name.png');
    final bytes = img.encodePng(_demoImage(base, accent));
    await file.writeAsBytes(bytes, flush: true);
    return (path: file.path, bytes: bytes);
  }

  /// Local stand-in for the Go core's `PHash` on demo collection photos:
  /// two 32-bit FNV-1a passes (different offset basis) over the exact PNG
  /// bytes, hex-encoded into the same 16 lowercase characters
  /// `townshipcore.PHash` returns, so `photoHash` keeps its format contract
  /// (and stays content-addressed: same photo → same hash, different demo
  /// item → different hash).
  ///
  /// Why not the real pHash: the OOB bug that used to make
  /// `townshipcore.PHash` panic for EVERY input (second DCT pass indexed `y`
  /// over the full
  /// 32-wide block into the 64-slot `coeffs` slice →
  /// `panic: index out of range [64] with length 64` → SIGABRT of the whole
  /// app via gomobile) was FIXED in Go core 0.2.1 (`for y := 0; y < 8`) —
  /// proven on-device, see `demo_evidence/F2_phash_fixed.txt` ('TWP:core
  /// 0.2.1'). The FNV-1a seam is kept INTENTIONALLY: demo seeding must never
  /// cross the platform channel, so the seed stays deterministic and
  /// plugin-free even in a plain VM test.
  static String demoPhotoHash(List<int> bytes) =>
      _fnv32(bytes, 0x811c9dc5) + _fnv32(bytes, 0x9747b28c);

  /// One 32-bit FNV-1a pass, zero-padded to 8 lowercase hex chars.
  static String _fnv32(List<int> bytes, int seed) {
    var h = seed;
    for (final b in bytes) {
      h ^= b;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  /// A deterministic 256×256 diagonal two-tone placeholder image — obviously
  /// synthetic, distinct per item, and byte-stable across runs.
  static img.Image _demoImage(ColorTriple base, ColorTriple accent) {
    const size = 256;
    final image = img.Image(width: size, height: size);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final t = (x + y) / (2 * (size - 1)); // 0..1 across the diagonal
        image.setPixelRgb(
          x,
          y,
          _lerp(base.r, accent.r, t),
          _lerp(base.g, accent.g, t),
          _lerp(base.b, accent.b, t),
        );
      }
    }
    return image;
  }

  static int _lerp(int a, int b, double t) => (a + (b - a) * t).round();
}

/// Plain RGB triple so the palette literals above stay readable `const`s.
class ColorTriple {
  final int r;
  final int g;
  final int b;
  const ColorTriple(this.r, this.g, this.b);
}
