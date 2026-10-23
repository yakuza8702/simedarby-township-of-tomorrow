/// Widget tests for WO-06 — teach the scanner: the six streams in render
/// order, the name rules (2–40 trimmed characters + case-insensitive
/// duplicate), and the Add button's live keystroke gate.
///
/// The screen is mounted with `TeachScannerScreen.initialPhotoPath`, the
/// documented test seam, so no camera (and no image_picker channel) ever
/// runs; the store stays un-loaded so `path_provider` is never touched. Each
/// test gets its own TempDir holding a real, decodable PNG for that seam.
///
/// The screen is a scrollable page: on the default 800×600 test surface the
/// Add button sits below the fold (default finders treat unpainted widgets as
/// offstage), so every test opens with a tall surface — the gate under test
/// is about typing, not about scrolling.
///
/// Run: `flutter test test/teach_validation_test.dart`
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:township_of_tomorrow/screens/teach_scanner_screen.dart';
import 'package:township_of_tomorrow/services/embedder.dart';
import 'package:township_of_tomorrow/services/reference_library.dart';
import 'package:township_of_tomorrow/store/township_store.dart';

/// The six stream chips, pinned in their exact render order.
const _streams = <String>[
  'Recyclable',
  'Organic',
  'E-waste',
  'Hazardous',
  'Paper',
  'Other',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late TownshipStore store;
  late ReferenceLibrary refs;
  late String photoPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('teach_validation_test');
    // A real, decodable PNG so Image.file renders through its happy path.
    final png = img.Image(width: 16, height: 16);
    final photo = File('${tmp.path}/item.png')
      ..writeAsBytesSync(img.encodePng(png));
    photoPath = photo.path;
    // Deliberately un-loaded: `_file` stays null, so nothing touches
    // path_provider and no JSON is written behind the test's back.
    store = TownshipStore();
    refs = ReferenceLibrary(Embedder(), store);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Tall window so the whole form — photo, name, chips, Add — is painted at
  /// once and visible to the default (skip-offstage) finders.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// The screen under test; [withPhoto] mirrors the production mount (a photo
  /// exists only once the camera capture returns).
  Widget harness({bool withPhoto = true}) => MaterialApp(
        home: TeachScannerScreen(
          store: store,
          refs: refs,
          initialPhotoPath: withPhoto ? photoPath : null,
        ),
      );

  /// The single FilledButton on the screen — "Add to the scanner".
  FilledButton addButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton));

  List<ChoiceChip> chips(WidgetTester tester) =>
      tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();

  Future<void> typeName(WidgetTester tester, String value) async {
    await tester.enterText(find.byType(TextField), value);
    await tester.pump();
  }

  testWidgets('six stream chips render in the exact order', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(harness());

    final rendered = chips(tester);
    expect(rendered, hasLength(6), reason: 'exactly six streams, no Reusable');
    expect([for (final c in rendered) (c.label as Text).data!], _streams);

    // Verbatim screen copy (WO-06).
    expect(find.text('Teach the scanner'), findsOneWidget);
    expect(
        find.text('Take one clear photo of the item. The scan will recognise it next time — offline, forever.'),
        findsOneWidget);
    expect(find.text('Which stream?'), findsOneWidget);
    expect(find.text('Add to the scanner'), findsOneWidget);
    expect(find.text('Retake'), findsOneWidget);
    expect(find.text('Take a photo of the item'), findsNothing,
        reason: 'one photo + Retake — no second capture offer');

    // A11y: every chip is its own >=44dp tap target.
    for (var i = 0; i < rendered.length; i++) {
      final size = tester.getSize(find.byType(ChoiceChip).at(i));
      expect(size.width, greaterThanOrEqualTo(44),
          reason: 'chip $i ($_streams) tap width');
      expect(size.height, greaterThanOrEqualTo(44),
          reason: 'chip $i ($_streams) tap height');
    }

    // Paper (fifth chip) selects alone, and the selected state is announced
    // through the chip's own Semantics(selected: …) — no wrapper needed.
    final handle = tester.ensureSemantics();
    await tester.tap(find.text('Paper'));
    await tester.pump();
    expect(
        [for (final c in chips(tester)) c.selected],
        [false, false, false, false, true, false]);
    expect(tester.getSemantics(find.byType(ChoiceChip).at(4)),
        isSemantics(isSelected: true));
    expect(tester.getSemantics(find.byType(ChoiceChip).first),
        isSemantics(isSelected: false));
    handle.dispose();
  });

  testWidgets('duplicate and length validation reject bad names',
      (tester) async {
    useTallSurface(tester);
    store.addTaughtRef(label: 'milo tin', stream: 'Recyclable', photoPath: '');
    await tester.pumpWidget(harness());

    // Case- and padding-insensitive duplicate → the exact inline copy, quoting
    // the resident's own trimmed spelling.
    await typeName(tester, '  MILO TIN  ');
    expect(find.text('You already taught “MILO TIN”. Try a different name.'),
        findsOneWidget);
    expect(addButton(tester).onPressed, isNull);

    // Shorter than 2 trimmed characters.
    await typeName(tester, 'a');
    expect(find.text('Item name must be 2–40 characters.'), findsOneWidget);
    expect(addButton(tester).onPressed, isNull);

    // Longer than 40 trimmed characters.
    await typeName(tester, 'x' * 41);
    expect(find.text('Item name must be 2–40 characters.'), findsOneWidget);
    expect(addButton(tester).onPressed, isNull);

    // Boundary: exactly 40 trimmed characters is in range.
    await typeName(tester, 'y' * 40);
    expect(find.textContaining('already taught'), findsNothing);
    expect(find.textContaining('2–40'), findsNothing);

    // A unique, in-range name clears every error…
    await typeName(tester, 'Milo cup');
    expect(find.textContaining('already taught'), findsNothing);
    expect(find.textContaining('2–40'), findsNothing);
    // …and the button stays gated only because no stream is picked here.
    expect(addButton(tester).onPressed, isNull);
  });

  testWidgets('button enables on typing without another tap', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(harness());

    // Photo present (test seam) alone is not enough.
    expect(addButton(tester).onPressed, isNull);

    // The split label/hint pair; the hint paints while the field is focused
    // and still empty.
    expect(find.text('Item name'), findsOneWidget);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.text('e.g. Milo tin'), findsOneWidget);

    // Stream picked — still gated, the name is empty.
    await tester.tap(find.text('Organic'));
    await tester.pump();
    expect([for (final c in chips(tester)) c.selected],
        [false, true, false, false, false, false]);
    expect(addButton(tester).onPressed, isNull);

    // ONE keystroke — no tap anywhere — flips the button on: the controller
    // listener registered in initState re-evaluates the gate live.
    await tester.enterText(find.byType(TextField), 'Milo cup');
    await tester.pump();
    expect(addButton(tester).onPressed, isNotNull,
        reason: 'typing must enable the button without another tap');

    // …and back off the moment the name stops being valid.
    await tester.enterText(find.byType(TextField), 'x');
    await tester.pump();
    expect(addButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Milo cup');
    await tester.pump();
    expect(addButton(tester).onPressed, isNotNull);
  });
}
