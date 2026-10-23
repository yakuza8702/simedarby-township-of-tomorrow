/// COCO-val2017 detection bench for the on-device YOLO waste-scan stage.
///
/// What it measures
/// ----------------
/// For every image listed in `assets/test_images/manifest.json` (written by
/// `tool/fetch_test_images.sh` from the COCO 2017 val **annotations**, so the
/// expectation is real ground truth, not a guess):
///
///   1. decode the JPEG with `package:image`;
///   2. run [YoloDetector.detect] on it — the exact graph, pre-processing and
///      class-agnostic NMS the shipped scanner uses, on-device, offline;
///   3. map every returned box through [categoriseCocoLabel];
///   4. compare the detected stream with the expected stream from the manifest.
///
/// Scoring — product-fair and honest
/// ---------------------------------
/// * **Primary metric: any-detection match.** The scanner shows a chip per
///   detection (up to 8), so an image counts as a hit when *any* box carries
///   the expected label (label accuracy) or maps to the expected category
///   (category accuracy). Category any-match is what the PASS/FAIL line and the
///   test assertion use.
/// * **Secondary metric: top-1.** The same two accuracies computed from the
///   single highest-confidence box only, which is the scan headline the
///   resident reads first.
/// * **No free credit.** An image that yields *zero* detections is scored WRONG
///   for both label accuracy and category accuracy. Nothing is silently mapped
///   to `trash` for the empty case; the exhaustive label→stream fallback inside
///   [categoriseCocoLabel] only ever applies to boxes that were actually
///   returned.
///
/// It prints the required seven columns — image, expected label, expected
/// category, detected label (top-1), detected category (top-1), confidence and
/// `any_hit` — then both accuracy pairs, the zero-detection count and a
/// PASS/FAIL line against the 80 % category-accuracy threshold, which states
/// how label accuracy compares with that same 80 %.
///
/// Running it
/// ----------
/// ```bash
/// tool/fetch_test_images.sh                     # images + manifest (once)
/// flutter test tool/detection_bench.dart        # this bench, on the host
/// flutter test integration_test/on_device_detection_test.dart -d <emulator>
/// ```
///
/// The host run needs a TFLite C library next to the running executable
/// (`blobs/libtensorflowlite_c-linux.so`, which stock Flutter SDKs do not
/// ship), so on a plain dev box the bench reports SKIP with that reason and
/// points at the on-device integration test, which runs this same code on an
/// emulator with real TFLite.
///
/// Image location: the fetched JPEGs are deliberately *not* bundled as Flutter
/// assets — they are test fixtures, not app payload — so the on-device runner
/// pushes `assets/test_images/` to the device and points the bench at it (see
/// `integration_test/on_device_detection_test.dart`). `--dart-define=BENCH_DIR`,
/// a `BENCH_DIR` environment value or `--root <dir>` overrides the location for
/// either runner.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:township_of_tomorrow/services/recycle_classifier.dart';
import 'package:township_of_tomorrow/services/yolo_detector.dart';
import 'package:township_of_tomorrow/types.dart';

/// Category accuracy the bench must reach to print PASS.
const double categoryAccuracyThreshold = 0.80;

/// One manifest row: the ground truth for a single image.
class BenchExpectation {
  const BenchExpectation({
    required this.file,
    required this.label,
    required this.category,
    this.imageId,
    this.instanceCount,
  });

  /// File name inside the image directory, e.g. `000000000139.jpg`.
  final String file;

  /// Primary COCO class annotated on the image (the dominant one).
  final String label;

  /// Stream that label must map to — read from the manifest and cross-checked
  /// against [categoriseCocoLabel] before the detector is even loaded.
  final RecycleCategory category;

  /// COCO image id, when the manifest carries it.
  final int? imageId;

  /// Non-crowd instance count in the annotations, when available.
  final int? instanceCount;
}

/// Result for one image.
class BenchRow {
  const BenchRow({
    required this.expectation,
    required this.detectedLabel,
    required this.confidence,
    required this.category,
    required this.elapsedMs,
    required this.detectionCount,
    required this.anyLabelHit,
    required this.anyCategoryHit,
    required this.topIsWasteRelevant,
    this.missing = false,
    this.error,
  });

  final BenchExpectation expectation;

  /// The top-1 (highest-confidence) box — the scan headline — or
  /// `(nothing detected)` when the image produced no box at all.
  final String detectedLabel;
  final double confidence;

