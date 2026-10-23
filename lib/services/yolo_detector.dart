/// YOLOv5 / YOLOv8 / YOLO26 TFLite detector for the Township of Tomorrow waste
/// scanner.
///
/// Fully on-device and offline: letterbox → normalise → TFLite invoke → decode
/// → class-agnostic NMS, with boxes returned in ORIGINAL image pixels.
///
/// The graph layout is auto-detected at [YoloDetector.load] time rather than
/// hard-coded, because YOLO `.tflite` exports differ in both axes:
///
/// * input `[1,H,W,3]` (NHWC) or `[1,3,H,W]` (NCHW) — the letterbox target is
///   read from the tensor itself, so a 320, 416 or 640 export all work. Only a
///   tensor with dynamic (-1) dimensions falls back to [defaultLetterboxSize];
/// * output `[1,N,85]` → YOLOv5 head, `score = objectness × class probability`;
/// * output `[1,84,N]` → YOLOv8 / YOLO26 head: transposed, WITHOUT objectness.
///
/// Which graph is opened comes from `assets/models/registry.json`: the
/// YOLO-family entry marked `"role": "primary"` is tried first and the entry
/// marked `"role": "fallback"` (or [defaultAssetPath] when the registry itself
/// is unavailable) takes over when the primary asset is missing or its tensor
/// layout is unusable — so a build that does not bundle the primary behaves
/// exactly as it did before the primary existed.
///
/// Loading is split so it also works off the main isolate: [YoloModelAssets]
/// resolves asset **bytes** where `rootBundle` is valid, and
/// [YoloDetector.loadChain] builds interpreters from those bytes with
/// `Interpreter.fromBuffer` — pure FFI, no bindings, safe inside
/// `Isolate.run`. Feeding is derived from the live tensors (shape, dtype, byte
/// count, and quantisation for int8/uint8 graphs) rather than assumed, so a
/// graph the runtime cannot accept is rejected at load time with the numbers
/// instead of failing mid-`Invoke`.
///
/// Both shipped graphs are non-end2end v8/v26-style exports, decoded by the same
/// code path ([YoloDetector.decodeMatrix]):
///
/// * `assets/models/yolo26n_int8.tflite` (primary) — declares `[1,3,640,640]` in
///   (NCHW, float32) / `[1,84,8400]` out float32, int8 weights;
/// * `assets/models/yolo_detect_fp16.tflite` (fallback) — declares
///   `[1,640,640,3]` in (NHWC, float32) / `[1,84,8400]` out float32
///   (8400 = 80² + 40² + 20² anchors).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Scratch for the float32 → float16 input conversion (one element, reused —
/// the detector is a single-threaded object per isolate).
final Float32List _halfScratch = Float32List(1);
final Uint32List _halfScratchBits = _halfScratch.buffer.asUint32List();

/// A single detection, in ORIGINAL image pixel coordinates (origin top-left).
class YoloDetection {
  /// Field order mirrors the declaration order: label, confidence, x1, y1, x2, y2.
  const YoloDetection(
    this.label,
    this.confidence,
    this.x1,
    this.y1,
    this.x2,
    this.y2,
  );

  /// Same payload, named-argument spelling.
  const YoloDetection.named({
    required this.label,
    required this.confidence,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  /// COCO (or model-specific) class name, e.g. `bottle`.
  final String label;

  /// Final score in `0..1` — already `objectness × class probability` when the
  /// head carries an objectness column.
  final double confidence;

  /// Left edge, in source-image pixels.
  final double x1;

  /// Top edge, in source-image pixels.
  final double y1;

  /// Right edge, in source-image pixels.
  final double x2;

  /// Bottom edge, in source-image pixels.
  final double y2;

  double get width => x2 - x1;
  double get height => y2 - y1;
  double get area => width * height;
  double get centerX => (x1 + x2) / 2;
  double get centerY => (y1 + y2) / 2;

  @override
  String toString() => 'YoloDetection($label ${confidence.toStringAsFixed(3)} '
      '[${x1.toStringAsFixed(1)}, ${y1.toStringAsFixed(1)} → '
      '${x2.toStringAsFixed(1)}, ${y2.toStringAsFixed(1)}])';
}

/// One `models[]` entry of `assets/models/registry.json`.
///
/// Only the fields this detector needs are lifted; unknown keys (e.g.
/// `anchorScale` on the EfficientDet entry) are ignored on purpose so one
/// registry can serve every engine.
class YoloModelEntry {
  const YoloModelEntry({
    required this.id,
    required this.file,
    this.labels = '',
    this.format = '',
    this.role = '',
    this.engine = '',
    this.inputSize = const <int>[],
    this.classes = 0,
    this.outputLayout = '',
    this.license = '',
    this.note = '',
    this.sha256 = '',
    this.source = '',
  });

  /// Reads one registry entry; missing keys fall back to empty values and a
  /// wrong-typed key is skipped rather than throwing.
  factory YoloModelEntry.fromJson(Map<String, dynamic> json) {
    String str(String key) {
      final value = json[key];
      return value is String ? value : '';
    }

    final rawSize = json['inputSize'];
    return YoloModelEntry(
      id: str('id'),
      file: str('file'),
      labels: str('labels'),
      format: str('format'),
      role: str('role'),
      engine: str('engine'),
      inputSize: rawSize is List
          ? <int>[
              for (final side in rawSize)
                if (side is num) side.toInt(),
            ]
          : const <int>[],
      classes: json['classes'] is num ? (json['classes'] as num).toInt() : 0,
      outputLayout: str('outputLayout'),
      license: str('license'),
      note: str('note'),
      sha256: str('sha256'),
      source: str('source'),
    );
  }

  /// Directory every model asset shipped with the app lives in.
  static const String assetDir = 'assets/models/';

  /// Registry id, e.g. `yolo26n-int8`.
  final String id;

  /// Model file name inside [assetDir] (a value that already carries a path is
  /// used verbatim, so the registry keeps working if models move).
  final String file;

  /// Label table file name inside [assetDir]; empty means "use the caller's".
  final String labels;

  /// Engine family: `yolo`, `efficientdet`, … Only `yolo*` entries are opened
  /// by [YoloDetector].
  final String format;

  /// `primary` / `fallback` / `opt-in` / empty. Empty means the entry is listed
  /// for documentation only and is never auto-loaded.
  final String role;

  /// Human-readable engine name for logs and [YoloDetector.engineName].
  final String engine;

  /// `[height, width]` the graph declares, for documentation.
  final List<int> inputSize;

  /// Class count the head carries (`80` for the COCO exports).
  final int classes;

  /// Head layout family, `v8` for the transposed `[1,4+C,N]` export.
  final String outputLayout;

  /// Upstream licence of the weights.
  final String license;

  /// Free-form provenance / verification note.
  final String note;

  /// SHA-256 of the model file as bundled, for provenance and verdict logs.
  final String sha256;

  /// Upstream download URL the file came from.
  final String source;

  /// `assets/models/<file>`.
  String get assetPath => file.isEmpty
      ? ''
      : (file.contains('/') ? file : '$assetDir$file');

  /// `assets/models/<labels>`, empty when the entry names no label table.
  String get labelAssetPath => labels.isEmpty
      ? ''
      : (labels.contains('/') ? labels : '$assetDir$labels');

  /// True for entries this detector may open.
  bool get isYolo => format.startsWith('yolo');

  /// True when the entry is this family's first choice.
  bool get isPrimary => role == 'primary';

  /// True when the entry is the documented fallback.
  bool get isFallback => role == 'fallback';
}

/// Parsed `assets/models/registry.json`.
class YoloModelRegistry {
  const YoloModelRegistry({required this.entries, this.comment = ''});

  /// Bundled registry asset.
  static const String assetPath = 'assets/models/registry.json';

  /// Parses the registry. Throws [FormatException] when the JSON root is not an
  /// object, so a corrupt file degrades to the caller's own default (the caller
  /// catches) instead of silently selecting nothing.
  factory YoloModelRegistry.parse(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('registry root is not a JSON object');
    }
    final raw = decoded['models'];
    return YoloModelRegistry(
      comment: decoded['comment'] is String ? decoded['comment'] as String : '',
      entries: <YoloModelEntry>[
        if (raw is List)
          for (final item in raw)
            if (item is Map)
              YoloModelEntry.fromJson(item.cast<String, dynamic>()),
      ],
    );
  }

  /// Reads the bundled registry through `rootBundle`.
  static Future<YoloModelRegistry> load() async =>
      YoloModelRegistry.parse(await rootBundle.loadString(assetPath));

  /// Registry `comment`, kept for diagnostics.
  final String comment;

  /// Every entry, in file order.
  final List<YoloModelEntry> entries;

  /// Entries belonging to the YOLO family, in file order.
  List<YoloModelEntry> get yoloEntries =>
      <YoloModelEntry>[for (final entry in entries) if (entry.isYolo) entry];

  /// The YOLO-family entry to open first: the one marked `"role": "primary"`,
  /// else the first YOLO entry (the "tried top to bottom" rule).
  YoloModelEntry? get yoloPrimary {
    final yolo = yoloEntries;
    for (final entry in yolo) {
      if (entry.isPrimary) return entry;
    }
    return yolo.isEmpty ? null : yolo.first;
  }

  /// The YOLO-family entry marked `"role": "fallback"`, when one is declared.
  YoloModelEntry? get yoloFallback {
    for (final entry in yoloEntries) {
      if (entry.isFallback) return entry;
    }
    return null;
  }

  /// Entry whose `file`/asset path matches [fileOrPath] (basename or full path).
  YoloModelEntry? entryForFile(String fileOrPath) {
    for (final entry in entries) {
      if (entry.file == fileOrPath || entry.assetPath == fileOrPath) {
        return entry;
      }
    }
    return null;
  }
}

/// One step of the ordered asset chain [YoloDetector.load] walks.
class YoloModelCandidate {
  const YoloModelCandidate({
    required this.assetPath,
    required this.labelAssetPaths,
    this.entryId = '',
    this.role = '',
    this.engine = '',
    this.isFallback = false,
  });

