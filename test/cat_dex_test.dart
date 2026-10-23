/// Unit + widget tests for the Cat Dex: JSON round-trips, level thresholds,
/// deterministic names, sticker cutting, and the share-to-board path.
///
/// Both stores take an injectable storage directory, so nothing here touches
/// `path_provider` or any other platform channel (unavailable in a plain VM
/// test) and nothing writes to the real documents dir. Images are generated
/// in memory: no fixtures, no network, no real personal data — precinct labels
/// only.
///
/// Run: `flutter test test/cat_dex_test.dart`
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:township_of_tomorrow/cat_dex/cat_dex_models.dart';
import 'package:township_of_tomorrow/cat_dex/cat_dex_screen.dart';
import 'package:township_of_tomorrow/cat_dex/cat_dex_store.dart';
import 'package:township_of_tomorrow/cat_dex/sticker_cutter.dart';
import 'package:township_of_tomorrow/community_board/board_store.dart';

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

bool _isPng(Uint8List bytes) =>
    bytes.length > 8 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4E &&
    bytes[3] == 0x47;

CatSighting _sighting(String id) => CatSighting(
      id: id,
      label: 'cat',
      itemLabel: 'stray cat',
      name: catDexNameFor(id),
      capturedAt: DateTime.utc(2026, 10, 14, 9, 30),
      precinct: 'Precinct 7',
      source: 'camera',
      originalPath: '/tmp/${id}_src.png',
      stickerPath: '/tmp/$id.png',
    );

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cat_dex_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<CatDexStore> freshStore() async {
    final store = CatDexStore(storageDir: tmp);
    await store.load();
    return store;
  }

  Future<CatSighting> addCat(CatDexStore store, String id) => store.addSighting(
        id: id,
        label: 'cat',
        precinct: 'Precinct 7',
        source: 'camera',
        originalPath: '${tmp.path}/${id}_src.png',
        stickerPath: '${tmp.path}/$id.png',
        capturedAt: DateTime.utc(2026, 10, 14, 9, 30),
      );

  group('CatSighting JSON', () {
    test('round-trips through jsonEncode/jsonDecode unchanged', () {
      final before = _sighting('cat-1001');
      final after = CatSighting.fromJson(
          (jsonDecode(jsonEncode(before.toJson())) as Map).cast<String, dynamic>());

      expect(after.id, before.id);
      expect(after.label, before.label);
      expect(after.itemLabel, before.itemLabel);
      expect(after.displayItemLabel, 'stray cat');
      expect(after.name, before.name);
      expect(after.capturedAt, before.capturedAt);
      expect(after.capturedAt.isUtc, isTrue);
      expect(after.precinct, before.precinct);
      expect(after.source, before.source);
      expect(after.originalPath, before.originalPath);
      expect(after.stickerPath, before.stickerPath);
      expect(after.toJson().keys.toSet(), before.toJson().keys.toSet());
    });

    test('tolerates missing optional keys so older files keep loading', () {
      final j = _sighting('cat-1002').toJson()
        ..remove('source')
        ..remove('precinct')
        ..remove('name')
        ..remove('itemLabel');
      final after = CatSighting.fromJson(j);
      expect(after.id, 'cat-1002');
      expect(after.source, '');
      expect(after.precinct, '');
      expect(after.name, '');
      expect(after.itemLabel, '');
      // An older sighting with no itemLabel shows the raw detector label.
      expect(after.displayItemLabel, after.label);
    });
  });

  group('CatDexStore', () {
    test('starts empty at the first tier', () async {
      final store = await freshStore();
      expect(store.count, 0);
      expect(store.sightings, isEmpty);
      expect(store.level, 'Awaiting assignment');
      expect(store.levelIndex, 0);
      expect(store.nextLevelCount, 1);
      expect(store.levelProgress, 0);
      expect(store.loaded, isTrue);
    });

    test('level titles follow the count thresholds', () {
      expect(CatDexStore.levelTitleFor(0), 'Awaiting assignment');
      expect(CatDexStore.levelTitleFor(1), 'Assigned');
      expect(CatDexStore.levelTitleFor(2), 'Assigned');
      expect(CatDexStore.levelTitleFor(3), 'Certified Cat Person');
      expect(CatDexStore.levelTitleFor(4), 'Cat Distribution Hub');
      expect(CatDexStore.levelTitleFor(9), 'Cat Distribution Hub');
      expect(CatDexStore.levelTitleFor(10), 'Final Boss of Cats');
      expect(CatDexStore.levelTitleFor(99), 'Final Boss of Cats');
    });

    test('addSighting walks the thresholds and reports the right level', () async {
      final store = await freshStore();
      await addCat(store, 'cat-1');
      expect(store.count, 1);
      expect(store.level, 'Assigned');
      expect(store.levelIndex, 1);
      expect(store.nextLevelCount, 3);
      expect(store.catsToNextLevel, 2);

      await addCat(store, 'cat-2');
      await addCat(store, 'cat-3');
      expect(store.count, 3);
      expect(store.level, 'Certified Cat Person');
      expect(store.levelIndex, 2);
      expect(store.nextLevelCount, 4);
      expect(store.catsToNextLevel, 1);

      await addCat(store, 'cat-4');
      expect(store.count, 4);
      expect(store.level, 'Cat Distribution Hub');
      expect(store.levelIndex, 3);
      expect(store.levelProgress, 0);

      for (var i = 5; i <= 10; i++) {
        await addCat(store, 'cat-$i');
      }
      expect(store.count, 10);
      expect(store.level, 'Final Boss of Cats');
      expect(store.levelIndex, CatDexStore.levelTitles.length - 1);
      expect(store.nextLevelCount, isNull);
      expect(store.catsToNextLevel, isNull);
      expect(store.levelProgress, 1);
    });

    test('newest sighting first and byId finds it', () async {
      final store = await freshStore();
      await addCat(store, 'cat-old');
      await addCat(store, 'cat-new');
      expect(store.sightings.first.id, 'cat-new');
      expect(store.byId('cat-old')?.id, 'cat-old');
      expect(store.byId('cat-nope'), isNull);
    });

    test('re-adding a known id is idempotent', () async {
      final store = await freshStore();
      final first = await addCat(store, 'cat-dup');
      final second = await store.addSighting(
        id: 'cat-dup',
        label: 'kitten',
        precinct: 'Precinct 9',
        source: 'gallery',
        originalPath: 'ignored',
        stickerPath: 'ignored',
      );
      expect(store.count, 1);
      expect(second.name, first.name);
      expect(second.precinct, 'Precinct 7');
    });

    test('persists to cat_dex.json and reloads it', () async {
      final store = await freshStore();
      await addCat(store, 'cat-persist');
      expect(File('${tmp.path}/${CatDexStore.fileName}').existsSync(), isTrue);

      final reloaded = await freshStore();
      expect(reloaded.count, 1);
      final s = reloaded.sightings.first;
      expect(s.id, 'cat-persist');
      expect(s.name, CatDexStore.nameFor('cat-persist'));
      expect(s.capturedAt, DateTime.utc(2026, 10, 14, 9, 30));
      expect(s.precinct, 'Precinct 7');
      expect(s.stickerPath, '${tmp.path}/cat-persist.png');
    });

    test('a corrupt file degrades to an empty Dex instead of throwing', () async {
      File('${tmp.path}/${CatDexStore.fileName}').writeAsStringSync('not json');
      final store = await freshStore();
      expect(store.count, 0);
      expect(store.level, 'Awaiting assignment');
    });
  });

  group('deterministic names', () {
    test('same id, same name — across the whole pool', () {
      for (var i = 0; i < 50; i++) {
        final id = 'cat-name-$i';
        expect(catDexNameFor(id), catDexNameFor(id));
        expect(CatDexStore.nameFor(id), catDexNameFor(id));
        expect(kCatDexNames, contains(catDexNameFor(id)));
      }
    });

    test('the pool is actually used', () {
      final names = {for (var i = 0; i < 400; i++) catDexNameFor('cat-$i')};
      expect(names.length, greaterThanOrEqualTo(6));
      expect(kCatDexNames.length, greaterThanOrEqualTo(12));
      expect(
          catDexHash('cat-1'), isNot(catDexHash('cat-2')),
          reason: 'the hand-rolled FNV-1a hash must separate adjacent ids');
    });
  });

  group('StickerCutter', () {
    test('cuts a non-empty RGBA PNG out of a synthetic frame', () {
      final bytes = StickerCutter.cutStickerBytes(
        imageBytes: _photo(),
        boxX: 20,
        boxY: 16,
        boxW: 40,
        boxH: 32,
        id: 'cat-cut',
      );
      expect(bytes, isNotEmpty);
      expect(_isPng(bytes), isTrue);
      final decoded = img.decodeImage(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, greaterThan(0));
      expect(decoded.height, greaterThan(0));
      expect(decoded.numChannels, 4);
      expect(decoded.width, greaterThanOrEqualTo(40));
      // Cut-out, ring and tilt really rendered: the corner is cut away, the
      // middle still carries the (opaque) photo.
      expect(decoded.getPixel(0, 0).a, 0);
      expect(decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2).a, 255);
    });

    test('is deterministic for one id — same bytes in, same PNG out', () {
      final photo = _photo();
      final first = StickerCutter.cutStickerBytes(
          imageBytes: photo, boxX: 8, boxY: 8, boxW: 32, boxH: 32, id: 'cat-det');
      final again = StickerCutter.cutStickerBytes(
          imageBytes: photo, boxX: 8, boxY: 8, boxW: 32, boxH: 32, id: 'cat-det');
      expect(again, equals(first));
    });

    test('survives a padded box that runs off the frame edge', () {
      final bytes = StickerCutter.cutStickerBytes(
        imageBytes: _photo(width: 40, height: 40),
        boxX: 0,
        boxY: 0,
        boxW: 40,
        boxH: 40,
        id: 'cat-edge',
      );
      expect(_isPng(bytes), isTrue);
    });

    test('tilt is stable per id and stays inside +/- 5 degrees', () {
      expect(StickerCutter.tiltFor('cat-tilt'), StickerCutter.tiltFor('cat-tilt'));
      var sawNegative = false;
      var sawPositive = false;
      for (var i = 0; i < 60; i++) {
        final tilt = StickerCutter.tiltFor('cat-tilt-$i');
        expect(tilt.abs(), lessThanOrEqualTo(StickerCutter.maxTiltDegrees));
        if (tilt < 0) sawNegative = true;
        if (tilt > 0) sawPositive = true;
      }
      expect(sawNegative && sawPositive, isTrue);
    });

    test('catchCat writes the sticker beside the original', () async {
      final cutter = StickerCutter(storageDir: tmp);
      final sighting = await cutter.catchCat(
        imageBytes: _photo(),
        boxX: 20,
        boxY: 16,
        boxW: 40,
        boxH: 32,
        label: 'cat',
        precinct: 'Precinct 7',
        source: 'camera',
        id: 'cat-files',
        capturedAt: DateTime.utc(2026, 10, 14, 9, 30),
      );

      expect(sighting.id, 'cat-files');
      expect(sighting.name, catDexNameFor('cat-files'));
      expect(sighting.precinct, 'Precinct 7');
      expect(sighting.source, 'camera');
      expect(sighting.capturedAt, DateTime.utc(2026, 10, 14, 9, 30));

      final sticker = File(sighting.stickerPath);
      expect(sticker.path,
          '${tmp.path}/${StickerCutter.stickerDirName}/cat-files.png');
      expect(sticker.existsSync(), isTrue);
      expect(_isPng(sticker.readAsBytesSync()), isTrue);
      expect(sticker.lengthSync(), greaterThan(0));

      final original = File(sighting.originalPath);
      expect(original.existsSync(), isTrue);
      expect(original.lengthSync(), greaterThan(0));
      expect(original.path, endsWith('cat-files_src.png'));
    });

    test('rejects undecodable bytes', () {
      expect(
        () => StickerCutter.cutStickerBytes(
          imageBytes: Uint8List.fromList(const [1, 2, 3, 4]),
          boxX: 0,
          boxY: 0,
          boxW: 4,
          boxH: 4,
          id: 'cat-bad',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Cat Dex -> community board', () {
    Future<CommunityBoardStore> freshBoard() async {
      final board = CommunityBoardStore(storageDir: tmp);
      await board.load();
      return board;
    }

    test('shareSightingToBoard posts a non-synthetic Lost & Found entry', () async {
      final board = await freshBoard();
      final baseline = board.postCount;
      expect(baseline, greaterThan(0), reason: 'synthetic seed loads first');

      final post = await shareSightingToBoard(
          board: board, sighting: _sighting('cat-share'));

      expect(board.postCount, baseline + 1);
      expect(board.posts.first.id, post.id);
      expect(post.title,
          'Cat Distribution System: a cat was assigned at Precinct 7');
      expect(post.category, 'Lost & Found');
      expect(post.precinct, 'Precinct 7');
      expect(post.isSynthetic, isFalse);
      expect(post.body, contains(_sighting('cat-share').name));
      expect(post.authorLabel, startsWith('Resident A-'));
      expect(post.comments, isEmpty);
      expect(board.byId(post.id), isNotNull);
      expect(board.byCategory('Lost & Found'), contains(post));
    });

    test('the shared post survives a reload', () async {
      final board = await freshBoard();
      final post = await shareSightingToBoard(
          board: board, sighting: _sighting('cat-persist'));

      final reloaded = await freshBoard();
      final stored = reloaded.byId(post.id);
      expect(stored, isNotNull);
      expect(stored!.title, post.title);
      expect(stored.isSynthetic, isFalse);
      expect(stored.category, 'Lost & Found');
    });

    test('sharing the same sighting twice adds one post', () async {
      final board = await freshBoard();
      final baseline = board.postCount;
      final sighting = _sighting('cat-twice');

      final first = await shareSightingToBoard(board: board, sighting: sighting);
      final second = await shareSightingToBoard(board: board, sighting: sighting);

      expect(board.postCount, baseline + 1);
      expect(first.id, 'cat-dex-cat-twice');
      expect(second.id, first.id);
      expect(catDexAlreadyShared(board, sighting), isTrue);
      expect(catDexAlreadyShared(board, _sighting('cat-thrice')), isFalse);
    });
  });

  group('CatDexScreen', () {
    testWidgets('shows the empty shelf copy + CTA, then the sheet + share button',
        (tester) async {
      // Neither store is `load()`ed on purpose: nothing then writes a JSON file
      // from inside the widget-test zone, and the board stays deterministic.
      final store = CatDexStore(storageDir: tmp);
      final board = CommunityBoardStore(storageDir: tmp);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: CatDexScreen(store: store, board: board)),
        routes: {
          // Share always leaves for the board — stub the route here.
          '/board': (_) =>
              const Scaffold(body: Text('board-route-stub')),
        },
      ));
      // Empty Dex: no level banner, the quiet shelf copy and the CTA.
      expect(find.text('The Dex is quiet'), findsOneWidget);
      expect(
          find.text(
              'Spot a stray cat on a scan run? Log the sighting to fill this shelf.'),
          findsOneWidget);
      expect(find.text('Log a sighting'), findsOneWidget);
      expect(find.textContaining('Cat Level'), findsNothing);

      // A real sighting with a real sticker on disk in the temp dir. Real file
      // I/O has to happen outside the fake-async zone, hence `runAsync`.
      final sighting = await tester.runAsync(() async {
        final cat = await StickerCutter(storageDir: tmp).catchCat(
          imageBytes: _photo(),
          boxX: 20,
          boxY: 16,
          boxW: 40,
          boxH: 32,
          label: 'cat',
          precinct: 'Precinct 7',
          source: 'camera',
          id: 'cat-ui',
          capturedAt: DateTime.utc(2026, 10, 14, 9, 30),
        );
        await store.addSighting(
          id: cat.id,
          label: cat.label,
          precinct: cat.precinct,
          source: cat.source,
          originalPath: cat.originalPath,
          stickerPath: cat.stickerPath,
          capturedAt: cat.capturedAt,
          name: cat.name,
        );
        return cat;
      });
      expect(sighting, isNotNull);
      final cat = sighting!;
      await tester.pumpAndSettle();

      expect(find.text('The Dex is quiet'), findsNothing);
      expect(find.text('Log a sighting'), findsNothing);
      expect(find.text('Cat Level 1'), findsOneWidget);
      expect(find.text(cat.name), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('cat-sticker-${cat.id}')));
      await tester.pumpAndSettle();

      expect(find.text('Share sighting to board'), findsOneWidget);
      expect(find.textContaining('Precinct 7'), findsWidgets);
      expect(find.textContaining('2026-10-14'), findsOneWidget);
      // Older-style sighting with no itemLabel shows the raw detector label.
      expect(find.text('Caught via camera · cat'), findsOneWidget);

      final baseline = board.postCount;
      await tester.tap(find.text('Share sighting to board'));
      await tester.pumpAndSettle();

      expect(board.postCount, baseline + 1);
      expect(board.posts.first.title,
          'Cat Distribution System: a cat was assigned at Precinct 7');
      expect(board.posts.first.isSynthetic, isFalse);
      // The sheet popped and the app pushed /board.
      expect(find.text('Share sighting to board'), findsNothing);
      expect(find.text('board-route-stub'), findsOneWidget);
    });
  });
}