  /// Stream of [detectedLabel], i.e. of the top-1 box; `trash` for the
  /// placeholder label of a zero-detection image, which is never credited.
  final RecycleCategory category;
  final int elapsedMs;
  final int detectionCount;

  /// Primary metric: true when ANY returned box carries the expected label.
  final bool anyLabelHit;

  /// Primary metric: true when ANY returned box maps to the expected category.
  final bool anyCategoryHit;

  /// Whether the top box counts as waste evidence at all.
  final bool topIsWasteRelevant;

  /// The JPEG was not on disk — excluded from the accuracy denominators.
  final bool missing;

  /// The image could not be decoded, or the detector threw.
  final String? error;

  String get file => expectation.file;
  String get expectedLabel => expectation.label;
  RecycleCategory get expectedCategory => expectation.category;

  /// True when the image yielded no box whatsoever. Such a row is scored wrong
  /// for both metrics: an empty result is never credited as `trash`.
  bool get emptyDetection => detectionCount == 0;

  /// Primary metric — some detection on the image carries the expected label.
  bool get labelHit => measurable && anyLabelHit;

  /// Primary metric — some detection maps to the expected category.
  bool get categoryHit => measurable && anyCategoryHit;

  /// Secondary metric — the top-1 box alone is exactly the expected class.
  bool get top1LabelHit => measurable &&
      !emptyDetection &&
      detectedLabel == normaliseCocoLabel(expectedLabel);

  /// Secondary metric — the top-1 box alone maps to the expected category.
  bool get top1CategoryHit =>
      measurable && !emptyDetection && category == expectedCategory;

  bool get measurable => !missing && error == null;
}

/// Everything the bench measured.
class BenchReport {
  const BenchReport({
    required this.rows,
    required this.detectorLoaded,
    required this.elapsedMs,
    required this.imageDirectory,
    this.skipReason,
  });

  final List<BenchRow> rows;

  /// False when the model never loaded (missing asset, or no TFLite on host).
  final bool detectorLoaded;
  final int elapsedMs;
  final String imageDirectory;

  /// Set when the run could not measure anything at all.
  final String? skipReason;

  List<BenchRow> get measured =>
      rows.where((row) => row.measurable).toList(growable: false);

  int get missingCount => rows.where((row) => row.missing).length;
  int get errorCount => rows.where((row) => row.error != null).length;

  /// Images that yielded no detection at all — each one is a miss for both
  /// primary metrics and for both top-1 metrics.
  int get emptyDetectionCount =>
      measured.where((row) => row.emptyDetection).length;

  /// Primary (any-match) hit counts.
  int get labelHits => measured.where((row) => row.labelHit).length;
  int get categoryHits => measured.where((row) => row.categoryHit).length;

  /// Secondary (top-1) hit counts.
  int get top1LabelHits => measured.where((row) => row.top1LabelHit).length;
  int get top1CategoryHits =>
      measured.where((row) => row.top1CategoryHit).length;

  /// Primary metric: fraction of images where ANY detection carries the
  /// expected label.
  double get labelAccuracy =>
      measured.isEmpty ? 0 : labelHits / measured.length;

  /// Primary metric: fraction of images where ANY detection maps to the
  /// expected category — the PASS/FAIL metric.
  double get categoryAccuracy =>
      measured.isEmpty ? 0 : categoryHits / measured.length;

  /// Secondary metric: the top-1 box alone is the expected label.
  double get top1LabelAccuracy =>
      measured.isEmpty ? 0 : top1LabelHits / measured.length;

  /// Secondary metric: the top-1 box alone maps to the expected category.
  double get top1CategoryAccuracy =>
      measured.isEmpty ? 0 : top1CategoryHits / measured.length;

  /// PASS is 80 % **any-match** category accuracy over everything the manifest
  /// asked for; missing or errored images are reported rather than silently
  /// shrinking the denominator, and an empty measurement is never a pass.
  bool get passed =>
      skipReason == null &&
      errorCount == 0 &&
      missingCount == 0 &&
      measured.isNotEmpty &&
      categoryAccuracy >= categoryAccuracyThreshold;

  /// True when nothing could be scored — the caller decides whether that is a
  /// skip (host without TFLite) or a hard failure (device with no images).
  bool get unmeasured => measured.isEmpty;
}