  /// Graph to open, e.g. `assets/models/yolo26n_int8.tflite`.
  final String assetPath;

  /// Label tables to try, in order; the first that loads wins.
  final List<String> labelAssetPaths;

  /// Registry id this candidate came from, empty for a caller-supplied asset.
  final String entryId;

  /// Registry role the candidate was built from (`primary`, `candidate`,
  /// `fallback`), or the chain position (`fallback` for the last-resort
  /// candidate) when the asset is not registered.
  final String role;

  /// Registry engine label, empty when the graph is not in the registry.
  final String engine;

  /// True for the candidate that re-establishes the pre-primary behaviour.
  final bool isFallback;

  /// [YoloDetector.engineName] for this candidate.
  String get engineName => engine.isEmpty
      ? YoloDetector.defaultEngineName
      : '$engine · TFLite · on-device';

  @override
  String toString() =>
      'YoloModelCandidate($assetPath${isFallback ? ' · fallback' : ''})';
}

/// One candidate resolved to bytes + labels **where `rootBundle` works**, so an
/// interpreter can be built anywhere, with no Flutter bindings.
///
/// Why this exists: `Interpreter.fromAsset` (and every `rootBundle` read) needs
/// `ServicesBinding.instance`, which only exists in the isolate that called
/// `WidgetsFlutterBinding.ensureInitialized()`. A worker spawned by
/// `Isolate.run` has no binding, so asset loading there fails with *"Binding has
/// not yet been initialized"* whichever candidate is tried. The contract is:
///
/// * [resolveChain] — **main isolate only**: walks [YoloDetector.candidateChain],
///   reads each asset through `rootBundle`, keeps the ones that really exist and
///   are real TFLite flatbuffers, and materialises them (bytes + a JSON manifest)
///   into a temp cache directory;
/// * [loadCached] — **binding-free**: rebuilds the same chain from that cache,
///   so a background isolate can load the model without any binding;
/// * [YoloDetector.loadChain] — **binding-free**: builds interpreters straight
///   from in-memory bytes via `Interpreter.fromBuffer`, which is what a worker
///   that receives the chain from the main isolate uses.
class YoloModelAssets {
  const YoloModelAssets({
    required this.assetPath,
    required this.modelBytes,
    required this.labels,
    this.labelAssetPath = '',
    this.entryId = '',
    this.role = '',
    this.engine = '',
    this.isFallback = false,
  });

  /// Cache directory (under [Directory.systemTemp]) the resolved chain is
  /// materialised into; readable from any isolate.
  static const String cacheDirName = 'township_models';

  /// Manifest file inside that directory, listing the materialised chain.
  static const String manifestFileName = 'chain.json';

  /// TFLite flatbuffer magic, at byte offset 4 — spelled out numerically so no
  /// string encoding can mangle it.
  static const List<int> flatbufferMagic = <int>[0x54, 0x46, 0x4C, 0x33];

  /// `assets/models/<file>` this candidate came from.
  final String assetPath;

  /// Raw model bytes, exactly as bundled.
  final Uint8List modelBytes;

  /// Label table, already parsed (`???` holes removed).
  final List<String> labels;

  /// Label asset the table was read from, empty when none resolved.
  final String labelAssetPath;

  /// Registry id, empty for a caller-supplied asset.
  final String entryId;

  /// Registry role, `fallback` for the last-resort candidate.
  final String role;

  /// Registry engine label.
  final String engine;

  /// True for the candidate that re-establishes the pre-primary behaviour.
  final bool isFallback;

  /// [YoloDetector.engineName] for this candidate.
  String get engineName => engine.isEmpty
      ? YoloDetector.defaultEngineName
      : '$engine · TFLite · on-device';

  /// True when the bytes really look like a TFLite flatbuffer: no ZIP header and
  /// the `TFL3` magic at offset 4. A renamed archive cannot be interpreted, so
  /// this is checked before a candidate is ever offered to the interpreter.
  bool get isFlatbuffer {
    final bytes = modelBytes;
    if (bytes.length < 8) return false;
    if (bytes[0] == 0x50 && bytes[1] == 0x4B) return false; // 'PK' → ZIP
    for (var i = 0; i < flatbufferMagic.length; i++) {
      if (bytes[4 + i] != flatbufferMagic[i]) return false;
    }
    return true;
  }

  /// File name this candidate is materialised under.
  String get cacheFileName => YoloDetector.tempFileNameFor(assetPath);

  /// Splits a label table into names, dropping blanks and COCO's `???` holes.
  static List<String> parseLabels(String source) => source
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && line != '???')
      .toList(growable: false);

  /// Manifest entry for this candidate (labels inline, so a reader needs no
  /// bundle access at all).
  Map<String, Object?> toJson() => <String, Object?>{
        'assetPath': assetPath,
        'file': cacheFileName,
        'entryId': entryId,
        'role': role,
        'engine': engine,
        'isFallback': isFallback,
        'labelAssetPath': labelAssetPath,
        'labels': labels,
        'bytes': modelBytes.length,
      };

