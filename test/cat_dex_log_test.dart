/// Tests for the Cat Dex WO-03 surface: the empty-shelf copy + CTA, the
/// shared cat-catch gate, `itemLabel` JSON tolerance, tier labels and
/// pluralisation at 0/1/3/4/10, the log-a-sighting flow, and idempotent
/// share-to-board (one post per sighting, repeat share says so and still
/// navigates).
///
/// Both stores take an injectable storage directory and the log screen takes
/// `pickPhoto` / `analyse` seams, so nothing here touches `path_provider`,
/// `image_picker` or any other platform channel. Photos are generated in
/// memory: no fixtures, no network, no real personal data — precinct labels
/// only.
///
/// Run: `flutter test test/cat_dex_log_test.dart`
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:township_of_tomorrow/cat_dex/cat_catch_gate.dart';
import 'package:township_of_tomorrow/cat_dex/cat_dex_models.dart';
import 'package:township_of_tomorrow/cat_dex/cat_dex_screen.dart';
import 'package:township_of_tomorrow/cat_dex/cat_dex_store.dart';
import 'package:township_of_tomorrow/cat_dex/log_sighting_screen.dart';
import 'package:township_of_tomorrow/cat_dex/sticker_cutter.dart';
import 'package:township_of_tomorrow/community_board/board_store.dart';
import 'package:township_of_tomorrow/types.dart';

/// A synthetic RGBA frame: a deterministic gradient, opaque throughout.
Uint8List _photo({int width = 96, int height = 72}) {
  final im = img.Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      im.setPixelRgba(x, y, (x * 2) % 256, (y * 3) % 256, 128, 255);
    }
  }
  return img.encodePng(im);
}

DetectedObject _box(String label, double confidence) => DetectedObject(
      label: label,
      confidence: confidence,
      category: RecycleCategory.trash,
      wasteRelevant: false,
      x1: 10,
      y1: 8,
      x2: 50,
      y2: 40,
    );

CatSighting _sighting(String id, {String itemLabel = ''}) => CatSighting(
      id: id,
      label: 'cat',
      itemLabel: itemLabel,
      name: catDexNameFor(id),
      capturedAt: DateTime.utc(2026, 10, 14, 9, 30),
      precinct: 'Precinct 7',
      source: 'camera',
      originalPath: '/tmp/${id}_src.png',
      stickerPath: '/tmp/$id.png',
    );

/// A [StickerCutter] that skips the filesystem: same return shape, no writes.
class _FakeCutter extends StickerCutter {
  final String dirPath;
  _FakeCutter(this.dirPath) : super(storageDir: Directory(dirPath));

  @override
  Future<CatSighting> catchCat({
    required Uint8List imageBytes,
    required double boxX,
    required double boxY,
    required double boxW,
    required double boxH,
    required String label,
    required String precinct,
    required String source,
    String? id,
    String? name,
    DateTime? capturedAt,
      }) async =>
      CatSighting(
        id: id ?? 'cat-${DateTime.now().microsecondsSinceEpoch}',
        label: label,
        name: name ?? catDexNameFor(id ?? 'cat-fake'),
        capturedAt: capturedAt ?? DateTime.now(),
        precinct: precinct,
        source: source,
        originalPath: '$dirPath/src.png',
        stickerPath: '$dirPath/sticker.png',
      );
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cat_dex_log_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<CatDexStore> freshStore() async {
    final store = CatDexStore(storageDir: tmp);
    await store.load();
    return store;
  }

  group('CatSighting.itemLabel', () {
    test('round-trips through jsonEncode/jsonDecode', () {
      final before = _sighting('cat-item', itemLabel: 'stray cat');
      final after = CatSighting.fromJson(
          (jsonDecode(jsonEncode(before.toJson())) as Map).cast<String, dynamic>());

      expect(after.itemLabel, 'stray cat');
      expect(after.displayItemLabel, 'stray cat');
      expect(after.toJson()['itemLabel'], 'stray cat');
    });

    test('tolerates a missing itemLabel key in older files', () {
      final j = _sighting('cat-old').toJson()..remove('itemLabel');
      final after = CatSighting.fromJson(j);
      expect(after.itemLabel, '');
      expect(after.displayItemLabel, 'cat'); // falls back to label
    });

    test('addSighting files the given itemLabel', () async {
      final store = await freshStore();
      await store.addSighting(
        id: 'cat-log-1',
        label: 'cat',
        itemLabel: 'stray cat',
        precinct: 'Precinct 7',
        source: 'camera roll',
        originalPath: '${tmp.path}/src.png',
        stickerPath: '${tmp.path}/sticker.png',
      );
      final filed = store.byId('cat-log-1')!;
      expect(filed.itemLabel, 'stray cat');
      expect(filed.displayItemLabel, 'stray cat');
      expect(filed.source, 'camera roll');

      // Omitting itemLabel keeps the old behaviour: empty, falls back.
      await store.addSighting(
        id: 'cat-log-2',
        label: 'kitten',
        precinct: 'Precinct 7',
        source: 'scan',
        originalPath: 'a',
        stickerPath: 'b',
      );
      expect(store.byId('cat-log-2')!.displayItemLabel, 'kitten');
    });
  });

