/// On-device run of the COCO-val2017 detection bench, for an Android emulator.
///
/// This file is a thin wrapper: it locates the fixtures that
/// `tool/fetch_test_images.sh` produced, then calls the very same bench the
/// host runner uses (`tool/detection_bench.dart` → [runBench] / [formatReport])
/// so the table, the accuracies and the 80 % PASS/FAIL rule cannot drift
/// between the two runners. The table is printed with `debugPrint`, so it shows
/// up in the `flutter test` console **and** in `adb logcat`.
///
/// Prerequisites
/// -------------
/// 1. `integration_test` must be a dev dependency (this task was bounded to
///    four new files, so `pubspec.yaml` was deliberately left untouched — add
///    the three lines yourself before running):
///
///    ```yaml
///    dev_dependencies:
///      integration_test:
///        sdk: flutter
///    ```
///
/// 2. Fetch the fixtures on the host, once:
///
///    ```bash
///    tool/fetch_test_images.sh
///    ```
///
/// 3. Copy them onto the emulator. The app-specific external directory is the
///    one path an unprivileged app can always read, so push there; the test
///    also looks in shared Download storage and the app's documents directory:
///
///    ```bash
///    adb shell mkdir -p /sdcard/Android/data/<APPLICATION_ID>/files/township_test_images
///    adb push "assets/test_images/." \
///        /sdcard/Android/data/<APPLICATION_ID>/files/township_test_images/
///    ```
///
/// 4. Run it (no emulator is started by this test — point `-d` at a device that
///    is already booted):
///
///    ```bash
///    flutter test integration_test/on_device_detection_test.dart -d emulator-5554
///    adb logcat -s flutter    # same table, live
///    ```
///
///    `--dart-define=BENCH_DIR=/path/on/device/township_test_images` overrides
///    the search when the fixtures live somewhere else.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import '../tool/detection_bench.dart';

/// Directory name the fixtures are pushed under, inside whichever root is used.
const String fixtureDirectoryName = 'township_test_images';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'on-device YOLO bench: COCO val2017 fixtures, >= 80% category accuracy',
    (tester) async {
      debugPrint('TWP:bench device ${Platform.operatingSystem} '
          '${Platform.operatingSystemVersion}');
      debugPrint('TWP:bench dart ${Platform.version}');

      final candidates = await candidateFixtureDirectories();
      final imageDir = firstWithManifest(candidates);
      if (imageDir == null) {
        debugPrint(pushInstructions(candidates));
        markTestSkipped(
            'no fixtures on the device — push assets/test_images first (see log)');
        return;
      }

      final manifestPath = '${imageDir.path}/manifest.json';
      debugPrint('TWP:bench fixtures ${imageDir.path} '
          '(${manifestImageCount(manifestPath)} images, manifest $manifestPath)');
      for (final expectation in loadManifest(File(manifestPath).readAsStringSync())) {
        debugPrint('TWP:bench expected ${describeExpectation(expectation)}');
      }

      final report = await runBench(
        imageDirectory: imageDir.path,
        manifestPath: manifestPath,
        log: debugPrint,
      );

      // The table goes to the test log as well as to the console.
      debugPrint(formatReport(report));

      if (!report.detectorLoaded || report.rows.isEmpty) {
        markTestSkipped(report.skipReason ?? 'the bench measured nothing');
        return;
      }
      if (report.measured.isEmpty) {
        fail('no image could be scored on device: ${report.errorCount} errored, '
            '${report.missingCount} missing');
      }

      expect(report.missingCount, 0,
          reason: 'every manifest image must be on the device under '
              '${imageDir.path}');
      expect(
        report.categoryAccuracy,
        greaterThanOrEqualTo(categoryAccuracyThreshold),
        reason: 'on-device category accuracy '
            '${percentText(report.categoryAccuracy)} is below the '
            '${percentText(categoryAccuracyThreshold)} threshold',
      );
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

/// Every place the fixtures are looked for, most specific first.
///
/// `path_provider` is already a dependency of the app, and its directories are
/// the only ones guaranteed to be readable by an unprivileged Android app.
Future<List<Directory>> candidateFixtureDirectories() async {
  final roots = <String>[];

  const dartDefined = String.fromEnvironment('BENCH_DIR');
  if (dartDefined.isNotEmpty) roots.add(dartDefined);
  final fromEnvironment = Platform.environment['BENCH_DIR'];
  if (fromEnvironment != null && fromEnvironment.isNotEmpty) {
    roots.add(fromEnvironment);
  }

  // App-specific external storage: `adb push`-able, no permission needed.
  try {
    final external = await getExternalStorageDirectory();
    if (external != null) {
      roots.add('${external.path}/$fixtureDirectoryName');
      roots.add(external.path);
    }
  } on Object catch (error) {
    debugPrint('TWP:bench getExternalStorageDirectory unavailable: $error');
  }

  // App-private documents directory (owner-only, for `run-as` workflows).
  try {
    final documents = await getApplicationDocumentsDirectory();
    roots.add('${documents.path}/$fixtureDirectoryName');
    roots.add(documents.path);
  } on Object catch (error) {
    debugPrint('TWP:bench getApplicationDocumentsDirectory unavailable: $error');
  }

  // Shared storage and the debugger's scratch space, in case they were used.
  roots
    ..add('/sdcard/Download/$fixtureDirectoryName')
    ..add('/storage/emulated/0/Download/$fixtureDirectoryName')
    ..add('/sdcard/$fixtureDirectoryName')
    ..add('/data/local/tmp/$fixtureDirectoryName')
    ..add('assets/test_images');

  return <Directory>[
    for (final root in roots)
      if (root.isNotEmpty) Directory(root),
  ];
}

/// First candidate that actually holds a `manifest.json`.
Directory? firstWithManifest(List<Directory> candidates) {
  for (final directory in candidates) {
    if (File('${directory.path}/manifest.json').existsSync()) return directory;
  }
  return null;
}

/// What to print when the fixtures are not on the device yet.
String pushInstructions(List<Directory> candidates) {
  final buffer = StringBuffer()
    ..writeln('TWP:bench NO FIXTURES ON DEVICE — the bench was skipped.');
  final checked = candidates.map((directory) => directory.path).join('\n');
  buffer.writeln('Checked:\n$checked');
  buffer
    ..writeln('Push them from the repository root with (APPLICATION_ID = the '
        'app id in android/app/build.gradle):')
    ..writeln('  tool/fetch_test_images.sh')
    ..writeln('  adb shell mkdir -p '
        '/sdcard/Android/data/<APPLICATION_ID>/files/$fixtureDirectoryName')
    ..writeln('  adb push "assets/test_images/." '
        '/sdcard/Android/data/<APPLICATION_ID>/files/$fixtureDirectoryName/')
    ..writeln('  flutter test integration_test/on_device_detection_test.dart '
        '-d <emulator-id>');
  return buffer.toString();
}