  /// Cache directory, created on demand.
  static Future<Directory> cacheDirectory([Directory? override]) async {
    final directory =
        override ?? Directory('${Directory.systemTemp.path}/$cacheDirName');
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// MAIN-ISOLATE ONLY (the default loaders read through `rootBundle`).
  ///
  /// Returns the ordered candidates that actually exist, each with its bytes and
  /// label table. Candidates whose asset is missing — or whose bytes are not a
  /// TFLite flatbuffer — are dropped, so the fallback graph is what remains when
  /// the primary was never bundled. [loadBytes]/[loadString] let host tests drive
  /// this exact code path with a stub bundle.
  static Future<List<YoloModelAssets>> resolveChain({
    String assetPath = YoloDetector.defaultAssetPath,
    String labelAssetPath = YoloDetector.defaultLabelAssetPath,
    bool useRegistry = true,
    Future<ByteData> Function(String asset)? loadBytes,
    Future<String> Function(String asset)? loadString,
    Directory? cacheDirectory,
    bool materialise = true,
  }) async {
    final readBytes = loadBytes ?? rootBundle.load;
    final readString = loadString ?? rootBundle.loadString;

    YoloModelRegistry? registry;
    if (useRegistry) {
      try {
        registry = YoloModelRegistry.parse(
            await readString(YoloModelRegistry.assetPath));
      } catch (error) {
        debugPrint('TWP:yolo registry unavailable ($error) — using $assetPath');
      }
    }

    final candidates = YoloDetector.candidateChain(
      assetPath: assetPath,
      labelAssetPath: labelAssetPath,
      registry: registry,
    );

    final resolved = <YoloModelAssets>[];
    for (final candidate in candidates) {
      final ByteData data;
      try {
        data = await readBytes(candidate.assetPath);
      } catch (error) {
        debugPrint('TWP:yolo asset "${candidate.assetPath}" not bundled ($error)');
        continue;
      }
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      var labels = const <String>[];
      var labelHit = '';
      for (final path in candidate.labelAssetPaths) {
        try {
          final parsed = parseLabels(await readString(path));
          if (parsed.isNotEmpty) {
            labels = parsed;
            labelHit = path;
            break;
          }
        } catch (error) {
          debugPrint('TWP:yolo label asset "$path" unavailable ($error)');
        }
      }

      final assets = YoloModelAssets(
        assetPath: candidate.assetPath,
        modelBytes: bytes,
        labels: labels,
        labelAssetPath: labelHit,
        entryId: candidate.entryId,
        role: candidate.role,
        engine: candidate.engine,
        isFallback: candidate.isFallback,
      );
      if (!assets.isFlatbuffer) {
        debugPrint('TWP:yolo "${candidate.assetPath}" is not a TFLite flatbuffer '
            '(${bytes.length} B) — skipped');
        continue;
      }
      debugPrint('TWP:yolo resolved ${candidate.assetPath} '
          '(${bytes.length} B, ${labels.length} labels, '
          'role=${candidate.role.isEmpty ? 'unregistered' : candidate.role})');
      resolved.add(assets);
    }

    if (resolved.isEmpty) {
      throw StateError('YoloModelAssets.resolveChain: none of '
          '${candidates.map((c) => c.assetPath).join(', ')} could be read');
    }
    if (materialise) {
      await _materialise(resolved, cacheDirectory);
    }
    return resolved;
  }

  /// BINDING-FREE: rebuilds the chain from the materialised cache. Returns an
  /// empty list when the main isolate has not resolved anything yet — a worker
  /// isolate then reports that and the app falls back to the main isolate, which
  /// is exactly the behaviour it had before.
  static Future<List<YoloModelAssets>> loadCached({Directory? directory}) async {
    final dir =
        directory ?? Directory('${Directory.systemTemp.path}/$cacheDirName');
    final manifest = File('${dir.path}/$manifestFileName');
    if (!manifest.existsSync()) return const <YoloModelAssets>[];

    final Object? decoded = jsonDecode(await manifest.readAsString());
    if (decoded is! Map) return const <YoloModelAssets>[];
    final raw = decoded['chain'];
    if (raw is! List) return const <YoloModelAssets>[];

    final chain = <YoloModelAssets>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final entry = item.cast<String, dynamic>();
      final file = entry['file'];
      if (file is! String) continue;
      final modelFile = File('${dir.path}/$file');
      if (!modelFile.existsSync()) continue;
      final bytes = await modelFile.readAsBytes();
      final rawLabels = entry['labels'];
      final assets = YoloModelAssets(
        assetPath:
            entry['assetPath'] is String ? entry['assetPath'] as String : '',
        modelBytes: bytes,
        labels: <String>[
          if (rawLabels is List)
            for (final label in rawLabels)
              if (label is String) label,
        ],
        labelAssetPath: entry['labelAssetPath'] is String
            ? entry['labelAssetPath'] as String
            : '',
        entryId: entry['entryId'] is String ? entry['entryId'] as String : '',
        role: entry['role'] is String ? entry['role'] as String : '',
        engine: entry['engine'] is String ? entry['engine'] as String : '',
        isFallback: entry['isFallback'] == true,
      );
      if (!assets.isFlatbuffer) continue;
      chain.add(assets);
    }
    if (chain.isNotEmpty) {
      debugPrint('TWP:yolo using materialised chain in ${dir.path} '
          '(${chain.map((c) => c.assetPath.split('/').last).join(', ')})');
    }
    return chain;
  }

  /// Writes the resolved chain (bytes + manifest) into the temp cache so any
  /// isolate can pick it up. Best effort: failing here only costs the worker
  /// path, never correctness.
  static Future<void> _materialise(
      List<YoloModelAssets> chain, Directory? override) async {
    try {
      final dir = await cacheDirectory(override);
      for (final assets in chain) {
        final file = File('${dir.path}/${assets.cacheFileName}');
        if (!file.existsSync() ||
            file.lengthSync() != assets.modelBytes.length) {
          await file.writeAsBytes(assets.modelBytes, flush: true);
        }
      }
      final manifest = File('${dir.path}/$manifestFileName');
      await manifest.writeAsString(
        jsonEncode(<String, Object?>{
          'version': 1,
          'chain': <Map<String, Object?>>[
            for (final assets in chain) assets.toJson(),
          ],
        }),
        flush: true,
      );
      debugPrint(
          'TWP:yolo materialised ${chain.length} model(s) into ${dir.path}');
    } catch (error) {
      debugPrint('TWP:yolo could not materialise the chain ($error)');
    }
  }
}

/// Head geometry of a YOLO prediction matrix: [rows] anchors × [cols] values,
/// [transposed] for the `[1,C,N]` v8/v26 spelling.
class YoloHead {
  const YoloHead({
    required this.rows,
    required this.cols,
    required this.transposed,
    required this.hasObjectness,
    required this.classCount,
  });

  /// The "not loaded yet" value.
  static const YoloHead empty = YoloHead(
    rows: 0,
    cols: 0,
    transposed: false,
    hasObjectness: true,
    classCount: 0,
  );

  /// Resolves the head from the output tensor's two trailing axes plus the
  /// label table — the rules the decode path has always used:
  ///
  /// * the smaller axis is the stride (`[1,84,8400]` → 8400 anchors, 84 values);
  /// * a stride of `4 + 1 + classes` is a YOLOv5 head carrying objectness,
  ///   otherwise the class columns start at 4 (v8/v26).
  static YoloHead resolve({
    required int first,
    required int second,
    required int labelCount,
  }) {
    final transposed = first < second;
    final rows = transposed ? second : first;
    final cols = transposed ? first : second;

    bool hasObjectness;
    int classCount;
    if (labelCount > 0) {
      hasObjectness = cols == 4 + 1 + labelCount;
      classCount = cols - (hasObjectness ? 5 : 4);
    } else {
      hasObjectness = cols == 85;
      classCount = cols - (hasObjectness ? 5 : 4);
    }
    if (classCount < 1) {
      hasObjectness = cols >= 5;
      classCount = cols - (hasObjectness ? 5 : 4);
    }
    return YoloHead(
      rows: rows,
      cols: cols,
      transposed: transposed,
      hasObjectness: hasObjectness,
      classCount: classCount,
    );
  }

  /// Prediction rows (anchors).
  final int rows;

  /// Values per row (`4 + classes`, `+1` when [hasObjectness]).
  final int cols;

  /// True when the tensor is `[1,C,N]`.
  final bool transposed;

  /// True when a YOLOv5-style objectness column precedes the classes.
  final bool hasObjectness;

  /// Class columns decoded per row.
  final int classCount;

  /// First class column.
  int get classBase => hasObjectness ? 5 : 4;

  /// Distance between consecutive values of one row: the row count when
  /// transposed, else `1` (rows are contiguous).
  int get step => transposed ? rows : 1;
}

/// Runtime verdicts: which resolved candidate **this device** refused to execute.
///
/// A graph that fails at the native level (`kTfLiteError`, which tflite_flutter
/// reports as a bare `Bad state: failed precondition` — e.g. an export whose
/// tensors the bundled TFLite cannot even allocate) is recorded next to the
/// materialised chain, keyed by a content fingerprint. Cold starts and the
/// per-scan worker isolates then open the fallback directly instead of paying a
/// failed load plus a failed invoke every time — while the registry keeps
/// declaring the primary, and the log keeps saying why it was skipped.
class YoloRuntimeVerdict {
  /// File name inside the materialised cache directory.
  static const String fileName = 'runtime_verdict.json';

  /// Content fingerprint of [assets]: byte length plus an FNV-1a hash over the
  /// first and last 4 KiB. Replacing the model invalidates its own verdict, and
  /// no crypto dependency is needed.
  static String get runtimeIdentity {
    try {
      return version;
    } catch (_) {
      return 'unknown';
    }
  }

  /// Content fingerprint of [assets]: byte length plus an FNV-1a hash over the
  /// first and last 4 KiB, scoped to [runtimeIdentity]. Replacing the model — or
  /// bumping the native runtime, which is the documented unblock path — therefore
  /// invalidates the old verdict instead of masking the fix. No crypto dependency
  /// is needed.
  static String fingerprintOf(YoloModelAssets assets) {
    final bytes = assets.modelBytes;
    var hash = 0x811c9dc5;
    void mix(int byte) {
      hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF;
    }

    final window = math.min(4096, bytes.length);
    for (var i = 0; i < window; i++) {
      mix(bytes[i]);
    }
    for (var i = math.max(0, bytes.length - window); i < bytes.length; i++) {
      mix(bytes[i]);
    }
    return '${assets.assetPath.replaceAll('/', '_')}:${bytes.length}:'
        '${hash.toRadixString(16)}:$runtimeIdentity';
  }