  group('CatCatchGate', () {
    test('catBox picks the highest-confidence cat, not the first entry', () {
      final box = CatCatchGate.catBox([
        _box('bottle', 0.99),
        _box('cat', 0.4),
        _box('Cat', 0.7),
        _box('dog', 0.9),
      ]);
      expect(box, isNotNull);
      expect(box!.confidence, 0.7);
    });

    test('catchableCatBox gates confidence and competing animals', () {
      // No cat at all.
      expect(CatCatchGate.catchableCatBox([_box('dog', 0.9)]), isNull);
      // Confident cat, no competitor: catchable.
      expect(CatCatchGate.catchableCatBox([_box('cat', 0.6)]), isNotNull);
      // Sub-floor cat: not catchable.
      expect(
          CatCatchGate.catchableCatBox([_box('cat', 0.08)]), isNull);
      // A higher-scoring competitor is a dog photo, not a cat photo.
      expect(CatCatchGate.catchableCatBox(
          [_box('cat', 0.26), _box('dog', 0.95)]), isNull);
      // A tie keeps the card.
      expect(CatCatchGate.catchableCatBox(
          [_box('cat', 0.5), _box('dog', 0.5)]), isNotNull);
    });

    test('scaleToOriginal passes small captures through and scales big ones',
        () {
      expect(CatCatchGate.scaleToOriginal(480, 640), 1.0);
      expect(CatCatchGate.scaleToOriginal(640, 640), 1.0);
      expect(CatCatchGate.scaleToOriginal(1280, 960), 2.0);
      expect(CatCatchGate.scaleToOriginal(2560, 1920), 4.0);
    });
  });

  group('tier label and pluralisation', () {
    Future<CatDexStore> storeWith(int cats) async {
      final store = await freshStore();
      for (var i = 0; i < cats; i++) {
        await store.addSighting(
          id: 'cat-tier-$i',
          label: 'cat',
          precinct: 'Precinct 7',
          source: 'camera',
          originalPath: 'a',
          stickerPath: 'b',
        );
      }
      return store;
    }

    test('Cat Level <index> at 0/1/3/4/10', () async {
      expect(catDexLevelLabel(await storeWith(0)), 'Cat Level 0');
      expect(catDexLevelLabel(await storeWith(1)), 'Cat Level 1');
      expect(catDexLevelLabel(await storeWith(3)), 'Cat Level 2');
      expect(catDexLevelLabel(await storeWith(4)), 'Cat Level 3');
      expect(catDexLevelLabel(await storeWith(10)), 'Cat Level 4');
    });

    test("1 cat unlocks vs N cats unlock, and the max-tier line", () async {
      expect(catDexTierLine(await storeWith(0)), '1 cat unlocks the next tier');
      expect(catDexTierLine(await storeWith(1)),
          '2 cats unlock the next tier');
      expect(catDexTierLine(await storeWith(2)), '1 cat unlocks the next tier');
      expect(catDexTierLine(await storeWith(3)), '1 cat unlocks the next tier');
      expect(catDexTierLine(await storeWith(4)),
          '6 cats unlock the next tier');
      expect(
          catDexTierLine(await storeWith(10)),
          'Maximum tier reached. The cats are pleased.');
    });
  });

