/// WO-05 — scan failure paths, pinned end to end:
///
/// * the board-35 consent explainer renders *before any camera plugin call*
///   (value-first camera consent: zero calls on the camera channel while the
///   explainer is on screen);
/// * board-32 denied recovery offers all three ways out — "Open settings"
///   (the `township/system` `openAppSettings` method channel call), "Try
///   again" (re-initialises) and "Skip for now" (gallery import, cancelled
///   import → camera-off panel with both ways forward);
/// * analysis failures — null result *and* thrown exception — surface the
///   recoverable "Could not read that photo" panel, `_analysing` is always
///   cleared, and both recovery actions work;
/// * the analysing overlay honours `MediaQuery.disableAnimationsOf`
///   (static glyph, no spinner);
/// * the cat catch files `itemLabel` = strongest non-cat waste label, else
///   `'stray cat'`;
/// * the result view renders with only the shell Scaffold (nested Scaffold
///   removed), SafeArea kept.
///
/// Everything runs against injected collaborators (stub [VisionPipeline],
/// temp-dir [CatDexStore]/[StickerCutter]) and mocked channels — no emulator,
/// no `path_provider`, no real camera.
///
/// Run: `flutter test test/scan_failure_test.dart`
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
// The test seam for the picker is `ImagePickerPlatform.instance`; the package
// is a transitive dependency of `image_picker`.
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart'
    show ImagePickerOptions, ImagePickerPlatform;
import 'package:township_of_tomorrow/cat_dex/cat_dex_store.dart';
import 'package:township_of_tomorrow/cat_dex/sticker_cutter.dart';
import 'package:township_of_tomorrow/screens/scan_screen.dart';
import 'package:township_of_tomorrow/services/vision_pipeline.dart';
import 'package:township_of_tomorrow/services/waste_classifier.dart';
import 'package:township_of_tomorrow/store/collection_store.dart';
import 'package:township_of_tomorrow/types.dart';

/// The camera plugin's method channel (what `availableCameras` /
/// `CameraController.initialize` talk to).
const MethodChannel _cameraChannel = MethodChannel('plugins.flutter.io/camera');

/// The board-32 "Open settings" channel (MainActivity: app-details intent).
const MethodChannel _systemChannel = MethodChannel('township/system');

/// A synthetic RGBA frame — deterministic, opaque, no fixtures on disk.
Uint8List _photoBytes() {
  final im = img.Image(width: 64, height: 48, numChannels: 4);
  for (var y = 0; y < 48; y++) {
    for (var x = 0; x < 64; x++) {
      im.setPixelRgba(x, y, (x * 3) % 256, (y * 5) % 256, 64, 255);
    }
  }
  return img.encodePng(im);
}

/// Detector box, in the pipeline's working-copy pixel space.
DetectedObject _box(String label, double confidence, {bool waste = true}) =>
    DetectedObject.at(label, confidence, RecycleCategory.trash, waste, 8, 6, 34, 30);

/// MaterialApp host with the `/cat-dex` route the catch pushes to.
Widget _host(Widget child) => MaterialApp(
      routes: {
        '/cat-dex': (_) =>
            const Scaffold(body: Center(child: Text('Cat Dex destination'))),
      },
      home: Scaffold(body: child),
    );

/// Let mocked-channel/async chains progress: one real event-loop turn, one
/// pump — the same drain `test/scan_catch_test.dart` uses for real I/O.
Future<void> _drain(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
}

/// Always returns null — the resident cancelled the picker.
class _FakeImagePicker extends ImagePickerPlatform {
  int calls = 0;
  final List<ImageSource> sources = <ImageSource>[];

  void reset() {
    calls = 0;
    sources.clear();
  }

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    calls += 1;
    sources.add(source);
    return null; // cancelled
  }
}

/// Analysis returns null — the "unreadable photo" path.
class _NullPipeline extends VisionPipeline {
  @override
  Future<ScanResult?> analyseFile(String path) async => null;
}

