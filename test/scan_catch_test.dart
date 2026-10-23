/// Widget + handler tests for the Cat Distribution System card on the scan
/// result view (`lib/screens/scan_screen.dart`).
///
/// Pinned here:
/// * the card appears when — and only when — a detected box is labelled `cat`,
///   whatever its position in the evidence order;
/// * the catch handler re-reads the analysed photo, cuts the highest-confidence
///   cat box into a sticker in an injected temp dir, files the sighting in an
///   injected [CatDexStore] and pushes `/cat-dex`;
/// * a handler failure (photo gone, bytes undecodable, no plugin) is a SnackBar
///   and nothing else — never an unhandled exception.
///
/// Test-harness note: the handler does real `dart:io` work, and real async work
/// awaits inside `testWidgets`' fake-async zone never completes. Every drain
/// here therefore runs the real event loop inside `tester.runAsync(...)` and
/// then pumps, so the interleaved file-I/O → microtask → file-I/O chain of the
/// handler can progress. The stores are deliberately left **un-loaded** (their
/// injectable dir is a temp dir, `load()` is never called), so nothing touches
/// `path_provider` and no JSON file is written behind the test's back.
///
/// Run: `flutter test test/scan_catch_test.dart`
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:township_of_tomorrow/cat_dex/cat_dex_models.dart';
import 'package:township_of_tomorrow/cat_dex/cat_dex_store.dart';
import 'package:township_of_tomorrow/cat_dex/sticker_cutter.dart';
import 'package:township_of_tomorrow/screens/scan_screen.dart';
import 'package:township_of_tomorrow/types.dart';

/// A synthetic RGBA frame — deterministic, opaque, no fixtures on disk.
Uint8List _photo({int width = 64, int height = 48}) {
  final im = img.Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      im.setPixelRgba(x, y, (x * 3) % 256, (y * 5) % 256, 64, 255);
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

/// Detector box, in the pipeline's working-copy pixel space.
DetectedObject _box(String label, double confidence,
        {double x1 = 8, double y1 = 6, double x2 = 34, double y2 = 30}) =>
    DetectedObject.at(
        label, confidence, RecycleCategory.trash, false, x1, y1, x2, y2);

/// Records what the handler handed the cutter, then cuts the sticker for real
/// into the injected temp dir.
class _RecordingCutter extends StickerCutter {
  _RecordingCutter(Directory dir) : super(storageDir: dir);

  final calls = <({double boxX, double boxY, double boxW, double boxH})>[];

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
  }) {
    calls.add((boxX: boxX, boxY: boxY, boxW: boxW, boxH: boxH));
    return super.catchCat(
      imageBytes: imageBytes,
      boxX: boxX,
      boxY: boxY,
      boxW: boxW,
      boxH: boxH,
      label: label,
      precinct: precinct,
      source: source,
      id: id,
      name: name,
      capturedAt: capturedAt,
    );
  }
}

/// The card on the `/cat-dex` route's destination, so a push is observable.
Widget _host(Widget card) => MaterialApp(
      routes: {
        '/cat-dex': (_) =>
            const Scaffold(body: Center(child: Text('Cat Dex destination'))),
      },
      home: Scaffold(body: SingleChildScrollView(child: card)),
    );

/// Let the handler's real I/O progress: one real event-loop turn, one pump.
Future<void> _drain(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
}

