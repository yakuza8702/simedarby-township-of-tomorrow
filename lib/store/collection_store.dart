/// Collection state: entries, points, and the (placeholder) verification gate.
///
/// Points are a PLACEHOLDER economy — every verified action is +1. Verification
/// is enforced client-side by the Go core for now (action whitelist + proof
/// photo must not be a re-use of the entry photo, via DCT pHash distance);
/// real anti-exploit verification (geotag near registered bins, weight
/// stations, hash-chained proofs) lands with the backend task.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../types.dart';
import '../services/township_core.dart';

class CollectionStore extends ChangeNotifier {
  static const actions = ['recycle', 'remove', 'dispose'];

  final List<CollectionEntry> _entries = [];
  List<CollectionEntry> get entries => List.unmodifiable(_entries);
  int get points => _entries.fold(0, (s, e) => s + e.pointsAwarded);
  int get pending => _entries.where((e) => e.status == 'collected').length;

  File? _file;

  Future<void> load() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/collection.json');
    if (await _file!.exists()) {
      try {
        final list = (jsonDecode(await _file!.readAsString()) as List)
            .cast<Map<String, dynamic>>();
        _entries
          ..clear()
          ..addAll([for (final j in list) CollectionEntry.fromJson(j)]);
      } catch (e) {
        debugPrint('TWP:ERROR collection load: $e');
      }
    }
    notifyListeners();
  }

  Future<void> _save() async {
    if (_file == null) return;
    await _file!.writeAsString(
        jsonEncode([for (final e in _entries) e.toJson()]));
  }

  /// Add an entry from a confirmed scan. The bundled Go core (0.2.1) has the
  /// fixed DCT loop bounds, so the production path calls
  /// `TownshipCore.pHashFile`; [photoHash] stays as an optional override
  /// (test/demo seam only).
  Future<CollectionEntry> add({
    required String itemLabel,
    required WasteCategory category,
    required int confidence,
    required String photoPath,
    String? photoHash,
  }) async {
    final hash = photoHash ?? await TownshipCore.pHashFile(photoPath);
    final entry = CollectionEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      itemLabel: itemLabel,
      category: category,
      confidence: confidence,
      photoPath: photoPath,
      photoHash: hash,
      status: 'collected',
      addedAt: DateTime.now(),
    );
    _entries.insert(0, entry);
    await _save();
    notifyListeners();
    return entry;
  }

  /// Complete a task with a proof photo → Go verification → +1 placeholder point.
  Future<(bool, String)> completeAction(CollectionEntry entry, String action,
      String proofPath) async {
    final proofBytes = await File(proofPath).readAsBytes();
    final report = await TownshipCore.verifyAction(action, entry.photoHash, proofBytes);
    if (report.accepted) {
      final done = CollectionEntry(
        id: entry.id,
        itemLabel: entry.itemLabel,
        category: entry.category,
        confidence: entry.confidence,
        photoPath: entry.photoPath,
        photoHash: entry.photoHash,
        status: 'done',
        action: action,
        pointsAwarded: entry.pointsAwarded + report.points,
        addedAt: entry.addedAt,
        doneAt: DateTime.now(),
        verifyReason: report.reason,
      );
      final idx = _entries.indexWhere((e) => e.id == entry.id);
      _entries[idx] = done;
      await _save();
      notifyListeners();
    }
    return (report.accepted, report.reason);
  }

  /// Remove every entry (and with it the points) — the demo-data reset path.
  Future<void> clearAll() async {
    _entries.clear();
    await _save();
    notifyListeners();
  }

  /// Copy a captured photo into the app's documents dir so it survives
  /// cache clears of the camera's temp storage.
  Future<String> persistPhoto(String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final photos = Directory('${dir.path}/photos')..createSync(recursive: true);
    final dest = '${photos.path}/${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(sourcePath).copy(dest);
    return dest;
  }

  static Float32List placeholderVec() => Float32List(0);
}
