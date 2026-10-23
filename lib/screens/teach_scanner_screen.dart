/// Teach the scanner: one clear photo → name the item → pick the stream → the
/// capture becomes a kNN reference the scan uses from then on. Fully offline.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../services/reference_library.dart';
import '../store/township_store.dart';
import '../theme.dart';
import '../types.dart';

// ── palette: every colour below is a theme lookup (TownshipPalette), so the
//    screen keeps its exact board values in light and follows the dark theme.

/// Trimmed item names shorter than this are typos, not items.
const int _minNameLength = 2;
/// Trimmed item names longer than this are pasted paragraphs, not items.
const int _maxNameLength = 40;

/// One resident-facing stream chip: [label] is exactly what the chip (and the
/// taught list) shows; [category] is the [WasteCategory] the classifier runs.
class _StreamChoice {
  final String label;
  final WasteCategory category;
  const _StreamChoice(this.label, this.category);
}

/// The six streams in render order (WO-06): Recyclable, Organic, E-waste,
/// Hazardous, Paper, Other.
///
/// `Paper` teaches as [WasteCategory.Recyclable] and `Other` as
/// [WasteCategory.Landfill] for the classifier; the chip label travels with
/// the save as `streamLabel` so the taught list still reads Paper / Other.
const List<_StreamChoice> _streamChoices = [
  _StreamChoice('Recyclable', WasteCategory.Recyclable),
  _StreamChoice('Organic', WasteCategory.Organic),
  _StreamChoice('E-waste', WasteCategory.Ewaste),
  _StreamChoice('Hazardous', WasteCategory.Hazardous),
  _StreamChoice('Paper', WasteCategory.Recyclable),
  _StreamChoice('Other', WasteCategory.Landfill),
];

class TeachScannerScreen extends StatefulWidget {
  final TownshipStore store;
  final ReferenceLibrary refs;

  /// Test seam: a photo path to mount with, so widget tests can exercise the
  /// live enabled-state listener without a camera. Always null in production
  /// (the camera capture in [_capture] is the only producer) — not a product
  /// feature.
  final String? initialPhotoPath;

  const TeachScannerScreen({
    super.key,
    required this.store,
    required this.refs,
    this.initialPhotoPath,
  });

  @override
  State<TeachScannerScreen> createState() => _TeachScannerScreenState();
}