/// Reads `manifest.json` (the fetch script's ground truth).
///
/// Tolerates the two shapes a hand-written manifest tends to take — a
/// `{"images": [...]}` object or a bare list — plus the `expected_*` key
/// spelling, so a manifest edited by hand still loads.
List<BenchExpectation> loadManifest(String jsonText) {
  final decoded = json.decode(jsonText);
  final List<dynamic> entries;
  if (decoded is Map<String, dynamic>) {
    final images = decoded['images'] ?? decoded['entries'];
    if (images is! List) {
      throw const FormatException(
          'manifest.json has no "images" list — re-run tool/fetch_test_images.sh');
    }
    entries = images;
  } else if (decoded is List) {
    entries = decoded;
  } else {
    throw const FormatException('manifest.json must be an object or a list');
  }

  final expectations = <BenchExpectation>[];
  for (final entry in entries) {
    if (entry is! Map) continue;
    final file =
        (entry['file'] ?? entry['filename'] ?? entry['path']) as String?;
    final label =
        (entry['label'] ?? entry['expected_label'] ?? entry['expectedLabel'])
            as String?;
    final categoryName = (entry['category'] ??
            entry['expected_category'] ??
            entry['expectedCategory']) as String?;
    if (file == null || label == null || categoryName == null) {
      throw FormatException('manifest row is missing file/label/category: $entry');
    }
    final category = RecycleCategory.values.firstWhere(
      (value) => value.name == categoryName,
      orElse: () => throw FormatException(
          'manifest row "$file" has unknown category "$categoryName"'),
    );
    expectations.add(BenchExpectation(
      file: file.split('/').last,
      label: normaliseCocoLabel(label),
      category: category,
      imageId: (entry['image_id'] as num?)?.toInt(),
      instanceCount: (entry['instance_count'] as num?)?.toInt(),
    ));
  }
  if (expectations.isEmpty) {
    throw const FormatException('manifest.json lists no images');
  }
  return expectations;
}

/// The bench itself: run the detector over every manifest image.
///
/// [log] receives progress lines; the caller prints the report with
/// [formatReport]. Never throws for a missing manifest / unusable model — it
/// returns a report whose [BenchReport.skipReason] says why.
Future<BenchReport> runBench({
  required String imageDirectory,
  required String manifestPath,
  double confidenceThreshold = YoloDetector.defaultConfidenceThreshold,
  void Function(String message)? log,
}) async {
  final stopwatch = Stopwatch()..start();
  final manifestFile = File(manifestPath);
  if (!manifestFile.existsSync()) {
    return BenchReport(
      rows: const [],
      detectorLoaded: false,
      elapsedMs: 0,
      imageDirectory: imageDirectory,
      skipReason:
          'no manifest at $manifestPath — run tool/fetch_test_images.sh first',
    );
  }

  final expectations = loadManifest(manifestFile.readAsStringSync());
  final detector = YoloDetector(confidenceThreshold: confidenceThreshold);
  try {
    await detector.load();
  } catch (error) {
    return BenchReport(
      rows: const [],
      detectorLoaded: false,
      elapsedMs: stopwatch.elapsedMilliseconds,
      imageDirectory: imageDirectory,
      skipReason: 'YoloDetector.load() failed: $error',
    );
  }

  log?.call('TWP:bench detector ready — input ${detector.inputWidth}x'
      '${detector.inputHeight}, ${detector.classCount} classes, '
      'threshold $confidenceThreshold, ${expectations.length} images to score');

  final rows = <BenchRow>[];
  for (final expectation in expectations) {
    final file = File('$imageDirectory/${expectation.file}');
    if (!file.existsSync() || file.lengthSync() == 0) {
      log?.call('TWP:bench missing ${file.path}');
      rows.add(BenchRow(
        expectation: expectation,
        detectedLabel: '-',
        confidence: 0,
        category: RecycleCategory.trash,
        elapsedMs: 0,
        detectionCount: 0,
        anyLabelHit: false,
        anyCategoryHit: false,
        topIsWasteRelevant: false,
        missing: true,
      ));
      continue;
    }

    try {
      final frame = img.decodeImage(file.readAsBytesSync());
      if (frame == null) {
        throw const FormatException('not a decodable image');
      }
      final imageStopwatch = Stopwatch()..start();
      final detections = await detector.detect(frame);
      imageStopwatch.stop();

      final top = primaryDetection(detections);
      final detectedLabel =
          top == null ? '(nothing detected)' : normaliseCocoLabel(top.label);
      // Primary metric: ANY box carrying the expected label / mapping to the
      // expected category. An empty result has no box, so both stay false —
      // that is the honest score for "the model saw nothing".
      final anyLabelHit = detections
          .any((d) => normaliseCocoLabel(d.label) == expectation.label);
      final anyCategoryHit = detections
          .any((d) => categoriseCocoLabel(d.label) == expectation.category);

      rows.add(BenchRow(
        expectation: expectation,
        detectedLabel: detectedLabel,
        confidence: top?.confidence ?? 0,
        category: categoriseCocoLabel(detectedLabel),
        elapsedMs: imageStopwatch.elapsedMilliseconds,
        detectionCount: detections.length,
        anyLabelHit: anyLabelHit,
        anyCategoryHit: anyCategoryHit,
        topIsWasteRelevant: top != null && wasteRelevantFor(top.label),
      ));
      log?.call('TWP:bench ${expectation.file} → $detectedLabel '
          '(${(top?.confidence ?? 0).toStringAsFixed(2)}, '
          '${detections.length} box(es), '
          'any_hit=${anyCategoryHit ? 'OK' : 'MISS'}, '
          '${imageStopwatch.elapsedMilliseconds}ms)');
    } catch (error) {
      log?.call('TWP:bench ${expectation.file} failed: $error');
      rows.add(BenchRow(
        expectation: expectation,
        detectedLabel: '(error)',
        confidence: 0,
        category: RecycleCategory.trash,
        elapsedMs: 0,
        detectionCount: 0,
        anyLabelHit: false,
        anyCategoryHit: false,
        topIsWasteRelevant: false,
        error: '$error',
      ));
    }
  }
  detector.dispose();

  return BenchReport(
    rows: rows,
    detectorLoaded: true,
    elapsedMs: stopwatch.elapsedMilliseconds,
    imageDirectory: imageDirectory,
  );
}