void main() {
  group('card visibility', () {
    testWidgets('a cat box shows the Cat Distribution System card',
        (tester) async {
      await tester.pumpWidget(_host(CatDistributionCard(
        objects: [
          _box('bottle', 0.95),
          _box('cat', 0.41, x1: 2, y1: 2, x2: 14, y2: 14),
          _box('cat', 0.77),
        ],
        photoPath: '/tmp/never-read-because-nothing-is-tapped.png',
      )));

      expect(find.text('Cat Distribution System'), findsOneWidget);
      expect(find.text(CatDistributionCard.message), findsOneWidget);
      expect(find.text('Catch it → Cat Dex'), findsOneWidget);
    });

    testWidgets('no cat box means no card, no copy and no button',
        (tester) async {
      await tester.pumpWidget(_host(CatDistributionCard(
        objects: [_box('bottle', 0.9), _box('chair', 0.4), _box('kitten', 0.99)],
        photoPath: '/tmp/never-read.png',
      )));

      expect(find.text(CatDistributionCard.message), findsNothing);
      expect(find.text(CatDistributionCard.buttonLabel), findsNothing);
      expect(find.text('Cat Distribution System'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);

      await tester.pumpWidget(_host(const CatDistributionCard(
        objects: [],
        photoPath: '/tmp/never-read.png',
      )));
      expect(find.text(CatDistributionCard.message), findsNothing);
    });

    test('boxes are scaled back out of the 640-px working copy only when the '
        'capture is the longer one', () {
      expect(CatDistributionCard.scaleToOriginal(64, 48), 1.0);
      expect(CatDistributionCard.scaleToOriginal(640, 480), 1.0);
      expect(CatDistributionCard.scaleToOriginal(1280, 720), 2.0);
      expect(CatDistributionCard.scaleToOriginal(800, 1200), 1200 / 640);
    });

    test('the highest-confidence cat wins, whatever the evidence order', () {
      final weak = _box('cat', 0.2);
      final strong = _box('cat', 0.9, x1: 20, y1: 20, x2: 40, y2: 40);
      expect(CatDistributionCard.catBox([weak, _box('bottle', 0.99), strong]), strong);
      expect(CatDistributionCard.catBox([_box('bottle', 0.99)]), isNull);
      expect(CatDistributionCard.catBox(const []), isNull);
    });
  });

  group('catch handler', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('scan_catch_test'));

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    testWidgets('catching the cat cuts a sticker, files it and opens the Dex',
        (tester) async {
      final photo = File('${tmp.path}/photo.png')..writeAsBytesSync(_photo());
      final dex = CatDexStore(storageDir: tmp); // injectable, never loaded
      final cutter = _RecordingCutter(tmp);
      final lower = _box('cat', 0.31, x1: 2, y1: 2, x2: 12, y2: 12);
      final best = _box('cat', 0.88, x1: 8, y1: 6, x2: 34, y2: 30);

      await tester.pumpWidget(_host(CatDistributionCard(
        objects: [_box('bottle', 0.95), lower, best],
        photoPath: photo.path,
        store: dex,
        cutter: cutter,
        precinct: 'Precinct 7',
      )));
      expect(dex.count, 0);

      await tester.tap(find.text(CatDistributionCard.buttonLabel));
      await _drain(tester, () => dex.count > 0);
      await tester.pumpAndSettle();

      // The handler picked the stronger box, from the real photo bytes.
      expect(cutter.calls, hasLength(1));
      expect(cutter.calls.single.boxX, best.x1);
      expect(cutter.calls.single.boxY, best.y1);
      expect(cutter.calls.single.boxW, best.width);
      expect(cutter.calls.single.boxH, best.height);

      // …and the sighting landed in the (injectable) store.
      expect(dex.count, 1);
      final sighting = dex.sightings.first;
      expect(sighting.label, 'cat');
      expect(sighting.source, 'scan');
      expect(sighting.precinct, 'Precinct 7');
      expect(sighting.name, catDexNameFor(sighting.id));

      final sticker = File(sighting.stickerPath);
      expect(sticker.existsSync(), isTrue);
      expect(_isPng(sticker.readAsBytesSync()), isTrue);
      expect(sticker.path.startsWith(tmp.path), isTrue);
      expect(File(sighting.originalPath).existsSync(), isTrue);

      expect(find.text('Cat Dex destination'), findsOneWidget);
    });

    testWidgets('a catch that cannot run is a SnackBar, not a crash',
        (tester) async {
      final dex = CatDexStore(storageDir: tmp);
      final cutter = _RecordingCutter(tmp);

      await tester.pumpWidget(_host(CatDistributionCard(
        objects: [_box('cat', 0.66)],
        photoPath: '${tmp.path}/gone.png', // never written
        store: dex,
        cutter: cutter,
      )));

      await tester.tap(find.text(CatDistributionCard.buttonLabel));
      await _drain(tester, () => find.text(CatDistributionCard.escapeMessage).evaluate().isNotEmpty);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // entrance done

      expect(find.text(CatDistributionCard.escapeMessage), findsOneWidget);
      expect(dex.count, 0);
      expect(cutter.calls, isEmpty);
      expect(find.text('Cat Dex destination'), findsNothing);

      // Let the SnackBar's own auto-dismiss timer run out before the test ends.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text(CatDistributionCard.escapeMessage), findsNothing);
    });
  });
}
