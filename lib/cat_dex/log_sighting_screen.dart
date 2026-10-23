/// Log a sighting: the Dex's manual-entry flow.
///
/// Pick a photo from the camera roll → run it through the on-device vision
/// pipeline → gate it with the shared [CatCatchGate] (same rule as the scan
/// card: a confident cat no other animal outranks) → cut the sticker, file the
/// sighting with `itemLabel: 'stray cat'`, `source: 'camera roll'` and the
/// current precinct → offer a jump straight to the Dex.
///
/// Offline: the photo never leaves the device. Every collaborator is
/// injectable (`store` / `pipeline` / `cutter` / `precinct`, plus `pickPhoto`
/// and `analyse` seams for widget tests) — the shipped screen leaves them null
/// and the defaults resolve through [App.instance].
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../theme.dart';

import '../main.dart' show App;
import '../services/vision_pipeline.dart';
import '../types.dart';
import 'cat_catch_gate.dart';
import 'cat_dex_models.dart';
import 'cat_dex_store.dart';
import 'sticker_cutter.dart';

class LogSightingScreen extends StatefulWidget {
  /// `null` → `App.instance.catDex`; injected in tests.
  final CatDexStore? store;

  /// `null` → `App.instance.pipeline`; injected in tests.
  final VisionPipeline? pipeline;

  /// `null` → `StickerCutter()` (app documents dir).
  final StickerCutter? cutter;

  /// `null` → the township store's precinct, else [fallbackPrecinct].
  final String? precinct;

  /// Test seam: gallery pick. `null` → `ImagePicker().pickImage(gallery)`.
  final Future<File?> Function()? pickPhoto;

  /// Test seam: on-device analysis. `null` → `pipeline.analyseFile(path)`
  /// with the result's detector boxes threaded through.
  final Future<List<DetectedObject>?> Function(String path)? analyse;

  /// Test seam: photo byte source. `null` → `photo.readAsBytes()` (real IO,
  /// which widget tests must not trigger inside the fake-async zone).
  final Future<Uint8List> Function(File photo)? readBytes;

  const LogSightingScreen({
    super.key,
    this.store,
    this.pipeline,
    this.cutter,
    this.precinct,
    this.pickPhoto,
    this.analyse,
    this.readBytes,
  });

  @override
  State<LogSightingScreen> createState() => _LogSightingScreenState();
}

/// The item label a logged sighting is filed under.
const String kLogSightingItemLabel = 'stray cat';

/// The provenance a logged sighting is filed under.
const String kLogSightingSource = 'camera roll';

class _LogSightingScreenState extends State<LogSightingScreen> {
  bool _busy = false;

  /// Inline feedback: the no-cat hint or the escape message; null when clean.
  String? _message;

  /// Set once a sighting is filed — drives the "Added to the Dex" panel.
  CatSighting? _added;

  /// Precinct this assignment is filed under; never throws.
  String _precinct() {
    final injected = widget.precinct;
    if (injected != null && injected.isNotEmpty) return injected;
    try {
      final fromStore = App.instance.township.precinct;
      return fromStore.isEmpty ? fallbackPrecinct : fromStore;
    } catch (e) {
      debugPrint('TWP:ERROR log sighting precinct: $e');
      return fallbackPrecinct;
    }
  }

  /// Precinct used when the township store cannot be read.
  static const String fallbackPrecinct = 'Precinct A';

  Future<File?> _pick() {
    final custom = widget.pickPhoto;
    if (custom != null) return custom();
    return () async {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      return picked == null ? null : File(picked.path);
    }();
  }

  Future<List<DetectedObject>?> _analyse(String path) {
    final custom = widget.analyse;
    if (custom != null) return custom(path);
    return () async {
      final result =
          await (widget.pipeline ?? App.instance.pipeline).analyseFile(path);
      return result?.objects;
    }();
  }

  /// gallery pick → analyse → gate → sticker → Dex entry.
  Future<void> _log() async {
    setState(() {
      _busy = true;
      _message = null;
      _added = null;
    });
    try {
      final photo = await _pick();
      if (photo == null) {
        // Cancelled picker: no message, just back to idle.
        if (mounted) setState(() => _busy = false);
        return;
      }
      final objects = await _analyse(photo.path);
      if (objects == null) throw StateError('analysis failed');
      final box = CatCatchGate.catchableCatBox(objects);
      if (box == null) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _message = 'No cat found in that photo. Try a clearer shot.';
        });
        return;
      }
      final bytes = await (widget.readBytes ?? ((File f) => f.readAsBytes()))(photo);
      final decoded = img.decodeImage(bytes);
      final scale = decoded == null
          ? 1.0
          : CatCatchGate.scaleToOriginal(decoded.width, decoded.height);
      final cut = await (widget.cutter ?? StickerCutter()).catchCat(
        imageBytes: bytes,
        boxX: box.x1 * scale,
        boxY: box.y1 * scale,
        boxW: box.width * scale,
        boxH: box.height * scale,
        label: box.label,
        precinct: _precinct(),
        source: kLogSightingSource,
      );
      final filed = await (widget.store ?? App.instance.catDex).addSighting(
        id: cut.id,
        label: cut.label,
        name: cut.name,
        itemLabel: kLogSightingItemLabel,
        precinct: cut.precinct,
        source: cut.source,
        originalPath: cut.originalPath,
        stickerPath: cut.stickerPath,
        capturedAt: cut.capturedAt,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _added = filed;
      });
    } catch (e) {
      debugPrint('TWP:ERROR log sighting: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'The cat slipped away — try another photo';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log a sighting')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _intro(context),
          const SizedBox(height: 14),
          if (_added != null)
            _successPanel(context)
          else ...[
            _pickButton(),
            if (_busy) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_message != null) ...[
              const SizedBox(height: 16),
              _messageCard(_message!),
            ],
          ],
        ],
      ),
    );
  }

  Widget _intro(BuildContext context) {
    return Card(
      color: context.tTintGreen,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.pets, color: context.tBrand),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Missed one on a scan run?',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
                'Pick a photo from your camera roll. The Cat Distribution '
                'System checks it right here on your phone — the photo never '
                'leaves your device.',
                style: TextStyle(fontSize: 13, color: context.tMuted)),
          ],
        ),
      ),
    );
  }

  Widget _pickButton() {
    return Semantics(
      button: true,
      label: 'Log a sighting from the camera roll',
      child: FilledButton.icon(
        icon: const Icon(Icons.photo_library_outlined),
        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
        onPressed: _busy ? null : _log,
        label: const Text('Choose from gallery'),
      ),
    );
  }

  /// Flat card, warn-amber flag + ink text — a hint, not an error banner.
  Widget _messageCard(String message) {
    return Card(
      color: context.tAmberWash,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const Icon(Icons.pets_outlined, color: kWarnAmber),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message,
                style: TextStyle(fontSize: 13, color: context.tAmberInk)),
          ),
        ]),
      ),
    );
  }

  Widget _successPanel(BuildContext context) {
    final added = _added!;
    return Card(
      color: context.tTintGreen,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.check_circle_outline,
                color: context.tBrand, size: 36),
            const SizedBox(height: 10),
            Text('Added to the Dex',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('${added.name} · ${added.precinct}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: context.tMuted)),
            const SizedBox(height: 14),
            Semantics(
              button: true,
              label: 'View Cat Dex',
              child: FilledButton.icon(
                icon: const Icon(Icons.grid_view_outlined),
                style:
                    FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () =>
                    Navigator.of(context).pushNamed('/cat-dex'),
                label: const Text('View Cat Dex'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