/// The highest-confidence box — the same choice the scanner makes for its scan
/// headline. Ties go to the larger box.
YoloDetection? primaryDetection(List<YoloDetection> detections) {
  if (detections.isEmpty) return null;
  return detections.reduce((a, b) {
    if (b.confidence != a.confidence) {
      return b.confidence > a.confidence ? b : a;
    }
    return b.area > a.area ? b : a;
  });
}

/// The required seven-column table: image, expected label, expected category,
/// detected label (top-1), detected category (top-1), confidence, any_hit.
///
/// `any_hit` is `OK` when ANY detection on the image maps to the expected
/// category — the primary any-match metric that drives PASS/FAIL. The two
/// top-1 columns carry a `✗` when the top-confidence box alone misses, so a
/// row can read `OK` overall while the headline chip was still wrong.
String formatTable(BenchReport report) {
  const widths = <int>[26, 14, 17, 25, 25, 10, 8];
  String pad(String value, int width, {bool miss = false}) {
    final marker = miss ? ' ✗' : '';
    final room = width - marker.length;
    final text = value.length <= room
        ? value
        : '…${value.substring(value.length - room + 1)}';
    return '$text$marker'.padRight(width);
  }

  final buffer = StringBuffer()
    ..writeln(<String>[
      pad('image', widths[0]),
      pad('expected label', widths[1]),
      pad('expected category', widths[2]),
      pad('detected label (top-1)', widths[3]),
      pad('detected category (top-1)', widths[4]),
      pad('confidence', widths[5]),
      pad('any_hit', widths[6]),
    ].join('  '))
    ..writeln('-' * (widths.reduce((a, b) => a + b) + 2 * (widths.length - 1)));

  for (final row in report.rows) {
    final detected = row.missing
        ? '(missing)'
        : row.error != null
            ? '(error)'
            : row.detectedLabel;
    // A zero-detection image has no top-1 box at all, so both top-1 cells stay
    // blank rather than borrowing the trash fallback.
    final detectedCategory = !row.measurable || row.emptyDetection
        ? '-'
        : row.category.name;
    buffer.writeln(<String>[
      pad(row.file, widths[0]),
      pad(row.expectedLabel, widths[1]),
      pad(row.expectedCategory.name, widths[2]),
      pad(detected, widths[3], miss: row.measurable && !row.top1LabelHit),
      pad(detectedCategory, widths[4],
          miss: row.measurable && !row.emptyDetection && !row.top1CategoryHit),
      pad(row.measurable ? row.confidence.toStringAsFixed(3) : '-', widths[5]),
      pad(row.measurable ? (row.categoryHit ? 'OK' : 'MISS') : '-', widths[6]),
    ].join('  '));
  }
  return buffer.toString();
}