class _TeachScannerScreenState extends State<TeachScannerScreen> {
  final _nameCtrl = TextEditingController();
  _StreamChoice? _stream;
  String? _photoPath;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _photoPath = widget.initialPhotoPath;
    // Every keystroke re-evaluates the Add button (and the inline name
    // errors) — no extra tap required. Removed again in [dispose].
    _nameCtrl.addListener(_revalidateOnNameChange);
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_revalidateOnNameChange);
    _nameCtrl.dispose();
    super.dispose();
  }

  void _revalidateOnNameChange() {
    if (mounted) setState(() {});
  }

  /// The name rule, inline under the field: `null` while the field is still
  /// empty (nothing to complain about — the button simply stays gated),
  /// otherwise 2–40 trimmed characters and no case-insensitive duplicate of
  /// anything already in [TownshipStore.taughtRefs].
  String? get _nameError {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return null;
    if (name.length < _minNameLength || name.length > _maxNameLength) {
      return 'Item name must be $_minNameLength–$_maxNameLength characters.';
    }
    if (_isDuplicateName(name)) {
      return 'You already taught “$name”. Try a different name.';
    }
    return null;
  }

  /// Case-insensitive duplicate check against everything already taught.
  bool _isDuplicateName(String trimmedName) {
    final lower = trimmedName.toLowerCase();
    return widget.store.taughtRefs.any((t) {
      final label = t['label'];
      return label is String && label.toLowerCase() == lower;
    });
  }

  /// The Add button gate: photo + valid, unique name + stream + not saving.
  /// Re-evaluated on every keystroke through the controller listener
  /// registered in [initState] and dropped in [dispose].
  bool get _canSave {
    if (_photoPath == null || _stream == null || _saving) return false;
    final name = _nameCtrl.text.trim();
    if (name.length < _minNameLength || name.length > _maxNameLength) {
      return false;
    }
    return !_isDuplicateName(name);
  }

  @override
  Widget build(BuildContext context) {
    final nameError = _nameError;
    return Scaffold(
      appBar: AppBar(title: const Text('Teach the scanner')),
      // Children run top-to-bottom in one column, so visual order is focus
      // order: photo → item name → stream chips → Add to the scanner.
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Take one clear photo of the item. The scan will recognise it next time — offline, forever.',
            style: TextStyle(fontSize: 13, color: context.tMuted),
          ),
          const SizedBox(height: 16),
          if (_photoPath == null)
            OutlinedButton.icon(
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Take a photo of the item'),
              onPressed: _capture,
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_photoPath!),
                height: 200,
                fit: BoxFit.cover,
                // A vanished or undecodable capture renders a placeholder
                // instead of throwing — the widget tests mount with
                // [TeachScannerScreen.initialPhotoPath].
                errorBuilder: (context, error, stackTrace) => SizedBox(
                  height: 200,
                  child: Center(
                      child: Icon(Icons.broken_image, color: context.tGhost)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _capture,
              child: const Text('Retake'),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: 'Item name',
              hintText: 'e.g. Milo tin',
              border: const OutlineInputBorder(),
              errorText: nameError,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Which stream?',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in _streamChoices) _streamChip(choice),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: context.tScheme.primary,
              disabledBackgroundColor:
                  context.tScheme.primary.withValues(alpha: 0.38),
              foregroundColor: context.tScheme.onPrimary,
              disabledForegroundColor:
                  context.tScheme.onSurface.withValues(alpha: 0.38),
              // Pill corners: radius 20 against the default 40dp height.
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.school),
            label: const Text('Add to the scanner'),
            onPressed: _canSave ? _save : null,
          ),
          const Divider(height: 32),
          Text('Taught so far (${widget.store.taughtRefs.length})',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          for (final t in widget.store.taughtRefs.take(10))
            ListTile(
              dense: true,
              leading: (t['photoPath'] as String?)?.isEmpty ?? true
                  ? const Icon(Icons.image)
                  : Image.file(File(t['photoPath'] as String),
                      width: 40, height: 40, fit: BoxFit.cover),
              title: Text(t['label'] as String? ?? ''),
              subtitle: Text(t['stream'] as String? ?? '',
                  style: const TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }

  /// One stream chip: 10dp corners, tinted selection, and an explicit
  /// padded (≥44dp) tap target that does not depend on the ambient theme.
  /// [ChoiceChip] carries its own `Semantics(button:, selected:)`, so the
  /// selected state is announced to screen readers without a wrapper.
  Widget _streamChip(_StreamChoice choice) {
    final selected = _stream?.label == choice.label;
    return ChoiceChip(
      label: Text(choice.label),
      selected: selected,
      onSelected: (_) => setState(() => _stream = choice),
      selectedColor: context.tTintGreen,
      backgroundColor: context.tCard,
      labelStyle: TextStyle(
        color: selected ? context.tBrand : context.tInk,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
      side: BorderSide(color: selected ? context.tBrand : context.tGhost),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }

  /// Single camera capture — one photo per taught item (WO-06: "one clear
  /// photo", Retake only, never a multi-photo set).
  Future<void> _capture() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera);
    if (picked == null) return;
    final dest = await widget.store.persistPhoto(picked.path);
    setState(() => _photoPath = dest);
  }

  /// Path of the photo the embedder is actually handed.
  ///
  /// A camera capture is several megapixels while the embedder's input is
  /// 224 px: decoding the full frame is the slow half of "Add to the scanner".
  /// Downscaling the longest side to [_trainSide] first shrinks the bytes the
  /// embedder chews through without changing what it learns. Never throws —
  /// if the copy cannot be made, teaching falls back to the original file.
  Future<String> _trainCopy(String sourcePath) async {
    try {
      final copy = await Isolate.run(() => _writeTrainCopy(sourcePath));
      return copy ?? sourcePath;
    } catch (e) {
      debugPrint('TWP:ERROR train downscale: $e');
      return sourcePath;
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final photoPath = _photoPath!;
    final label = _nameCtrl.text.trim().toLowerCase();
    final choice = _stream!;
    // Teach from a small copy: the embedder reads 224 px, so handing it the
    // full-resolution capture only buys a slow decode (see [_writeTrainCopy]).
    final trainPath = await _trainCopy(photoPath);
    final ok = await widget.refs.teach(
      photoPath: trainPath,
      label: label,
      stream: choice.category,
      // The taught list displays the chip's own word — 'Paper', 'Other' —
      // while the classifier keeps WasteCategory.name (Recyclable, Landfill).
      streamLabel: choice.label,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _photoPath = widget.initialPhotoPath;
      _stream = null;
      _nameCtrl.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? context.tScheme.primary : context.tScheme.error,
      content: Text(
        ok
            ? 'Learned! The scanner recognises it now.'
            : 'Could not embed that photo — try again',
        style: TextStyle(
          color: ok ? context.tScheme.onPrimary : context.tScheme.onError,
        ),
      ),
    ));
  }
}

/// Longest side, in pixels, of the copy handed to the embedder when teaching.
const int _trainSide = 512;

/// Worker-isolate half of the train-copy downscale: decode [sourcePath], shrink
/// the longest side to [_trainSide] and write the JPEG beside the original.
///
/// Returns the smaller path, [sourcePath] when it is already small enough, or
/// null when the photo cannot be decoded.
String? _writeTrainCopy(String sourcePath) {
  final decoded = img.decodeImage(File(sourcePath).readAsBytesSync());
  if (decoded == null) return null;

  final longest = math.max(decoded.width, decoded.height);
  if (longest <= _trainSide) return sourcePath;

  final scale = _trainSide / longest;
  final small = img.copyResize(
    decoded,
    width: math.max(1, (decoded.width * scale).round()),
    height: math.max(1, (decoded.height * scale).round()),
    interpolation: img.Interpolation.average,
  );

  final dot = sourcePath.lastIndexOf('.');
  final stem =
      dot > sourcePath.lastIndexOf('/') ? sourcePath.substring(0, dot) : sourcePath;
  final dest = '${stem}_train$_trainSide.jpg';
  File(dest).writeAsBytesSync(img.encodeJpg(small, quality: 85));
  return dest;
}