/// Analysis throws — the "thrown exception" path.
class _ThrowPipeline extends VisionPipeline {
  @override
  Future<ScanResult?> analyseFile(String path) async {
    throw StateError('model exploded');
  }
}

/// Analysis blocks on [gate] — lets a test observe the analysing overlay.
class _GatedPipeline extends VisionPipeline {
  _GatedPipeline(this.gate);
  final Future<ScanResult?> gate;
  @override
  Future<ScanResult?> analyseFile(String path) => gate;
}

/// Analysis always returns this result — drives the result view.
class _FixedPipeline extends VisionPipeline {
  _FixedPipeline(this.result);
  final ScanResult result;
  @override
  Future<ScanResult?> analyseFile(String path) async => result;
}

/// A decided scan, cheaply assembled: no boxes, one stream, no kNN.
ScanResult _decidedResult() => ScanResult(
      const ClassificationOutcome(
        category: WasteCategory.Recyclable,
        confidence: 84,
        needsConfirmation: false,
        candidates: [WasteCategory.Recyclable],
        infrastructure: false,
        scores: {},
        knnItem: 'plastic bottle',
        deviceName: 'plastic bottle',
        matchedFrom: 'recycling stream',
      ),
      const [],
      const [],
      null,
      12,
    );

/// Record every camera-channel call; `create` refuses like the OS would.
void _installCameraMock(List<String> calls) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_cameraChannel, (call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'availableCameras':
        return <Map<String, Object>>[
          <String, Object>{
            'name': '(Camera) test',
            'lensFacing': 'back',
            'sensorOrientation': 90,
          },
        ];
      case 'create':
        throw PlatformException(
            code: 'CameraAccessDenied', message: 'The user denied permission');
      default:
        return null;
    }
  });
}