  /// All recorded verdicts (fingerprint → reason). Empty when nothing was
  /// recorded yet, or when the file is unreadable.
  static Future<Map<String, String>> load({Directory? directory}) async {
    try {
      final file = File(
          '${(await YoloModelAssets.cacheDirectory(directory)).path}/$fileName');
      if (!file.existsSync()) return const <String, String>{};
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const <String, String>{};
      final raw = decoded['verdicts'];
      if (raw is! Map) return const <String, String>{};
      return <String, String>{
        for (final entry in raw.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } catch (error) {
      debugPrint('TWP:yolo verdict store unreadable ($error)');
      return const <String, String>{};
    }
  }

  /// True when [assets] was already refused on this device.
  static Future<bool> isBlocked(YoloModelAssets assets,
      {Directory? directory}) async {
    final verdicts = await load(directory: directory);
    return verdicts.containsKey(fingerprintOf(assets));
  }

  /// Records that [assets] could not run here, with the native reason.
  static Future<void> record(String fingerprint, Object reason,
      {Directory? directory}) async {
    try {
      final dir = await YoloModelAssets.cacheDirectory(directory);
      final verdicts = Map<String, String>.of(await load(directory: dir));
      verdicts[fingerprint] = '$reason';
      await File('${dir.path}/$fileName').writeAsString(
        jsonEncode(<String, Object?>{'version': 1, 'verdicts': verdicts}),
        flush: true,
      );
      debugPrint('TWP:yolo recorded runtime verdict for $fingerprint ($reason)');
    } catch (error) {
      debugPrint('TWP:yolo could not record a runtime verdict ($error)');
    }
  }
}

/// Letterbox bookkeeping needed to map a decoded box back to source pixels.
class YoloLetterbox {
  const YoloLetterbox({
    required this.inputWidth,
    required this.inputHeight,
    this.scale = 1.0,
    this.padX = 0,
    this.padY = 0,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  /// Graph input width (letterboxed).
  final int inputWidth;

  /// Graph input height (letterboxed).
  final int inputHeight;

  /// Uniform scale applied to the source image.
  final double scale;

  /// Left padding added to centre the scaled image.
  final int padX;

  /// Top padding added to centre the scaled image.
  final int padY;

  /// Width of the image the boxes are reported in.
  final int sourceWidth;

  /// Height of the image the boxes are reported in.
  final int sourceHeight;
}

/// Input-tensor geometry resolved from the graph's declared shape.
class YoloInputLayout {
  const YoloInputLayout({
    required this.width,
    required this.height,
    required this.isChw,
  });

  /// Letterbox width to feed.
  final int width;

  /// Letterbox height to feed.
  final int height;

  /// True for `[1,3,H,W]`.
  final bool isChw;
}

/// Loads one YOLO `.tflite` graph and turns [img.Image] frames into boxes.
///
/// ```dart
/// final detector = YoloDetector();
/// await detector.load();
/// final detections = await detector.detect(frame); // frame: img.Image
/// detector.dispose();
/// ```
class YoloDetector {
  YoloDetector({
    this.assetPath = defaultAssetPath,
    this.labelAssetPath = defaultLabelAssetPath,
    this.confidenceThreshold = defaultConfidenceThreshold,
    this.iouThreshold = defaultIouThreshold,
    this.maxDetections = defaultMaxDetections,
    this.letterboxSize = defaultLetterboxSize,
    this.threads = defaultThreads,
    this.useRegistry = true,
  });

  /// Fallback YOLO graph — the previously bundled asset, still shipped.
  ///
  /// Declares 640×640 in / 84×8400 out (transposed: 4 box coordinates + 80 class
  /// scores per anchor, no objectness column).
  static const String defaultAssetPath = 'assets/models/yolo_detect_fp16.tflite';

  /// 80 COCO names in ultralytics / COCO-train order.
  static const String defaultLabelAssetPath = 'assets/models/coco_labels.txt';

  /// Older spelling already shipped with the app, kept as a fallback.
  static const String fallbackLabelAssetPath = 'assets/models/coco-labels.txt';

  /// [engineName] before a graph is loaded, and for graphs that are not in the
  /// registry.
  static const String defaultEngineName = 'YOLO · TFLite · on-device';

  /// Candidates below this score are discarded before NMS.
  static const double defaultConfidenceThreshold = 0.25;

  /// Fallback score floor for the single relaxed retry described in [detect];
  /// used only when the pass at [confidenceThreshold] keeps nothing.
  static const double fallbackConfidenceThreshold = 0.05;

  /// Class-agnostic NMS IoU.
  static const double defaultIouThreshold = 0.50;

  /// Hard cap on returned boxes.
  static const int defaultMaxDetections = 64;

  /// Letterbox side used only when the graph leaves its input shape dynamic.
  static const int defaultLetterboxSize = 640;

  /// TFLite worker threads handed to the interpreter.
  static const int defaultThreads = 4;

  /// YOLOv5 letterbox padding value (mid grey).
  static const int letterboxPadValue = 114;

  /// Upper bound on the candidate pool handed to NMS (defensive; a COCO frame
  /// at 0.25 confidence yields a few dozen).
  static const int maxCandidates = 3000;

  /// Explicit graph to load. Consulted first when [useRegistry] is false, and
  /// always the last resort of the chain when it is true.
  final String assetPath;

  /// Primary labels asset; [fallbackLabelAssetPath] is tried when missing.
  final String labelAssetPath;

  /// Discard candidates below this score.
  final double confidenceThreshold;

  /// Class-agnostic NMS IoU threshold.
  final double iouThreshold;

  /// Cap on returned boxes.
  final int maxDetections;

  /// Fallback letterbox side for dynamic-shape graphs.
  final int letterboxSize;

  /// Interpreter thread count.
  final int threads;

  /// When true (the default) the graph named by the registry's primary YOLO
  /// entry is tried before [assetPath]. Set false to pin [assetPath] exactly.
  final bool useRegistry;

  Interpreter? _interpreter;
  Future<void>? _loading;

  List<String> _labels = const <String>[];
  int _inputWidth = 0;
  int _inputHeight = 0;
  bool _inputIsChw = false;

  /// Live input tensor dtype and size, plus the exact bytes [detect] feeds it.
  /// Everything here is read back from the graph, never assumed from the file
  /// name or the registry: a mismatch is what surfaced as a bare
  /// `Bad state: failed precondition` from inside `Interpreter.run`.
  TensorType _inputTensorType = TensorType.float32;
  int _inputTensorBytes = 0;
  double _inputScale = 0.0;
  int _inputZeroPoint = 0;
  Uint8List _inputFeed = Uint8List(0);

  /// Staging buffer: normalised RGB floats in the tensor's own NHWC/NCHW order.
  Float32List _inputBuffer = Float32List(0);

  /// Output side, sized from the live tensor rather than from arithmetic.
  Uint8List _outputBytes = Uint8List(0);
  Float32List? _decodedOutput;
  TensorType _outputTensorType = TensorType.float32;
  double _outputScale = 0.0;
  int _outputZeroPoint = 0;
  YoloHead _head = YoloHead.empty;

  /// Resolved candidate chain and the index currently loaded, so a native run
  /// failure swaps to the next graph once instead of failing the whole scan.
  List<YoloModelAssets> _chain = const <YoloModelAssets>[];
  int _chainIndex = -1;
  bool _swapAttempted = false;
  bool _reallocated = false;

  String _engineName = defaultEngineName;
  String _loadedAssetPath = '';
  String _loadedFingerprint = '';

  /// True once [load] has completed.
  bool get ready => _interpreter != null;

  /// Letterbox width actually fed to the graph.
  int get inputWidth => _inputWidth;

  /// Letterbox height actually fed to the graph.
  int get inputHeight => _inputHeight;

  /// Class columns decoded per box (`80` for the bundled COCO graphs).
  int get classCount => _head.classCount;

  /// True when the head carries an explicit objectness column (YOLOv5 style).
  bool get hasObjectness => _head.hasObjectness;

  /// True when the head is `[1,C,N]` (YOLOv8 / YOLO26 style transposed).
  bool get boxesTransposed => _head.transposed;

  /// Live input tensor dtype of the loaded graph.
  TensorType get inputTensorType => _inputTensorType;

  /// Live output tensor dtype of the loaded graph.
  TensorType get outputTensorType => _outputTensorType;

  /// Bytes the loaded graph declares for its input tensor.
  int get inputTensorBytes => _inputTensorBytes;

  /// Row count of the prediction matrix (`8400` for both bundled graphs).
  int get predictionCount => _head.rows;

  /// Label table, empty when every candidate falls back to `class #N`.
  List<String> get labels => List<String>.unmodifiable(_labels);

  /// Asset the loaded graph came from, empty until [load] succeeds.
  String get loadedAssetPath => _loadedAssetPath;

  /// Human-readable engine of the loaded graph, from the registry when known.
  String get engineName => _engineName;

  /// Loads the graph and labels. Safe to call repeatedly; concurrent callers
  /// share one load. Throws [StateError] when no asset in the chain is usable.
  Future<void> load() async {
    if (_interpreter != null) return;
    final pending = _loading;
    if (pending != null) return pending;
    final future = _load();
    _loading = future;
    try {
      await future;
    } finally {
      _loading = null;
    }
  }

  /// Resolves the model chain **in this isolate** (needs Flutter bindings) and
  /// loads the first candidate that works: the main-isolate entry point.
  Future<void> _load() async {
    final stopwatch = Stopwatch()..start();
    List<YoloModelAssets> chain;
    try {
      chain = await YoloModelAssets.resolveChain(
        assetPath: assetPath,
        labelAssetPath: labelAssetPath,
        useRegistry: useRegistry,
      );
    } catch (error) {
      // A worker isolate spawned by Isolate.run has no ServicesBinding, so
      // `rootBundle` — and therefore Interpreter.fromAsset — is unavailable
      // there. Consume the chain the main isolate materialised instead: that path
      // is pure dart:io + FFI and needs no binding at all.
      debugPrint('TWP:yolo asset resolution unavailable in this isolate '
          '($error) — trying the materialised cache');
      chain = _pinned(await YoloModelAssets.loadCached());
      if (chain.isEmpty) {
        throw StateError('YoloDetector: no rootBundle binding in this isolate '
            'and nothing materialised yet — resolve the chain on the main '
            'isolate (YoloModelAssets.resolveChain) and hand it to loadChain()');
      }
    }
    await loadChain(chain, stopwatch: stopwatch);
  }

  /// BINDING-FREE load: builds the interpreter straight from in-memory bytes.
  ///
  /// Safe in any isolate, because `Interpreter.fromBuffer` is pure FFI — this is
  /// what a worker that received the chain from the main isolate calls. Every
  /// candidate is tried in order and the first one whose tensors this detector
  /// can actually drive is adopted.
  Future<void> loadChain(List<YoloModelAssets> chain,
      {Stopwatch? stopwatch}) async {
    if (_interpreter != null) return;
    _chain = List<YoloModelAssets>.unmodifiable(chain);
    _chainIndex = -1;
    _swapAttempted = false;
    _reallocated = false;
    if (chain.isEmpty) {
      throw StateError('YoloDetector.loadChain: empty model chain');
    }
    final sw = stopwatch ?? (Stopwatch()..start());
    final errors = <String>[];
    for (var i = 0; i < chain.length; i++) {
      final candidate = chain[i];
      // A candidate this device already refused is skipped while a fallback is
      // still available; when nothing is left the chain still tries it, so the
      // real error is reported rather than hidden.
      if (i + 1 < chain.length &&
          await YoloRuntimeVerdict.isBlocked(candidate)) {
        debugPrint('TWP:yolo skipping "${candidate.assetPath}" — this device '
            'already refused it (recorded runtime verdict)');
        continue;
      }
      try {
        _adopt(_openCandidate(candidate), candidate, sw);
        _chainIndex = i;
        return;
      } catch (error) {
        errors.add('${candidate.assetPath}: $error');
        debugPrint('TWP:yolo candidate "${candidate.assetPath}" unusable ($error)');
        if (i + 1 < chain.length) {
          debugPrint('TWP:yolo falling back to "${chain[i + 1].assetPath}"');
        }
      }
    }
    throw StateError('YoloDetector: no usable model asset (tried '
        '${chain.map((candidate) => candidate.assetPath).join(', ')}): '
        '${errors.join(' | ')}');
  }

  /// Candidates matching a pinned [assetPath] (the registry-primary entry is only
  /// used for the default chain, so a pinned graph must not inherit it).
  List<YoloModelAssets> _pinned(List<YoloModelAssets> chain) {
    if (assetPath == defaultAssetPath) return chain;
    return <YoloModelAssets>[
      for (final assets in chain)
        if (assets.assetPath == assetPath) assets,
    ];
  }

  /// Builds an interpreter for one resolved candidate — no `rootBundle` involved.
  Interpreter _openCandidate(YoloModelAssets candidate) {
    if (!candidate.isFlatbuffer) {
      throw StateError('"${candidate.assetPath}" is not a TFLite flatbuffer '
          '(${candidate.modelBytes.length} B)');
    }
    final options = InterpreterOptions()..threads = threads;
    return Interpreter.fromBuffer(candidate.modelBytes, options: options);
  }

  /// Validates one candidate's tensors and adopts it; the previously loaded
  /// graph, if any, is only replaced once the new one is fully usable.
  void _adopt(
      Interpreter interpreter, YoloModelAssets candidate, Stopwatch stopwatch) {
    try {
      // Force the first AllocateTensors here, on the exact input shape, before
      // any tensor handle is read or written.
      //
      // Why: TFLite rewrites the graph while allocating — dynamic-range
      // quantisation inserts dequantise nodes and can move the tensor array — and
      // tflite_flutter caches `Tensor` wrappers on first access. Reading a tensor
      // before that rewrite leaves the cached handle pointing at stale memory, so
      // a perfect input copy lands nowhere and the native side reports
      // `Input tensor N lacks data`. `resizeInputTensor` clears those caches
      // (tflite_flutter nulls both handles), and allocating here makes the
      // rewrite happen before anything touches a tensor.
      final declared = interpreter.getInputTensor(0).shape;
      if (declared.isNotEmpty && declared.every((dimension) => dimension > 0)) {
        interpreter.resizeInputTensor(0, declared);
        interpreter.allocateTensors();
      }
    } catch (error) {
      debugPrint('TWP:yolo pre-allocation of "${candidate.assetPath}" failed '
          '($error)');
      interpreter.close();
      rethrow;
    }

    try {
      _labels = candidate.labels;
      _readInputLayout(interpreter);
      _readOutputLayout(interpreter);
    } catch (_) {
      interpreter.close();
      rethrow;
    }
    _interpreter = interpreter;
    _loadedAssetPath = candidate.assetPath;
    _loadedFingerprint = YoloRuntimeVerdict.fingerprintOf(candidate);
    _engineName = candidate.engineName;
    debugPrint('TWP:yolo loaded in=${_inputWidth}x$_inputHeight'
        '${_inputIsChw ? ' (CHW)' : ''} preds=${_head.rows} cols=${_head.cols} '
        'transposed=${_head.transposed} objectness=${_head.hasObjectness} '
        'classes=${_head.classCount} labels=${_labels.length} '
        'inType=${_inputTensorType.name} inBytes=$_inputTensorBytes '
        'outType=${_outputTensorType.name} outBytes=${_outputBytes.length} '
        'asset=${candidate.assetPath} '
        'role=${candidate.role.isEmpty ? 'unregistered' : candidate.role} '
        'rt=${YoloRuntimeVerdict.runtimeIdentity} '
        'in ${stopwatch.elapsedMilliseconds}ms');
  }

  /// Ordered assets this detector will try: the registry's primary YOLO entry
  /// first, then [assetPath] (the documented fallback). Pure with respect to the
  /// interpreter — [isPresent] lets tests simulate an asset that was not bundled.
  ///
  /// When [assetPath] is not [defaultAssetPath] the caller has pinned a graph on
  /// purpose, so the registry is not consulted at all.
  static List<YoloModelCandidate> candidateChain({
    String assetPath = defaultAssetPath,
    String labelAssetPath = defaultLabelAssetPath,
    YoloModelRegistry? registry,
    bool Function(String assetPath)? isPresent,
  }) {
    final present = isPresent ?? (_) => true;
    final chain = <YoloModelCandidate>[];

    void add(YoloModelCandidate candidate) {
      if (candidate.assetPath.isEmpty) return;
      for (final existing in chain) {
        if (existing.assetPath == candidate.assetPath) return;
      }
      chain.add(candidate);
    }

    final overridden = assetPath != defaultAssetPath;
    final primary = overridden ? null : registry?.yoloPrimary;
    if (primary != null &&
        primary.assetPath.isNotEmpty &&
        primary.assetPath != assetPath &&
        present(primary.assetPath)) {
      add(YoloModelCandidate(
        assetPath: primary.assetPath,
        labelAssetPaths: _labelChain(<String>[
          primary.labelAssetPath,
          labelAssetPath,
          fallbackLabelAssetPath,
        ]),
        entryId: primary.id,
        role: primary.role.isEmpty ? 'primary' : primary.role,
        engine: primary.engine,
      ));
    }

    final fallbackEntry =
        overridden ? null : registry?.entryForFile(assetPath);
    add(YoloModelCandidate(
      assetPath: assetPath,
      labelAssetPaths: _labelChain(<String>[
        fallbackEntry?.labelAssetPath ?? '',
        labelAssetPath,
        fallbackLabelAssetPath,
      ]),
      entryId: fallbackEntry?.id ?? '',
      role: overridden ? 'pinned' : (fallbackEntry?.role ?? 'fallback'),
      engine: fallbackEntry?.engine ?? '',
      isFallback: true,
    ));
    return chain;
  }

  static List<String> _labelChain(List<String> paths) {
    final chain = <String>[];
    for (final path in paths) {
      if (path.isEmpty || chain.contains(path)) continue;
      chain.add(path);
    }
    return chain;
  }

  /// Scratch copy name for the fallback graph.
  static const String tempModelFileName = 'township_yolo_detect_fp16.tflite';

  /// Materialised-file name used for [asset]: the legacy constant for the
  /// fallback graph (so nothing changes there), the asset basename otherwise.
  static String tempFileNameFor(String asset) => asset == defaultAssetPath
      ? tempModelFileName
      : 'township_${asset.split('/').last}';

  /// Resolves the shape→(width, height, CHW) mapping of an input tensor.
  ///
  /// A graph that leaves its input dynamic is resized to
  /// `[1, letterboxSize, letterboxSize, 3]` before this is called, so the
  /// fallback below only matters for exports that still declare zeroed axes.
  static YoloInputLayout resolveInputLayout(
    List<int> shape, {
    int letterboxSize = defaultLetterboxSize,
  }) {
    var width = letterboxSize;
    var height = letterboxSize;
    var chw = false;
    if (shape.length == 4) {
      if (shape[3] == 3) {
        height = shape[1];
        width = shape[2];
      } else if (shape[1] == 3) {
        height = shape[2];
        width = shape[3];
        chw = true;
      }
    } else if (shape.length == 2) {
      // Flat dynamic input, e.g. [1, 1228800] — assume square RGB.
      final flat = shape[1] > 0 ? shape[1] : letterboxSize * letterboxSize * 3;
      final side = math.sqrt(flat / 3).round();
      width = height = side > 0 ? side : letterboxSize;
    }
    if (width <= 0 || height <= 0) {
      width = letterboxSize;
      height = letterboxSize;
    }
    return YoloInputLayout(width: width, height: height, isChw: chw);
  }

  /// Reads the graph input shape and dtype (pinning a dynamic shape to
  /// [letterboxSize]), then sizes the feed buffer **from the tensor itself**.
  ///
  /// A mismatch here used to surface far away as a bare
  /// `Bad state: failed precondition` from inside `Interpreter.run`; now it is
  /// caught at load time, with the numbers, so the candidate is rejected and the
  /// next one in the chain is tried.
  void _readInputLayout(Interpreter interpreter) {
    var shape = interpreter.getInputTensor(0).shape;
    final dynamicShape = shape.length == 4 &&
        (shape[1] <= 0 || shape[2] <= 0 || shape[3] <= 0);
    if (dynamicShape) {
      interpreter.resizeInputTensor(0, <int>[1, letterboxSize, letterboxSize, 3]);
      interpreter.allocateTensors();
      shape = interpreter.getInputTensor(0).shape;
    }

    final layout = resolveInputLayout(shape, letterboxSize: letterboxSize);
    _inputWidth = layout.width;
    _inputHeight = layout.height;
    _inputIsChw = layout.isChw;

    final live = interpreter.getInputTensor(0);
    _inputTensorType = live.type;
    _inputTensorBytes = live.numBytes();
    _inputScale = 0.0;
    _inputZeroPoint = 0;
    if (_inputTensorType == TensorType.int8 ||
        _inputTensorType == TensorType.uint8) {
      final params = live.params;
      _inputScale = params.scale;
      _inputZeroPoint = params.zeroPoint;
    }

    final elements = layout.height * layout.width * 3;
    final perElement = bytesPerElement(_inputTensorType);
    if (perElement == 0) {
      throw StateError('YoloDetector: unsupported input dtype '
          '${_inputTensorType.name} — expected float32, float16, int8 or uint8');
    }
    if (elements * perElement != _inputTensorBytes) {
      throw StateError('YoloDetector: input tensor ${live.shape} '
          '${_inputTensorType.name} declares $_inputTensorBytes B, but a '
          '${layout.width}x${layout.height}x3 image needs '
          '${elements * perElement} B');
    }
    _inputBuffer = Float32List(elements);
    _inputFeed =
        _inputTensorType == TensorType.float32 ? Uint8List(0) : Uint8List(_inputTensorBytes);
  }

  /// Bytes per element for the dtypes this detector can feed or read.
  static int bytesPerElement(TensorType type) {
    switch (type) {
      case TensorType.float32:
        return 4;
      case TensorType.float16:
        return 2;
      case TensorType.int8:
      case TensorType.uint8:
        return 1;
      default:
        return 0;
    }
  }

  /// Reads the graph head: layout, objectness presence, class count, dtype.
  void _readOutputLayout(Interpreter interpreter) {
    final tensor = interpreter.getOutputTensor(0);
    final shape = tensor.shape;
    if (shape.length != 3) {
      throw StateError(
          'YoloDetector: unsupported output rank ${shape.length} (shape $shape) — '
          'expected [1,N,C] or [1,C,N]');
    }
    if (bytesPerElement(tensor.type) == 0) {
      throw StateError(
          'YoloDetector: unsupported output dtype ${tensor.type} — expected '
          'float32, float16, int8 or uint8');
    }

    // [1,25200,85] → rows 25200, cols 85 (YOLOv5).
    // [1,84,8400]  → transposed: rows 8400, cols 84 (YOLOv8 / YOLO26).
    final head = YoloHead.resolve(
      first: shape[1],
      second: shape[2],
      labelCount: _labels.length,
    );
    if (head.rows <= 0 || head.cols <= 0) {
      throw StateError('YoloDetector: dynamic output shape $shape is not supported');
    }
    if (head.classCount < 1) {
      throw StateError(
          'YoloDetector: output stride ${head.cols} carries no class columns');
    }

    _head = head;
    _outputTensorType = tensor.type;
    _outputScale = 0.0;
    _outputZeroPoint = 0;
    if (_outputTensorType == TensorType.int8 ||
        _outputTensorType == TensorType.uint8) {
      final params = tensor.params;
      _outputScale = params.scale;
      _outputZeroPoint = params.zeroPoint;
    }
    _decodedOutput = null;
    _outputBytes = Uint8List(tensor.numBytes());

    final elements = head.rows * head.cols;
    final perElement = bytesPerElement(_outputTensorType);
    if (elements * perElement != _outputBytes.length) {
      throw StateError('YoloDetector: output tensor $shape '
          '${_outputTensorType.name} declares ${_outputBytes.length} B but '
          '$elements values x $perElement B need ${elements * perElement} B');
    }
  }

  /// Runs detection over an RGB [img.Image] and returns boxes in the pixel
  /// coordinates of that same image.
  ///
  /// If the loaded graph cannot execute on this runtime (a native `kTfLiteError`,
  /// which tflite_flutter surfaces as a bare `Bad state: failed precondition`),
  /// the next candidate of the resolved chain is adopted once and the frame is
  /// retried — so a primary export this TFLite build cannot run degrades to the
  /// fallback graph instead of failing the scan.
  Future<List<YoloDetection>> detect(img.Image rgb) async {
    if (_interpreter == null) {
      throw StateError('YoloDetector.load() must be awaited before detect()');
    }
    try {
      return await _detectOnce(rgb);
    } catch (error) {
      // Allocation-state failure: re-seat the tensors once on the same graph
      // before giving up on it (see the note in [_adopt]).
      if (!_reallocated) {
        _reallocated = true;
        try {
          final interpreter = _interpreter;
          if (interpreter != null) {
            final declared = interpreter.getInputTensor(0).shape;
            if (declared.isNotEmpty &&
                declared.every((dimension) => dimension > 0)) {
              interpreter.resizeInputTensor(0, declared);
              interpreter.allocateTensors();
              debugPrint('TWP:yolo re-seated tensors on "$_loadedAssetPath" '
                  'after ($error)');
              return await _detectOnce(rgb);
            }
          }
        } catch (retryError) {
          debugPrint('TWP:yolo retry on "$_loadedAssetPath" failed '
              '($retryError)');
        }
      }
      if (_swapAttempted) rethrow;
      debugPrint('TWP:yolo run failed on "$_loadedAssetPath" ($error)');
      if (_loadedFingerprint.isNotEmpty) {
        await YoloRuntimeVerdict.record(_loadedFingerprint, error);
      }
      final swapped = await _swapToNextCandidate();
      if (!swapped) rethrow;
      return _detectOnce(rgb);
    }
  }

  /// Adopts the next resolved candidate after a native run failure; false when
  /// none is left, in which case the caller rethrows the original error.
  Future<bool> _swapToNextCandidate() async {
    _swapAttempted = true;
    for (var index = _chainIndex + 1; index < _chain.length; index++) {
      final candidate = _chain[index];
      if (await YoloRuntimeVerdict.isBlocked(candidate)) {
        debugPrint('TWP:yolo skipping "${candidate.assetPath}" — blocked by a '
            'recorded runtime verdict');
        continue;
      }
      debugPrint('TWP:yolo switching to "${candidate.assetPath}"'
          '${candidate.isFallback ? ' (documented fallback)' : ''}');
      _interpreter?.close();
      _interpreter = null;
      _loadedAssetPath = '';
      try {
        _adopt(_openCandidate(candidate), candidate, Stopwatch()..start());
        _chainIndex = index;
        return true;
      } catch (error) {
        debugPrint('TWP:yolo candidate "${candidate.assetPath}" unusable ($error)');
      }
    }
    debugPrint('TWP:yolo no further candidate to switch to '
        '(${_chain.length} in the chain)');
    return false;
  }

  /// One inference pass over the currently loaded graph.
  Future<List<YoloDetection>> _detectOnce(img.Image rgb) async {
    final interpreter = _interpreter!;
    final sourceWidth = rgb.width;
    final sourceHeight = rgb.height;
    if (sourceWidth <= 0 || sourceHeight <= 0) return const <YoloDetection>[];

    // 1. Letterbox: one uniform scale for both axes, the leftover split evenly
    //    as grey padding. Scale and pad are kept so the inverse mapping below
    //    is exact.
    final scale = math.min(_inputWidth / sourceWidth, _inputHeight / sourceHeight);
    final scaledWidth = math.max(1, (sourceWidth * scale).round());
    final scaledHeight = math.max(1, (sourceHeight * scale).round());
    final padX = ((_inputWidth - scaledWidth) / 2).round();
    final padY = ((_inputHeight - scaledHeight) / 2).round();

    final canvas = img.Image(
      width: _inputWidth,
      height: _inputHeight,
      numChannels: 3,
    );
    img.fill(
      canvas,
      color: img.ColorRgb8(letterboxPadValue, letterboxPadValue, letterboxPadValue),
    );
    final resized = img.copyResize(
      rgb,
      width: scaledWidth,
      height: scaledHeight,
      interpolation: img.Interpolation.linear,
    );
    img.compositeImage(canvas, resized, dstX: padX, dstY: padY);

    // 2. Normalise to float32 0..1 (NHWC or NCHW, whichever the graph wants).
    _fillInput(canvas.getBytes(order: img.ChannelOrder.rgb));

    // 3. Invoke. The feed is built from the live tensor shape/dtype, so its byte
    //    count always matches what the graph declared (float32, float16, int8 or
    //    uint8); a raw ByteBuffer feed also skips per-element conversion.
    final stopwatch = Stopwatch()..start();
    interpreter.run(_feedInput(), _outputBytes.buffer);
    final inferenceMs = stopwatch.elapsedMilliseconds;

    // 4. Decode every prediction row at [confidenceThreshold] through the same
    //    matrix decoder the host-side tests call. The decoding itself is a pure
    //    function of the threshold, so the one relaxed retry below re-scores the
    //    very same prediction matrix instead of invoking the interpreter twice.
    final result = _decodeInto(
      _decodeOutput(),
      head: _head,
      letterbox: YoloLetterbox(
        inputWidth: _inputWidth,
        inputHeight: _inputHeight,
        scale: scale,
        padX: padX,
        padY: padY,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
      ),
      labels: _labels,
      confidenceThreshold: confidenceThreshold,
      retryConfidenceThreshold: fallbackConfidenceThreshold,
      iouThreshold: iouThreshold,
      maxDetections: maxDetections,
    );

    // 5. Diagnostics.
    debugPrint('TWP:yolo infer=${inferenceMs}ms rows=${_head.rows} '
        'raw=${result.rawCandidates} kept=${result.detections.length} '
        'conf=${result.threshold} normalizedBoxes=${result.boxesNormalized} '
        'asset=$_loadedAssetPath src=${sourceWidth}x$sourceHeight');

    return result.detections;
  }

  /// Public, interpreter-free entry point to the decode path [detect] runs after
  /// `Interpreter.run`: one raw prediction matrix in, boxes in source pixels out
  /// (class-agnostic NMS included). Host-side tests drive it with a synthetic
  /// `[84, 8400]` or `[25200, 85]` matrix; the app never needs to call it.
  static List<YoloDetection> decodeMatrix(
    Float32List logits, {
    required YoloHead head,
    required YoloLetterbox letterbox,
    List<String> labels = const <String>[],
    double confidenceThreshold = defaultConfidenceThreshold,
    double retryConfidenceThreshold = fallbackConfidenceThreshold,
    double iouThreshold = defaultIouThreshold,
    int maxDetections = defaultMaxDetections,
  }) =>
      _decodeInto(
        logits,
        head: head,
        letterbox: letterbox,
        labels: labels,
        confidenceThreshold: confidenceThreshold,
        retryConfidenceThreshold: retryConfidenceThreshold,
        iouThreshold: iouThreshold,
        maxDetections: maxDetections,
      ).detections;

  /// Matrix → candidates → NMS, with the single relaxed retry when the primary
  /// pass keeps nothing.
  static _DecodeResult _decodeInto(
    Float32List logits, {
    required YoloHead head,
    required YoloLetterbox letterbox,
    required List<String> labels,
    required double confidenceThreshold,
    required double retryConfidenceThreshold,
    required double iouThreshold,
    required int maxDetections,
  }) {
    final boxesNormalized = _boxesLookNormalized(logits, head, confidenceThreshold);
    final boxScaleX = boxesNormalized ? letterbox.inputWidth.toDouble() : 1.0;
    final boxScaleY = boxesNormalized ? letterbox.inputHeight.toDouble() : 1.0;
    final classBase = head.classBase;
    final step = head.step;
    final padX = letterbox.padX;
    final padY = letterbox.padY;
    final scale = letterbox.scale;
    final sourceWidth = letterbox.sourceWidth;
    final sourceHeight = letterbox.sourceHeight;

    List<_Candidate> collect(double threshold) {
      final candidates = <_Candidate>[];
      for (var row = 0; row < head.rows; row++) {
        final base = head.transposed ? row : row * head.cols;

        // Bounding box (centre form), in letterbox pixels.
        final double cx = logits[base] * boxScaleX;
        final double cy = logits[base + step] * boxScaleY;
        final double bw = logits[base + 2 * step] * boxScaleX;
        final double bh = logits[base + 3 * step] * boxScaleY;

        // Objectness gate first: score = obj × cls ≤ obj, so this cannot drop a
        // candidate that would have passed the threshold anyway.
        final double objectness =
            head.hasObjectness ? logits[base + 4 * step] : 1.0;
        if (objectness < threshold) continue;

        var bestClass = -1;
        var bestScore = 0.0;
        for (var c = 0; c < head.classCount; c++) {
          final score = logits[base + (classBase + c) * step];
          if (score > bestScore) {
            bestScore = score;
            bestClass = c;
          }
        }
        if (bestClass < 0) continue;

        final confidence = head.hasObjectness ? objectness * bestScore : bestScore;
        if (confidence < threshold) continue;

        final double left = ((cx - bw / 2) - padX) / scale;
        final double top = ((cy - bh / 2) - padY) / scale;
        final double right = ((cx + bw / 2) - padX) / scale;
        final double bottom = ((cy + bh / 2) - padY) / scale;
        if (right <= left || bottom <= top) continue;

        candidates.add(_Candidate(
          labelIndex: bestClass,
          score: confidence,
          x1: left.clamp(0.0, sourceWidth.toDouble()),
          y1: top.clamp(0.0, sourceHeight.toDouble()),
          x2: right.clamp(0.0, sourceWidth.toDouble()),
          y2: bottom.clamp(0.0, sourceHeight.toDouble()),
        ));
      }
      return candidates;
    }

    var usedThreshold = confidenceThreshold;
    var candidates = collect(usedThreshold);
    var kept = _nonMaxSuppression(candidates,
        iouThreshold: iouThreshold, maxDetections: maxDetections);
    if (kept.isEmpty && usedThreshold > retryConfidenceThreshold) {
      usedThreshold = retryConfidenceThreshold;
      candidates = collect(usedThreshold);
      kept = _nonMaxSuppression(candidates,
          iouThreshold: iouThreshold, maxDetections: maxDetections);
    }

    return _DecodeResult(
      detections: <YoloDetection>[
        for (final candidate in kept)
          YoloDetection(
            _labelFor(candidate.labelIndex, labels),
            candidate.score,
            candidate.x1,
            candidate.y1,
            candidate.x2,
            candidate.y2,
          ),
      ],
      rawCandidates: candidates.length,
      threshold: usedThreshold,
      boxesNormalized: boxesNormalized,
    );
  }

  /// Writes normalised RGB bytes into [_inputBuffer].
  void _fillInput(Uint8List rgbBytes) {
    final buffer = _inputBuffer;
    final pixels = math.min(_inputWidth * _inputHeight, rgbBytes.length ~/ 3);
    if (_inputIsChw) {
      for (var i = 0; i < pixels; i++) {
        final offset = i * 3;
        buffer[i] = rgbBytes[offset] / 255.0;
        buffer[pixels + i] = rgbBytes[offset + 1] / 255.0;
        buffer[pixels * 2 + i] = rgbBytes[offset + 2] / 255.0;
      }
    } else {
      for (var i = 0, offset = 0; i < pixels; i++, offset += 3) {
        buffer[i * 3] = rgbBytes[offset] / 255.0;
        buffer[i * 3 + 1] = rgbBytes[offset + 1] / 255.0;
        buffer[i * 3 + 2] = rgbBytes[offset + 2] / 255.0;
      }
    }
  }

  /// Staging floats → the exact bytes the live input tensor expects.
  ///
  /// Sizes were validated against `Tensor.numBytes()` at load time, so each
  /// branch below produces exactly the declared byte count — which is what the
  /// native `TfLiteTensorCopyFromBuffer` precondition checks.
  ByteBuffer _feedInput() {
    switch (_inputTensorType) {
      case TensorType.float32:
        return _inputBuffer.buffer;
      case TensorType.float16:
        final feed = _inputFeed;
        final staging = _inputBuffer;
        for (var i = 0; i < staging.length; i++) {
          final half = toHalfBits(staging[i]);
          feed[i * 2] = half & 0xFF;
          feed[i * 2 + 1] = (half >> 8) & 0xFF;
        }
        return feed.buffer;
      case TensorType.int8:
      case TensorType.uint8:
        final feed = _inputFeed;
        final staging = _inputBuffer;
        final scale = _inputScale == 0.0 ? 1.0 / 255.0 : _inputScale;
        for (var i = 0; i < staging.length; i++) {
          final quantised = (staging[i] / scale).round() + _inputZeroPoint;
          feed[i] = quantised < 0
              ? 0
              : (quantised > 255 ? 255 : quantised);
        }
        return feed.buffer;
      default:
        throw StateError('YoloDetector: unsupported input dtype '
            '${_inputTensorType.name}');
    }
  }

  /// Exposes the output buffer as float32, decoding half precision and
  /// dequantising int8/uint8 against the tensor's own scale and zero point.
  Float32List _decodeOutput() {
    final elements = _head.rows * _head.cols;
    switch (_outputTensorType) {
      case TensorType.float32:
        return Float32List.view(_outputBytes.buffer, 0, elements);
      case TensorType.float16:
        final decoded = _decodedOutput ??= Float32List(elements);
        final bytes = _outputBytes;
        for (var i = 0, o = 0; i < decoded.length; i++, o += 2) {
          decoded[i] = halfToDouble(bytes[o] | (bytes[o + 1] << 8));
        }
        return decoded;
      case TensorType.int8:
        final decoded = _decodedOutput ??= Float32List(elements);
        final bytes = _outputBytes;
        for (var i = 0; i < elements; i++) {
          final raw = bytes[i];
          decoded[i] = ((raw > 127 ? raw - 256 : raw) - _outputZeroPoint) *
              _outputScale;
        }
        return decoded;
      case TensorType.uint8:
        final decoded = _decodedOutput ??= Float32List(elements);
        final bytes = _outputBytes;
        for (var i = 0; i < elements; i++) {
          decoded[i] = (bytes[i] - _outputZeroPoint) * _outputScale;
        }
        return decoded;
      default:
        throw StateError('YoloDetector: unsupported output dtype '
            '${_outputTensorType.name}');
    }
  }

  /// Some exports emit `xywh` normalised to `0..1` instead of input pixels;
  /// sample the confident rows to tell the two apart.
  static bool _boxesLookNormalized(
      Float32List logits, YoloHead head, double confidenceThreshold) {
    final step = head.step;
    final classBase = head.classBase;
    var sampled = 0;
    var maxAbs = 0.0;
    for (var row = 0; row < head.rows && sampled < 256; row++) {
      final base = head.transposed ? row : row * head.cols;
      var gate = head.hasObjectness ? logits[base + 4 * step] : 0.0;
      if (!head.hasObjectness) {
        for (var c = 0; c < head.classCount; c++) {
          final score = logits[base + (classBase + c) * step];
          if (score > gate) gate = score;
        }
      }
      if (gate < confidenceThreshold) continue;
      sampled++;
      for (var c = 0; c < 4; c++) {
        final value = logits[base + c * step].abs();
        if (value > maxAbs) maxAbs = value;
      }
    }
    if (sampled == 0) return false;
    return maxAbs <= 2.0;
  }

  static List<_Candidate> _nonMaxSuppression(
    List<_Candidate> candidates, {
    required double iouThreshold,
    required int maxDetections,
  }) {
    if (candidates.isEmpty) return candidates;
    final sorted = List<_Candidate>.of(candidates)
      ..sort((a, b) => b.score.compareTo(a.score));
    final pool = sorted.length > maxCandidates
        ? sorted.sublist(0, maxCandidates)
        : sorted;
    final kept = <_Candidate>[];
    for (final candidate in pool) {
      var suppressed = false;
      for (final chosen in kept) {
        // Class-agnostic on purpose: a bottle and a cup on the same patch are
        // one object as far as the scanner is concerned.
        if (_intersectionOverUnion(chosen, candidate) > iouThreshold) {
          suppressed = true;
          break;
        }
      }
      if (suppressed) continue;
      kept.add(candidate);
      if (kept.length >= maxDetections) break;
    }
    return kept;
  }

  static double _intersectionOverUnion(_Candidate a, _Candidate b) {
    final x1 = math.max(a.x1, b.x1);
    final y1 = math.max(a.y1, b.y1);
    final x2 = math.min(a.x2, b.x2);
    final y2 = math.min(a.y2, b.y2);
    final intersection = math.max(0.0, x2 - x1) * math.max(0.0, y2 - y1);
    if (intersection <= 0) return 0.0;
    final union = a.area + b.area - intersection;
    return union <= 0 ? 0.0 : intersection / union;
  }

  static String _labelFor(int index, List<String> labels) {
    if (index >= 0 && index < labels.length) return labels[index];
    return 'class #$index';
  }

  /// IEEE-754 binary16 → double, used when a graph emits fp16 activations.
  static double halfToDouble(int half) {
    final sign = (half & 0x8000) == 0 ? 1.0 : -1.0;
    final exponent = (half >> 10) & 0x1F;
    final mantissa = half & 0x03FF;
    if (exponent == 0) {
      return sign * mantissa * 5.9604644775390625e-8; // 2^-24
    }
    if (exponent == 0x1F) {
      return mantissa == 0 ? sign * double.infinity : double.nan;
    }
    return sign *
        math.pow(2.0, exponent - 15).toDouble() *
        (1.0 + mantissa / 1024.0);
  }

  /// double → IEEE-754 binary16 bits, used when a graph declares a fp16 input
  /// tensor: round to nearest with ties up, subnormals and overflow handled the
  /// way TFLite's own converter writes them.
  static int toHalfBits(double value) {
    _halfScratch[0] = value;
    final bits = _halfScratchBits[0];
    final sign = (bits >> 16) & 0x8000;
    final rawExponent = (bits >> 23) & 0xFF;
    var mantissa = bits & 0x7FFFFF;
    if (rawExponent == 0xFF) {
      return sign | 0x7C00 | (mantissa == 0 ? 0 : 0x200);
    }
    final exponent = rawExponent - 127 + 15;
    if (exponent <= 0) {
      if (exponent < -10) return sign;
      mantissa = (mantissa | 0x800000) >> (1 - exponent);
      return sign | ((mantissa + 0x1000) >> 13);
    }
    if (exponent >= 31) return sign | 0x7C00;
    return sign | (exponent << 10) | ((mantissa + 0x1000) >> 13);
  }

  /// Releases the native interpreter.
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}

/// Decode outcome: the kept detections plus the diagnostics `detect` logs.
class _DecodeResult {
  const _DecodeResult({
    required this.detections,
    required this.rawCandidates,
    required this.threshold,
    required this.boxesNormalized,
  });

  final List<YoloDetection> detections;
  final int rawCandidates;
  final double threshold;
  final bool boxesNormalized;
}

/// Internal candidate row, boxes already in source-image pixels.
class _Candidate {
  const _Candidate({
    required this.labelIndex,
    required this.score,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  final int labelIndex;
  final double score;
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  double get area => math.max(0.0, x2 - x1) * math.max(0.0, y2 - y1);
}