/// The bench verdict: table, both accuracy pairs, notes, PASS/FAIL against the
/// 80 % category-accuracy threshold.
String formatReport(BenchReport report) {
  final buffer = StringBuffer()..writeln(formatTable(report));

  if (report.skipReason != null) {
    buffer
      ..writeln('SKIPPED: ${report.skipReason}')
      ..writeln('UNMEASURED: nothing was scored, so there is no PASS/FAIL.');
    return buffer.toString();
  }

  final measured = report.measured.length;
  buffer
    ..writeln('images: ${report.rows.length} in manifest, $measured scored, '
        '${report.missingCount} missing, ${report.errorCount} errored')
    ..writeln('image directory   : ${report.imageDirectory}')
    ..writeln('elapsed           : ${report.elapsedMs} ms')
    ..writeln('label accuracy (any-match)    : '
        '${report.labelHits}/$measured (${percentText(report.labelAccuracy)})')
    ..writeln('category accuracy (any-match) : '
        '${report.categoryHits}/$measured '
        '(${percentText(report.categoryAccuracy)})')
    ..writeln('label accuracy (top-1)        : '
        '${report.top1LabelHits}/$measured '
        '(${percentText(report.top1LabelAccuracy)})')
    ..writeln('category accuracy (top-1)     : '
        '${report.top1CategoryHits}/$measured '
        '(${percentText(report.top1CategoryAccuracy)})')
    ..writeln('zero-detection images         : ${report.emptyDetectionCount} '
        '(each one scored wrong for label and category — no default-to-trash '
        'credit)')
    ..writeln('threshold         : ${percentText(categoryAccuracyThreshold)} '
        'category accuracy (any-match)');

  final notes = <String>[];
  for (final row in report.measured) {
    if (row.emptyDetection) {
      notes.add('  ${row.file}: zero detections — scored WRONG for label '
          '(${row.expectedLabel}) and for category '
          '(${row.expectedCategory.name})');
      continue;
    }
    if (!row.categoryHit) {
      notes.add('  ${row.file}: no detection maps to '
          '${row.expectedCategory.name} (expected ${row.expectedLabel}); '
          'top box was ${row.detectedLabel} '
          '(${row.confidence.toStringAsFixed(2)}) → ${row.category.name}');
    } else if (!row.labelHit) {
      notes.add('  ${row.file}: stream correct (any-match), expected label '
          '${row.expectedLabel} was not among the boxes; top box was '
          '${row.detectedLabel} (${row.confidence.toStringAsFixed(2)})');
    }
    if (!row.topIsWasteRelevant) {
      notes.add('  ${row.file}: top box ${row.detectedLabel} is not waste '
          'evidence (wasteRelevantFor == false)');
    }
  }
  if (notes.isNotEmpty) {
    buffer.writeln('notes (${notes.length}):');
    notes.forEach(buffer.writeln);
  }
  if (report.missingCount > 0) {
    buffer.writeln('MISSING: ${report.missingCount} image(s) not on disk under '
        '${report.imageDirectory} — re-run tool/fetch_test_images.sh');
  }
  final thresholdMet = report.categoryAccuracy >= categoryAccuracyThreshold;
  buffer.writeln('${report.passed ? 'PASS' : 'FAIL'}: category accuracy '
      '(any-match) ${percentText(report.categoryAccuracy)} '
      '${thresholdMet ? '>=' : '<'} ${percentText(categoryAccuracyThreshold)} '
      '(${report.categoryHits}/$measured); label accuracy (any-match) '
      '${percentText(report.labelAccuracy)} '
      '${report.labelAccuracy >= categoryAccuracyThreshold ? '>=' : '<'} '
      '${percentText(categoryAccuracyThreshold)} '
      '(${report.labelHits}/$measured)');
  if (!report.passed && thresholdMet) {
    buffer.writeln('  (the category threshold itself is met — FAIL comes from '
        '${report.errorCount} errored / ${report.missingCount} '
        'missing image(s))');
  }
  return buffer.toString();
}

/// Percentage with one decimal — the one place the bench rounds.
String percentText(double value) => '${(value * 100).toStringAsFixed(1)}%';

/// Pretty-prints a manifest row — used for log headers before the table.
String describeExpectation(BenchExpectation expectation) =>
    '${expectation.file} → ${expectation.label} (${expectation.category.name})';