void _installSystemMock(List<String> calls) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_systemChannel, (call) async {
    calls.add(call.method);
    return true;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final picker = _FakeImagePicker();
  final originalPicker = ImagePickerPlatform.instance;
  late Directory tmp;

  setUp(() {
    ImagePickerPlatform.instance = picker;
    picker.reset();
    tmp = Directory.systemTemp.createTempSync('scan_failure_test');
  });

  tearDown(() {
    ImagePickerPlatform.instance = originalPicker;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_cameraChannel, null);
    messenger.setMockMethodCallHandler(_systemChannel, null);
  });

  group('camera consent (board-35)', () {
    testWidgets('explainer shows before any camera initialization',
        (tester) async {
      final cameraCalls = <String>[];
      _installCameraMock(cameraCalls);

      await tester.pumpWidget(
          _host(ScanScreen(pipeline: _NullPipeline(), store: CollectionStore())));
      await tester.pump();

      // The board, verbatim.
      expect(find.text('Before the camera opens'), findsOneWidget);
      expect(
          find.text(
              'We ask once, with a reason: the scan runs on this device — nothing is uploaded.'),
          findsOneWidget);
      expect(find.text('Runs on-device, no cloud'), findsOneWidget);
      expect(find.text('Nothing is uploaded'), findsOneWidget);
      expect(find.text('Revoke anytime in Settings'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Allow camera'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Not now'), findsOneWidget);
      expect(find.byIcon(Icons.photo_camera), findsOneWidget);

      // Value-first consent: not one camera plugin call has happened yet.
      expect(cameraCalls, isEmpty,
          reason: 'the explainer must render before any camera plugin call');
      expect(picker.calls, 0);
    });
  });

  group('permission recovery (board-32)', () {
    testWidgets('permission recovery offers settings, retry and skip',
        (tester) async {
      final cameraCalls = <String>[];
      final systemCalls = <String>[];
      _installCameraMock(cameraCalls);
      _installSystemMock(systemCalls);

      await tester.pumpWidget(
          _host(ScanScreen(pipeline: _NullPipeline(), store: CollectionStore())));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Allow camera'));
      await tester.pumpAndSettle();

      // Denied board, verbatim copy.
      expect(find.text('Camera permission denied'), findsOneWidget);
      expect(
          find.text(
              'No problem.\nThe scanner needs the camera only when you use it — your '
              'photos stay on this device and you can change this anytime in system settings.'),
          findsOneWidget);
      expect(cameraCalls, contains('availableCameras'));
      expect(cameraCalls, contains('create'));
      expect(systemCalls, isEmpty);

      // "Open settings" → MethodChannel 'township/system' openAppSettings.
      await tester.tap(find.widgetWithText(FilledButton, 'Open settings'));
      await tester.pumpAndSettle();
      expect(systemCalls, ['openAppSettings']);

      // "Try again" → re-initialise the camera (refusal repeats → same board).
      final callsBeforeRetry = cameraCalls.length;
      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pumpAndSettle();
      expect(cameraCalls.length, greaterThan(callsBeforeRetry),
          reason: '"Try again" must re-run camera initialisation');
      expect(cameraCalls.where((m) => m == 'availableCameras').length, 2);
      expect(find.text('Camera permission denied'), findsOneWidget);

      // "Skip for now" → gallery import → cancelled → camera-off panel with
      // both ways forward, never a dead end.
      await tester.tap(find.widgetWithText(TextButton, 'Skip for now'));
      await tester.pumpAndSettle();
      expect(picker.calls, 1);
      expect(picker.sources.single, ImageSource.gallery);
      expect(find.text('Camera permission denied'), findsNothing);
      expect(find.text('The camera is off'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Import a photo'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Allow camera'), findsOneWidget);
    });
  });

  group('analysis failures', () {
    testWidgets('analysis failure renders a recoverable panel', (tester) async {
      await tester.pumpWidget(
          _host(ScanScreen(pipeline: _NullPipeline(), store: CollectionStore())));
      await tester.pump();
      expect(find.text('Before the camera opens'), findsOneWidget);

      ScanScreenStateProxy.fire('/tmp/never-read.png');
      await _drain(tester,
          () => find.text('Could not read that photo').evaluate().isNotEmpty);
      await tester.pump();

      expect(find.text('Could not read that photo'), findsOneWidget);
      expect(
          find.widgetWithText(FilledButton, 'Try another photo'), findsOneWidget);
      expect(
          find.widgetWithText(OutlinedButton, 'Import a photo'), findsOneWidget);
      // `_analysing` is always cleared in the finally — the overlay is gone.
      expect(find.text('Working on-device…'), findsNothing);

      // Recoverable: "Try another photo" returns to the flow.
      await tester.tap(find.widgetWithText(FilledButton, 'Try another photo'));
      await tester.pump();
      expect(find.text('Could not read that photo'), findsNothing);
      expect(find.text('Before the camera opens'), findsOneWidget);
    });

    testWidgets('a thrown analysis exception lands on the same panel',
        (tester) async {
      await tester.pumpWidget(
          _host(ScanScreen(pipeline: _ThrowPipeline(), store: CollectionStore())));
      await tester.pump();

      ScanScreenStateProxy.fire('/tmp/explodes.png');
      await _drain(tester,
          () => find.text('Could not read that photo').evaluate().isNotEmpty);
      await tester.pump();
      expect(find.text('Could not read that photo'), findsOneWidget);
      expect(find.text('Working on-device…'), findsNothing);

      // "Import a photo" → picker → cancelled → camera-off panel (no dead end).
      await tester.tap(find.widgetWithText(OutlinedButton, 'Import a photo'));
      await tester.pumpAndSettle();
      expect(picker.calls, 1);
      expect(picker.sources.single, ImageSource.gallery);
      expect(find.text('Could not read that photo'), findsNothing);
      expect(find.text('The camera is off'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Import a photo'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Allow camera'), findsOneWidget);
    });

    testWidgets('the analysing overlay goes static under reduced motion',
        (tester) async {
      final gate = Completer<ScanResult?>();
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return Scaffold(
            body: MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: ScanScreen(
                  pipeline: _GatedPipeline(gate.future),
                  store: CollectionStore()),
            ),
          );
        }),
      ));
      await tester.pump();

      ScanScreenStateProxy.fire('/tmp/gated.png');
      await tester.pump();
      expect(find.text('Working on-device…'), findsOneWidget);
      // Static glyph instead of the spinner, because animations are off.
      expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      gate.complete(null);
      await _drain(tester,
          () => find.text('Could not read that photo').evaluate().isNotEmpty);
      await tester.pump();
      expect(find.text('Working on-device…'), findsNothing);
      expect(find.byIcon(Icons.hourglass_top), findsNothing);
    });
  });

  group('cat catch item label', () {
    test('itemLabelFor is the strongest non-cat waste label, else stray cat',
        () {
      expect(CatDistributionCard.itemLabelFor(const []), 'stray cat');
      expect(CatDistributionCard.itemLabelFor([_box('cat', 0.9, waste: false)]),
          'stray cat');
      // A non-waste box (chair) never becomes the Dex's item label.
      expect(
          CatDistributionCard.itemLabelFor([
            _box('chair', 0.95, waste: false),
            _box('cat', 0.9, waste: false),
          ]),
          'stray cat');
      // Strongest of the non-cat *waste* boxes wins, list order ignored.
      expect(
          CatDistributionCard.itemLabelFor([
            _box('bottle', 0.60, waste: true),
            _box('cat', 0.9, waste: false),
            _box('can', 0.95, waste: true),
          ]),
          'can');
      expect(
          CatDistributionCard.itemLabelFor([
            _box('cat', 0.9, waste: false),
            _box('bottle', 0.55, waste: true),
          ]),
          'bottle');
    });

    testWidgets('the catch files the sighting with that item label',
        (tester) async {
      final photo = File('${tmp.path}/photo.png')..writeAsBytesSync(_photoBytes());
      final dex = CatDexStore(storageDir: tmp); // never loaded → no path_provider
      final cutter = StickerCutter(storageDir: tmp);

      await tester.pumpWidget(_host(CatDistributionCard(
        objects: [
          _box('bottle', 0.95, waste: true),
          _box('cat', 0.88, waste: false),
        ],
        photoPath: photo.path,
        store: dex,
        cutter: cutter,
        precinct: 'Precinct 7',
      )));

      await tester.tap(find.text(CatDistributionCard.buttonLabel));
      await _drain(tester, () => dex.count > 0);
      await tester.pumpAndSettle();

      expect(dex.count, 1);
      final sighting = dex.sightings.first;
      expect(sighting.label, 'cat');
      expect(sighting.itemLabel, 'bottle');
      expect(sighting.source, 'scan');
      expect(sighting.precinct, 'Precinct 7');
      expect(File(sighting.stickerPath).existsSync(), isTrue);
      expect(find.text('Cat Dex destination'), findsOneWidget);
    });
  });

  group('result view shell', () {
    testWidgets('the result view renders with only the shell Scaffold',
        (tester) async {
      final photo = File('${tmp.path}/result.png')
        ..writeAsBytesSync(_photoBytes());

      await tester.pumpWidget(_host(ScanScreen(
        pipeline: _FixedPipeline(_decidedResult()),
        store: CollectionStore(),
      )));
      await tester.pump();

      ScanScreenStateProxy.fire(photo.path);
      // The headline card is inside the first viewport, unlike the confirm
      // button at the end of the lazy list — wait for that instead.
      await _drain(tester,
          () => find.text('Category: Recyclable').evaluate().isNotEmpty);
      await tester.pump();

      expect(find.text('Category: Recyclable'), findsOneWidget);
      expect(find.text('Looks like: plastic bottle (local embedding kNN)'),
          findsOneWidget);
      // WO-05: the nested Scaffold is gone — the route/shell Scaffold is the
      // only one — and the SafeArea stays.
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(SafeArea), findsOneWidget);
      expect(find.text('Could not read that photo'), findsNothing);

      // Confirm/rescan actions are still there, at the end of the scroll view —
      // scroll to the last of them so both are inside the built range.
      await tester.scrollUntilVisible(find.text('Scan another'), 200,
          scrollable: find.byType(Scrollable));
      expect(find.text('Confirm action'), findsOneWidget);
      expect(find.text('Scan another'), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}