  group('LogSightingScreen', () {
    // NOTE: widget tests run in the fake-async zone — never await real file IO
    // (e.g. freshStore()) there. The store is left unloaded: count/addSighting
    // work in memory and save() is a no-op without a file handle.

    testWidgets('no catchable cat shows the no-cat hint', (tester) async {
      final store = CatDexStore(storageDir: tmp);
      var analysed = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LogSightingScreen(
            store: store,
            precinct: 'Precinct 7',
            pickPhoto: () async => File('${tmp.path}/photo.png'),
            analyse: (path) async {
              analysed++;
              return [_box('dog', 0.92)];
            },
          ),
        ),
      ));

      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();

      expect(analysed, 1);
      expect(
          find.text('No cat found in that photo. Try a clearer shot.'),
          findsOneWidget);
      expect(store.count, 0);
      expect(find.text('Added to the Dex'), findsNothing);
    });

    testWidgets('a throwing pipeline shows the escape message', (tester) async {
      final store = CatDexStore(storageDir: tmp);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LogSightingScreen(
            store: store,
            precinct: 'Precinct 7',
            pickPhoto: () async => File('${tmp.path}/photo.png'),
            analyse: (path) async => throw StateError('detector died'),
          ),
        ),
      ));

      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();

      expect(find.text('The cat slipped away — try another photo'), findsOneWidget);
      expect(store.count, 0);
    });

    testWidgets('a cat photo is filed with itemLabel and shows Added to the Dex',
        (tester) async {
      final store = CatDexStore(storageDir: tmp);
      // Real bytes so the pipeline-copy decode inside the flow has something
      // to scale; written synchronously (sync IO is safe in the test zone).
      final photo = File('${tmp.path}/cat_photo.png')
        ..writeAsBytesSync(_photo());

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LogSightingScreen(
            store: store,
            cutter: _FakeCutter('${tmp.path}/cut'),
            precinct: 'Precinct 7',
            pickPhoto: () async => photo,
            analyse: (path) async => [_box('cat', 0.88)],
            // Bytes straight from memory: no real IO in the fake-async zone.
            readBytes: (f) async => _photo(),
          ),
        ),
        routes: {
          '/cat-dex': (_) =>
              const Scaffold(body: Text('cat-dex-route-stub')),
        },
      ));

      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();

      expect(find.text('Added to the Dex'), findsOneWidget);
      expect(find.text('View Cat Dex'), findsOneWidget);
      expect(store.count, 1);
      final filed = store.sightings.first;
      expect(filed.itemLabel, 'stray cat');
      expect(filed.source, 'camera roll');
      expect(filed.precinct, 'Precinct 7');

      await tester.tap(find.text('View Cat Dex'));
      await tester.pumpAndSettle();
      expect(find.text('cat-dex-route-stub'), findsOneWidget);
    });

    testWidgets('cancelling the picker leaves no message', (tester) async {
      final store = CatDexStore(storageDir: tmp);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LogSightingScreen(
            store: store,
            precinct: 'Precinct 7',
            pickPhoto: () async => null, // resident backed out
            analyse: (path) async => [_box('cat', 0.9)],
          ),
        ),
      ));

      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();

      expect(find.text('The cat slipped away — try another photo'), findsNothing);
      expect(find.text('Added to the Dex'), findsNothing);
      expect(store.count, 0);
    });
  });

  group('empty Dex + repeated share (widget)', () {
    testWidgets('empty Dex shows the board-40 copy and the CTA pushes the log flow',
        (tester) async {
      final store = CatDexStore(storageDir: tmp);
      final board = CommunityBoardStore(storageDir: tmp);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: CatDexScreen(store: store, board: board)),
      ));

      expect(find.text('The Dex is quiet'), findsOneWidget);
      expect(
          find.text(
              'Spot a stray cat on a scan run? Log the sighting to fill this shelf.'),
          findsOneWidget);
      expect(find.textContaining('Cat Level'), findsNothing);
      expect(find.text('Caught so far · newest first'), findsNothing);

      await tester.tap(find.text('Log a sighting'));
      await tester.pumpAndSettle();

      expect(find.byType(LogSightingScreen), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
    });

    testWidgets(
        'sharing twice adds one post, says Already shared, still navigates',
        (tester) async {
      final store = CatDexStore(storageDir: tmp);
      final board = CommunityBoardStore(storageDir: tmp);
      await store.addSighting(
        id: 'cat-share-twice',
        label: 'cat',
        itemLabel: 'stray cat',
        precinct: 'Precinct 7',
        source: 'camera roll',
        originalPath: '${tmp.path}/src.png',
        stickerPath: '${tmp.path}/sticker.png',
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: CatDexScreen(store: store, board: board)),
        routes: {
          '/board': (_) => const Scaffold(body: Text('board-route-stub')),
        },
      ));

      final baseline = board.postCount;

      // First share: posts once and leaves for the board.
      await tester.tap(find.byKey(const ValueKey('cat-sticker-cat-share-twice')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share sighting to board'));
      await tester.pumpAndSettle();

      expect(board.postCount, baseline + 1);
      expect(board.byId('cat-dex-cat-share-twice'), isNotNull);
      expect(find.text('Sighting shared to the community board'), findsOneWidget);
      expect(find.text('board-route-stub'), findsOneWidget);

      // Let the first SnackBar expire so the repeat message stands alone
      // (queued snackbars hide behind the current one's timer).
      await tester.pump(const Duration(seconds: 6));

      // Back to the Dex, open the sheet again, share the same sighting.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cat-sticker-cat-share-twice')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share sighting to board'));
      await tester.pumpAndSettle();

      // One post total, the repeat message, and the trip to the board again.
      expect(board.postCount, baseline + 1);
      expect(find.text('Already shared to the community board'), findsOneWidget);
      expect(find.text('board-route-stub'), findsOneWidget);
    });
  });
}