/// How many images the manifest asks for, without touching the detector.
int manifestImageCount(String manifestPath) =>
    loadManifest(File(manifestPath).readAsStringSync()).length;

/// Image directory the bench reads from, in priority order: an explicit
/// override, `--dart-define=BENCH_DIR=…`, a `BENCH_DIR` environment value, then
/// the repository-relative default.
Directory resolveImageDirectory([String? override]) {
  final candidates = <String>[
    if (override != null && override.isNotEmpty) override,
    const String.fromEnvironment('BENCH_DIR'),
    Platform.environment['BENCH_DIR'] ?? '',
    'assets/test_images',
    '../../../assets/test_images',
  ];
  for (final candidate in candidates) {
    if (candidate.isEmpty) continue;
    final directory = Directory(candidate);
    if (directory.existsSync()) return directory;
  }
  return Directory('assets/test_images');
}

/// True when a TFLite C library is loadable on this host.
///
/// `tflite_flutter` resolves its native library next to the running
/// executable, so this is a cheap pre-flight before the bench pretends to run.
bool tfliteAvailableOnHost() {
  const libraryNames = <String>[
    'libtensorflowlite_c-linux.so',
    'libtensorflowlite_c.so',
    'libtensorflowlite_c-mac.dylib',
    'libtensorflowlite_c-win.dll',
    'libtensorflowlite_jni.so',
  ];
  for (final name in libraryNames) {
    try {
      DynamicLibrary.open(name);
      return true;
    } on Object {
      continue;
    }
  }
  return false;
}

/// Host entry point: `flutter test tool/detection_bench.dart`.
///
/// The bench is one test so `flutter test` reports PASS/FAIL with a real exit
/// code; when the prerequisites are absent (images not fetched yet, or no
/// TFLite on this host) it skips with the reason instead of failing a run that
/// measured nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final override = _argValue(Platform.executableArguments, '--root') ??
      Platform.environment['BENCH_DIR'];
  final imageDir = resolveImageDirectory(override);
  final manifestPath = '${imageDir.path}/manifest.json';
  final skip = _preflightSkipReason(imageDir, manifestPath);

  test(
    'COCO val2017 detection bench (>= '
    '${(categoryAccuracyThreshold * 100).toStringAsFixed(0)}% category accuracy)',
    () async {
      final report = await runBench(
        imageDirectory: imageDir.path,
        manifestPath: manifestPath,
        log: debugPrint,
      );
      debugPrint(formatReport(report));
      if (!report.detectorLoaded || report.rows.isEmpty) {
        return; // nothing to score — the skip reason above explains why
      }
      if (report.measured.isEmpty) {
        fail('no image could be scored: ${report.errorCount} errored, '
            '${report.missingCount} missing');
      }
      expect(report.missingCount, 0,
          reason: 'every manifest image must be on disk under ${imageDir.path}');
      expect(report.categoryAccuracy, greaterThanOrEqualTo(categoryAccuracyThreshold),
          reason: 'category accuracy (any-match over all detections) is below '
              'the ${(categoryAccuracyThreshold * 100).toStringAsFixed(0)}% '
              'threshold; top-1 category accuracy was '
              '${percentText(report.top1CategoryAccuracy)}');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

String? _preflightSkipReason(Directory imageDir, String manifestPath) {
  if (!File(manifestPath).existsSync()) {
    return 'no manifest at $manifestPath — run tool/fetch_test_images.sh';
  }
  final jpegs = imageDir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.toLowerCase().endsWith('.jpg'))
      .length;
  if (jpegs == 0) {
    return 'no JPEGs in ${imageDir.path} — run tool/fetch_test_images.sh';
  }
  if (!tfliteAvailableOnHost()) {
    return 'this host has no libtensorflowlite_c shared library, so the TFLite '
        'interpreter cannot start here. Run the same bench on a device with:\n'
        '        flutter test integration_test/on_device_detection_test.dart '
        '-d <emulator-id>';
  }
  return null;
}

/// Minimal `--key value` reader; the bench is invoked as a test, so its own
/// arguments arrive appended to the executable's.
String? _argValue(List<String> args, String key) {
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == key) return args[i + 1];
  }
  return null;
}

/// Image directory for the on-device runner (same resolution rules).
Directory benchImageDirectory([String? override]) =>
    resolveImageDirectory(override ?? const String.fromEnvironment('BENCH_DIR'));
